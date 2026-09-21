import Foundation
import Combine
import Network
import Security
import CryptoKit

/// Foreground-only, authenticated local transport. It never contacts a server.
@MainActor
final class NearbySync: ObservableObject {
    @Published private(set) var status = "Not paired"
    @Published private(set) var lastSync: Date?
    @Published private(set) var isPaired = false
    @Published private(set) var pendingConfirmation = false
    @Published private(set) var invitationCode: String?
    @Published private(set) var confirmationCode = ""
    @Published var errorMessage: String?
    var snapshotProvider: (() throws -> Data)?
    var snapshotReceiver: ((Data) throws -> Void)?

    private struct Credentials: Codable {
        var version = 1
        var familyID: UUID
        var secret: Data
        var deviceID: UUID
        var isHost: Bool
        var peerID: UUID?
    }
    private struct Invite: Codable {
        var version: Int
        var familyID: UUID
        var secret: Data
    }
    private struct Message: Codable {
        var version = 1
        var kind: String
        var device: UUID?
        var family: UUID?
        var transfer: UUID?
        var size: Int?
        var digest: String?
        var index: Int?
        var bytes: Data?
    }
    private struct Incoming {
        var id: UUID
        var size: Int
        var digest: String
        var nextIndex = 0
        var data = Data()
    }
    private var credentials: Credentials?
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var active = false
    private var remoteID: UUID?
    private var remoteApproved = false
    private var localApproved = false
    private var outgoing: UUID?
    private var incoming: Incoming?
    private var queuedSync = false
    private var receivedSnapshot = false
    private var sentSnapshot = false
    private var reconnect: Task<Void, Never>?
    private var transferTimeout: Task<Void, Never>?
    private var pairingTimeout: Task<Void, Never>?
    private var failedEndpoints: [String: Date] = [:]
    private var sendQueue: [Data] = []
    private var sending = false
    private let maxSnapshot = 16 * 1024 * 1024
    private let maxFrame = 128 * 1024
    private let chunkSize = 48 * 1024
    private let keychainService = "com.dansullivan.babytracker.nearby.v1"
    private let serviceType = "_baby-local._tcp"

    #if TRANSPORT_TESTING
    private var ephemeralTestStorage = false
    init(testFamilyID: UUID, secret: Data, host: Bool, deviceID: UUID = UUID(), peerID: UUID? = nil) {
        ephemeralTestStorage = true
        credentials = Credentials(familyID: testFamilyID, secret: secret, deviceID: deviceID, isHost: host, peerID: peerID)
        isPaired = peerID != nil
    }
    func testSendUnsupportedVersion() {
        send(Message(version: 99, kind: "begin", transfer: UUID(), size: 0, digest: Self.hash(Data())))
    }
    #endif

    init() {
        do {
            credentials = try loadCredentials()
            if let credentials {
                guard credentials.version == 1, credentials.secret.count == 32 else { throw SyncFailure.invalidPairing }
                isPaired = credentials.peerID != nil
                status = isPaired ? "Open both apps nearby to sync" : "Finish pairing"
            }
        } catch { errorMessage = "Pairing could not be loaded. \(error.localizedDescription)" }
    }

    func createInvitation() {
        guard credentials?.peerID == nil else { errorMessage = "Unpair before connecting a different phone."; return }
        do {
            var key = Data(count: 32)
            let result = key.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
            guard result == errSecSuccess else { throw SyncFailure.keychain(result) }
            let value = Credentials(familyID: UUID(), secret: key, deviceID: UUID(), isHost: true)
            try saveCredentials(value)
            credentials = value
            let invite = Invite(version: 1, familyID: value.familyID, secret: key)
            invitationCode = "baby-local-v1:" + (try JSONEncoder().encode(invite)).base64EncodedString()
            restart()
            status = "Scan this code on the other phone"
        } catch { errorMessage = error.localizedDescription }
    }

