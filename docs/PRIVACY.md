# Privacy and recovery

Baby Tracker keeps its activity database in the app's private Application Support directory. It has no account system, server, CloudKit container, analytics SDK, crash-upload SDK, advertising SDK, or internet API endpoint. The app does not register for background tasks or push notifications.

Nearby sharing uses Bonjour discovery and Apple peer-to-peer Wi-Fi/local Wi-Fi. Cellular transport is excluded. Network framework authenticates and encrypts transfers with TLS 1.2 and a random 256-bit pre-shared secret. The QR code carries that secret: scan it directly with the second phone; do not photograph, paste, or upload it. Both people compare a session code and confirm before any history is exchanged. Bonjour advertisements contain no names or tracker data. Only one partner is accepted per pairing; unpairing leaves local history intact.

The pairing secret is stored in a nonsynchronizing Keychain item with `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly`. Removing the phone passcode may remove that item and require pairing again. Database files use complete iOS file protection. App-switcher content should not be treated as a secure storage mechanism; avoid screenshots of private history.

## Backup is a separate operating-system setting

The app requests exclusion from backups, but Apple explicitly says this flag is guidance, not a guarantee. Before logging or importing real history, verify Baby Tracker is excluded in the phone's iCloud backup settings. If the app-specific control cannot be verified, disable device cloud backup until it can. The in-app acknowledgment records your check; it cannot inspect or change iCloud settings.

Original ZIPs, screenshots, device backups made outside the app, and files you upload elsewhere are outside this app's control. In particular, the history ZIP supplied in the original conversation already existed outside these two phones. This app cannot retract such copies or promise that an operating system never retains data.

Version one deliberately offers no export or cloud restore. Each phone is a recoverable copy only as of its last completed sync. If both copies are lost or erased, the history is lost. Free signing renewal must install over the same app; do not uninstall it. When replacing one phone, use the surviving phone's history and pair the replacement locally.

## Sync integrity

Snapshots have bounded size and bounded chunk frames. Only a compatible, authenticated peer can send them. The receiving application validates and commits the operation union before acknowledging. Retry resends are safe because operation identifiers are deduplicated. An interrupted transfer does not become a partially imported snapshot. A receipt is not a promise that the other phone has no subsequent unsynced edits.

Apple references:
- https://developer.apple.com/documentation/technotes/tn3213-moving-from-multipeer-connectivity-to-network-framework
- https://developer.apple.com/documentation/foundation/optimizing-your-app-s-data-for-icloud-backup
- https://developer.apple.com/documentation/security/restricting-keychain-item-accessibility
