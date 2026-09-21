import SwiftUI
import AVFoundation
import CoreImage.CIFilterBuiltins

struct PairingView: View {
    @ObservedObject var sync: NearbySync
    @State private var scanning = false
    @State private var confirmForget = false
    @State private var cameraError: String?

    var body: some View {
        Form {
            Section {
                BabySectionHeader(
                    title: "Share with one trusted phone",
                    subtitle: "Both phones must be nearby, unlocked, and running Baby Tracker."
                )
            }
            Section("Nearby sharing") {
                HStack {
                    Label("Status", systemImage: sync.isPaired ? "iphone.radiowaves.left.and.right" : "iphone")
                    Spacer()
                    Text(sync.status)
                        .foregroundStyle(sync.isPaired ? BabyTheme.sleep : BabyTheme.quietText)
                }
                if let date = sync.lastSync {
                    LabeledContent("Last confirmed sync", value: date.formatted(date: .abbreviated, time: .shortened))
                }
                Text("Entries stay on each phone. Open both apps nearby with Wi-Fi enabled to exchange updates. There is no internet sync.")
                    .font(.footnote).foregroundStyle(BabyTheme.quietText)
            }
            if sync.pendingConfirmation {
                Section("Confirm on both phones") {
                    Text(sync.confirmationCode)
                        .font(.system(.largeTitle, design: .monospaced, weight: .bold))
                        .tracking(4)
                        .foregroundStyle(BabyTheme.diaper)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .textSelection(.disabled)
                        .accessibilityLabel("Pairing code " + sync.confirmationCode.map(String.init).joined(separator: " "))
                    Text("Compare this code on both screens. Confirm only when they match and you are holding your partner’s phone.")
                        .foregroundStyle(BabyTheme.quietText)
                    Button("Codes match, pair these phones") { sync.confirmPairing() }
                        .buttonStyle(BabyPrimaryButtonStyle(color: BabyTheme.sleep))
                    Button("Cancel pairing", role: .destructive) { sync.forgetPairing() }
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            } else if !sync.isPaired {
                Section("First phone") {
                    Button("Show pairing QR code", systemImage: "qrcode") { sync.createInvitation() }
                        .frame(minHeight: 44)
                    if let code = sync.invitationCode, let image = qrImage(code) {
                        Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                            .padding(16).background(.white).clipShape(RoundedRectangle(cornerRadius: 16))
                            .accessibilityLabel("Private pairing QR code. Scan with the other phone’s Baby Tracker app.")
                        Text("This code is a secret. Scan it directly in the app. Do not photograph or share it.")
                            .font(.footnote)
                    }
                }
                Section("Second phone") {
                    Button("Scan partner’s code", systemImage: "qrcode.viewfinder") { scanning = true }
                        .frame(minHeight: 44)
                    Text("Pairing combines the two phones’ tracker histories after you both confirm.").font(.footnote)
                }
            } else {
                Section {
                    Button("Sync now", systemImage: "arrow.triangle.2.circlepath") { sync.start(); sync.requestSync() }
                        .frame(minHeight: 44)
                    Button("Unpair this phone", role: .destructive) { confirmForget = true }
                        .frame(minHeight: 44)
                    Text("Unpairing keeps this phone’s entries. Pair again only with your family’s phone.").font(.footnote)
                }
            }
            if let error = sync.errorMessage {
                Section("Connection needs attention") {
                    Text(error).foregroundStyle(.orange)
                    Button("Try again") { sync.errorMessage = nil; sync.stop(); sync.start() }
                }
            }
        }
        .babyFormStyle()
        .navigationTitle("Private sharing")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $scanning) {
            NavigationStack {
                QRScanner { result in
                    scanning = false
                    switch result {
                    case .success(let value): sync.acceptInvitation(value)
                    case .failure(let error): cameraError = error.localizedDescription
                    }
                }
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Scan pairing code")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { scanning = false } } }
            }
        }
        .alert("Camera unavailable", isPresented: Binding(get: { cameraError != nil }, set: { if !$0 { cameraError = nil } })) {
            Button("OK") { cameraError = nil }
        } message: { Text(cameraError ?? "") }
        .confirmationDialog("Unpair this phone?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Unpair", role: .destructive) { sync.forgetPairing() }
        } message: { Text("History stays here. The other phone will no longer be able to sync with this phone until you pair again.") }
        .onAppear { sync.start() }
    }

    private func qrImage(_ value: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let image = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cgImage = CIContext().createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

private struct QRScanner: UIViewControllerRepresentable {
    var onResult: (Result<String, Error>) -> Void
    func makeUIViewController(context: Context) -> ScannerController { ScannerController(onResult: onResult) }
    func updateUIViewController(_ uiViewController: ScannerController, context: Context) {}
    static func dismantleUIViewController(_ uiViewController: ScannerController, coordinator: ()) { uiViewController.stop() }
}

private final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "babytracker.camera")
    private var preview: AVCaptureVideoPreviewLayer?
    private var finished = false
    private var cancelled = false
    private let onResult: (Result<String, Error>) -> Void

    init(onResult: @escaping (Result<String, Error>) -> Void) {
        self.onResult = onResult
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
            DispatchQueue.main.async {
                guard let self, !self.cancelled else { return }
                if allowed { self.configure() }
                else { self.finish(.failure(CameraFailure.permission)) }
            }
        }
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); preview?.frame = view.bounds }
    private func configure() {
        guard let camera = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input) else {
            finish(.failure(CameraFailure.unavailable)); return
        }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { finish(.failure(CameraFailure.unavailable)); return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        preview = layer
        let session = session
        queue.async { session.startRunning() }
    }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let object = metadataObjects.compactMap({ $0 as? AVMetadataMachineReadableCodeObject }).first,
              let text = object.stringValue, text.hasPrefix("baby-local-v1:") else { return }
        finish(.success(text))
    }
    func stop() {
        cancelled = true
        let session = session
        queue.async { if session.isRunning { session.stopRunning() } }
    }
    private func finish(_ result: Result<String, Error>) {
        guard !finished, !cancelled else { return }
        finished = true
        stop()
        onResult(result)
    }
}
private enum CameraFailure: LocalizedError {
    case permission, unavailable
    var errorDescription: String? {
        switch self {
        case .permission: return "Allow Camera access for Baby Tracker in Settings to scan the pairing code. No photos are saved."
        case .unavailable: return "A camera is required to scan the pairing code. Try again on your iPhone."
        }
    }
}