    func acceptInvitation(_ text: String) {
        guard credentials?.peerID == nil else { errorMessage = "This phone is already paired."; return }
        do {
            let prefix = "baby-local-v1:"
            guard text.hasPrefix(prefix), text.count < 2048,
                  let data = Data(base64Encoded: String(text.dropFirst(prefix.count))) else { throw SyncFailure.invalidPairing }
            let invite = try JSONDecoder().decode(Invite.self, from: data)
            guard invite.version == 1, invite.secret.count == 32 else { throw SyncFailure.invalidPairing }
            let value = Credentials(familyID: invite.familyID, secret: invite.secret, deviceID: UUID(), isHost: false)
            try saveCredentials(value)
            credentials = value
            invitationCode = nil
            restart()
        } catch { errorMessage = error.localizedDescription }
    }

    func confirmPairing() {
        guard var value = credentials, let peer = remoteID, pendingConfirmation else { return }
        do {
            value.peerID = peer
            try saveCredentials(value)
            credentials = value
            localApproved = true
            pendingConfirmation = false
            invitationCode = nil
            send(Message(kind: "approve"))
            beginIfApproved()
        } catch { errorMessage = error.localizedDescription }
    }

    func forgetPairing() {
        stop()
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService, kSecAttrAccount as String: "pairing"]
        let result = SecItemDelete(query as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else {
            errorMessage = SyncFailure.keychain(result).localizedDescription; return
        }
        credentials = nil
        isPaired = false
        invitationCode = nil
        lastSync = nil
        status = "Not paired — history remains on this phone"
    }

    func start() {
        guard !active else { return }
        active = true
        startDiscovery()
    }

    func stop() {
        active = false
        reconnect?.cancel(); reconnect = nil
        transferTimeout?.cancel(); transferTimeout = nil
        pairingTimeout?.cancel(); pairingTimeout = nil
        browser?.cancel(); browser = nil
        listener?.cancel(); listener = nil
        let old = connection; connection = nil; old?.cancel()
        resetSession()
        if credentials != nil { status = "Open both apps nearby to sync" }
    }

    func requestSync() {
        guard localApproved && remoteApproved, connection != nil else {
            queuedSync = true
            if isPaired { status = "Changes stay on this phone until nearby sync" }
            return
        }
        guard outgoing == nil else { queuedSync = true; return }
        do {
            guard let provider = snapshotProvider else { throw SyncFailure.unavailable }
            let data = try provider()
            guard data.count <= maxSnapshot else { throw SyncFailure.tooLarge }
            let id = UUID()
            outgoing = id
            sentSnapshot = false
            queuedSync = false
            status = "Syncing nearby…"
            armTimeout()
            send(Message(kind: "begin", transfer: id, size: data.count, digest: Self.hash(data)))
            var index = 0
            for offset in stride(from: 0, to: data.count, by: chunkSize) {
                send(Message(kind: "chunk", transfer: id, index: index,
                    bytes: data.subdata(in: offset..<min(offset + chunkSize, data.count))))
                index += 1
            }
            send(Message(kind: "end", transfer: id))
        } catch { fail(error) }
    }

    private func restart() { stop(); start() }

    private func parameters() throws -> NWParameters {
        guard let value = credentials else { throw SyncFailure.invalidPairing }
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_append_tls_ciphersuite(options, tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!)
        let key = value.secret.withUnsafeBytes { DispatchData(bytes: $0) }
        let identity = Data(value.familyID.uuidString.utf8).withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(options, key as NSObject as! dispatch_data_t, identity as NSObject as! dispatch_data_t)
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 15
        let params = NWParameters(tls: tls, tcp: tcp)
        params.includePeerToPeer = true
        params.prohibitedInterfaceTypes = [.cellular]
        return params
    }

