# Physical-device acceptance — not yet signed off

Automated tests and unsigned compilation do not prove this checklist. Use synthetic entries first. Do not mark any item complete until observed on the actual two phones.

- [ ] Same stable bundle identifier installed with the chosen free Personal Team on both phones.
- [ ] Cloud-backup settings checked on each phone before real entries/import; app privacy acknowledgment set independently.
- [ ] With internet unavailable, QR pairing and two-sided confirmation succeed; no history appears before both approve.
- [ ] Each parent adds a feed and diaper while disconnected. After nearby sync both histories contain every entry exactly once.
- [ ] Stop a nursing or sleep timer from the other phone; both show exactly one completed entry after sync.
- [ ] Two independently started timers are retained and visible, rather than silently overwritten.
- [ ] Edit the same record independently, reconnect, review retained versions, choose one, sync again, and verify convergence.
- [ ] Delete while the other phone edits. Confirm deletion wins until explicitly restored; then confirm a later deletion still works.
- [ ] Background/lock/terminate and reopen both apps. Entries and timers survive; nearby sync reconnects.
- [ ] Denied Local Network/Camera permissions explain how to recover, without data loss.
- [ ] Import the historical file once: verify 39 activities, timestamps, amounts, and types. Repeating the same import creates zero duplicates.
- [ ] Import sync reaches the second phone. No source history is embedded in the app bundle.
- [ ] Renew signing by installing over the existing app: history and pairing remain.
- [ ] Check VoiceOver, largest accessibility text, date editing, and one-handed logging on both phone sizes.
- [ ] Observe local-only network traffic during sync. No unexpected internet destination is contacted by the app.

Recovery limitation: do not erase the last phone containing the history. There is no cloud or export recovery in version one.