    private func startDiscovery() {
        guard active, let value = credentials else { return }
        do {
            status = isPaired ? "Looking for your paired phone…" : "Waiting for the other phone…"
            if value.isHost {
                let listener = try NWListener(using: parameters())
                self.listener = listener
                listener.service = NWListener.Service(name: UUID().uuidString, type: serviceType)
                listener.newConnectionHandler = { [weak self, weak listener] candidate in
                    Task { @MainActor in
                        guard let self, let listener, self.listener === listener, self.active, self.connection == nil else { candidate.cancel(); return }
                        self.attach(candidate)
                    }
                }
                listener.stateUpdateHandler = { [weak self, weak listener] state in
                    if case .failed(let error) = state {
                        Task { @MainActor in
                            guard let self, let listener, self.listener === listener else { return }
                            self.discoveryFailed(error)
                        }
                    }
                }
                listener.start(queue: .main)
            } else {
                let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: try parameters())
                self.browser = browser
                browser.browseResultsChangedHandler = { [weak self, weak browser] results, _ in
                    Task { @MainActor in
                        guard let self, let browser, self.browser === browser, self.active, self.connection == nil else { return }
                        let candidates = results.sorted(by: { String(describing: $0.endpoint) < String(describing: $1.endpoint) })
                        guard let endpoint = candidates.first(where: {
                            self.failedEndpoints[String(describing: $0.endpoint), default: .distantPast] < Date()
                        })?.endpoint else { self.scheduleDiscoveryRetry(); return }
                        do { self.attach(NWConnection(to: endpoint, using: try self.parameters())) }
                        catch { self.fail(error) }
                    }
                }
                browser.stateUpdateHandler = { [weak self, weak browser] state in
                    if case .failed(let error) = state {
                        Task { @MainActor in
                            guard let self, let browser, self.browser === browser else { return }
                            self.discoveryFailed(error)
                        }
                    }
                }
                browser.start(queue: .main)
            }
        } catch { fail(error) }
    }

    private func attach(_ candidate: NWConnection) {
        resetSession()
        connection = candidate
        pairingTimeout = Task { [weak self, weak candidate] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, let self, let candidate, self.connection === candidate else { return }
            self.fail(SyncFailure.timeout)
        }
        candidate.stateUpdateHandler = { [weak self, weak candidate] state in
            Task { @MainActor in
                guard let self, let candidate, self.connection === candidate else { return }
                switch state {
                case .ready:
                    self.pairingTimeout?.cancel()
                    guard let value = self.credentials else { return }
                    self.status = "Secure nearby connection"
                    self.send(Message(kind: "hello", device: value.deviceID, family: value.familyID))
                    self.readHeader(candidate)
                    self.pairingTimeout = Task { [weak self, weak candidate] in
                        try? await Task.sleep(for: .seconds(120))
                        guard !Task.isCancelled, let self, let candidate, self.connection === candidate,
                              !(self.localApproved && self.remoteApproved) else { return }
                        self.fail(SyncFailure.timeout)
                    }
                case .failed(let error): self.fail(error)
                case .waiting(let error): self.fail(error)
                case .cancelled: self.disconnectAndRetry()
                default: break
                }
            }
        }
        candidate.start(queue: .main)
    }

    private func readHeader(_ current: NWConnection) {
        readExactly(4, on: current) { [weak self, weak current] data in
            guard let self, let current else { return }
            let size = data.reduce(0) { ($0 << 8) | Int($1) }
            guard size > 0, size <= self.maxFrame else { self.fail(SyncFailure.invalidMessage); return }
            self.readExactly(size, on: current) { [weak self, weak current] payload in
                guard let self, let current else { return }
                do {
                    try self.handle(JSONDecoder().decode(Message.self, from: payload))
                    if self.connection === current { self.readHeader(current) }
                } catch { self.fail(error) }
            }
        }
    }

    private func readExactly(_ count: Int, on current: NWConnection, accumulated: Data = Data(), completion: @escaping (Data) -> Void) {
        current.receive(minimumIncompleteLength: 1, maximumLength: count - accumulated.count) { [weak self, weak current] bytes, _, done, error in
            Task { @MainActor in
                guard let self, let current, self.connection === current else { return }
                if let error { self.fail(error); return }
                var data = accumulated
                if let bytes { data.append(bytes) }
                if data.count == count { completion(data) }
                else if done { self.disconnectAndRetry() }
                else { self.readExactly(count, on: current, accumulated: data, completion: completion) }
            }
        }
    }

    private func handle(_ message: Message) throws {
        guard message.version == 1 else { throw SyncFailure.incompatible }
        switch message.kind {
        case "hello":
            guard remoteID == nil, let value = credentials, message.family == value.familyID,
                  let id = message.device, id != value.deviceID else { throw SyncFailure.invalidMessage }
            if let pinned = value.peerID, pinned != id { throw SyncFailure.unknownPeer }
            remoteID = id
            if value.peerID == id {
                localApproved = true
                send(Message(kind: "approve"))
            } else {
                let ids = [id.uuidString, value.deviceID.uuidString].sorted().joined(separator: ":")
                let digest = SHA256.hash(data: Data((value.familyID.uuidString + ids).utf8))
                let number = digest.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } % 1_000_000
                confirmationCode = String(format: "%06u", number)
                pendingConfirmation = true
                status = "Compare the code on both phones"
            }
        case "approve":
            guard remoteID != nil else { throw SyncFailure.invalidMessage }
            remoteApproved = true
            beginIfApproved()
        default:
            guard localApproved, remoteApproved else { throw SyncFailure.unknownPeer }
            try handleTransfer(message)
        }
    }

    private func beginIfApproved() {
        guard localApproved, remoteApproved else { return }
        pairingTimeout?.cancel(); pairingTimeout = nil
        isPaired = true
        pendingConfirmation = false
        invitationCode = nil
        requestSync()
    }

    private func handleTransfer(_ message: Message) throws {
        switch message.kind {
        case "begin":
            guard incoming == nil, let id = message.transfer, let size = message.size,
                  size >= 0, size <= maxSnapshot, let digest = message.digest, digest.count == 64 else { throw SyncFailure.invalidMessage }
            incoming = Incoming(id: id, size: size, digest: digest)
            receivedSnapshot = false
            status = "Syncing nearby…"
            armTimeout()
        case "chunk":
            guard var value = incoming, message.transfer == value.id, message.index == value.nextIndex,
                  let bytes = message.bytes, !bytes.isEmpty, bytes.count <= chunkSize,
                  value.data.count + bytes.count <= value.size else { throw SyncFailure.invalidMessage }
            value.data.append(bytes); value.nextIndex += 1; incoming = value
        case "end":
            guard let value = incoming, message.transfer == value.id,
                  value.data.count == value.size, Self.hash(value.data) == value.digest,
                  let receiver = snapshotReceiver else { throw SyncFailure.invalidMessage }
            try receiver(value.data) // Must commit durably before ACK.
            incoming = nil
            receivedSnapshot = true
            send(Message(kind: "ack", transfer: value.id))
            markCompletedIfReady()
        case "ack":
            guard let id = outgoing, message.transfer == id else { throw SyncFailure.invalidMessage }
            outgoing = nil
            sentSnapshot = true
            markCompletedIfReady()
            if queuedSync { requestSync() }
        default: throw SyncFailure.invalidMessage
        }
    }

    private func markCompletedIfReady() {
        guard sentSnapshot, receivedSnapshot, incoming == nil, outgoing == nil else { return }
        transferTimeout?.cancel(); transferTimeout = nil
        lastSync = Date()
        errorMessage = nil
        status = "Synced with your paired phone"
    }

    private func send(_ message: Message) {
        guard let current = connection else { return }
        do {
            let body = try JSONEncoder().encode(message)
            guard body.count <= maxFrame else { throw SyncFailure.tooLarge }
            var size = UInt32(body.count).bigEndian
            var frame = withUnsafeBytes(of: &size) { Data($0) }
            frame.append(body)
            sendQueue.append(frame)
            drainSendQueue(on: current)
        } catch { fail(error) }
    }

    private func drainSendQueue(on current: NWConnection) {
        guard connection === current, !sending, !sendQueue.isEmpty else { return }
        sending = true
        let frame = sendQueue.removeFirst()
        current.send(content: frame, completion: .contentProcessed { [weak self, weak current] error in
            Task { @MainActor in
                guard let self, let current, self.connection === current else { return }
                self.sending = false
                if let error { self.fail(error) }
                else { self.drainSendQueue(on: current) }
            }
        })
    }

    private func armTimeout() {
        transferTimeout?.cancel()
        transferTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            self?.fail(SyncFailure.timeout)
        }
    }

    private func resetSession() {
        remoteID = nil; remoteApproved = false; localApproved = false
        pendingConfirmation = false; incoming = nil; outgoing = nil
        receivedSnapshot = false; sentSnapshot = false
        sendQueue.removeAll(); sending = false
        transferTimeout?.cancel(); transferTimeout = nil
        pairingTimeout?.cancel(); pairingTimeout = nil
    }
    private func fail(_ error: Error) {
        errorMessage = "Nearby sync stopped: \(error.localizedDescription) Your saved entries remain on this phone."
        disconnectAndRetry()
    }
    private func discoveryFailed(_ error: Error) {
        errorMessage = "Nearby discovery is unavailable. Check Local Network permission and Wi-Fi. \(error.localizedDescription)"
        disconnectAndRetry()
    }
    private func disconnectAndRetry() {
        if let connection { failedEndpoints[String(describing: connection.endpoint)] = Date().addingTimeInterval(20) }
        let old = connection; connection = nil; old?.cancel()
        resetSession()
        browser?.cancel(); browser = nil
        listener?.cancel(); listener = nil
        status = "Waiting for nearby sync"
        scheduleDiscoveryRetry()
    }
    private func scheduleDiscoveryRetry() {
        guard active else { return }
        reconnect?.cancel()
        reconnect = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self, self.active else { return }
            guard self.connection == nil else { return }
            self.browser?.cancel(); self.browser = nil
            self.listener?.cancel(); self.listener = nil
            self.startDiscovery()
        }
    }
    private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    private func loadCredentials() throws -> Credentials? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService, kSecAttrAccount as String: "pairing",
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: false]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw SyncFailure.keychain(status) }
        return try JSONDecoder().decode(Credentials.self, from: data)
    }
    private func saveCredentials(_ value: Credentials) throws {
        #if TRANSPORT_TESTING
        if ephemeralTestStorage { return }
        #endif
        let data = try JSONEncoder().encode(value)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService, kSecAttrAccount as String: "pairing",
            kSecAttrSynchronizable as String: false]
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly]
        let result = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if result == errSecItemNotFound {
            var add = query
            attributes.forEach { add[$0.key] = $0.value }
            let added = SecItemAdd(add as CFDictionary, nil)
            guard added == errSecSuccess else { throw SyncFailure.keychain(added) }
        } else if result != errSecSuccess { throw SyncFailure.keychain(result) }
    }
}

private enum SyncFailure: LocalizedError {
    case invalidPairing, invalidMessage, incompatible, unknownPeer, tooLarge, unavailable, timeout, keychain(OSStatus)
    var errorDescription: String? {
        switch self {
        case .invalidPairing: return "The pairing code is invalid. Generate a new code on the first phone."
        case .invalidMessage: return "The other phone sent an invalid sync message."
        case .incompatible: return "Both phones need the same compatible app version."
        case .unknownPeer: return "This is not your confirmed paired phone."
        case .tooLarge: return "The local history exceeds this version’s transfer limit. No entries were removed."
        case .unavailable: return "Local storage is not ready for sync."
        case .timeout: return "The connection timed out. Keep both apps open nearby and try again."
        case .keychain: return "Secure pairing storage is unavailable. Unlock the phone and ensure a passcode is set."
        }
    }
}
