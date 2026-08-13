# okraPDF Desktop — Launch Checklist

The supported desktop product combines the `D.6.3` document-first workspace
with the `D.6.14` windowed macOS PDF reader and local parser. It opens a PDF in
place, waits for an explicit Parse action, and returns reviewable
source-aligned output.

## Versioning

- Tag format: `desktop-v{SEMVER}`, including prerelease suffixes such as
  `desktop-v1.0.0-rc.5`.
- Current train: `desktop-v1.0.0-rc.5`.
- `1.0.0` means the parser flow and direct-download distribution are stable.
- Chat, agents, cloud upload, document libraries, channels, and remote control
  are separate products and do not belong in this release train.

## Product gate

- [x] Lightweight windowed SwiftUI PDF reader
- [x] Permanent center PDF reader with compact edge rails
- [x] Independently collapsible local Workspace and Extract panels
- [x] Native document toolbar with clean, functional controls and no promotional surfaces
- [x] Open and Finder drag-and-drop
- [x] PDF selection and parsing are separate actions
- [x] Original PDF remains in place
- [x] Apple Vision zero-setup parser
- [x] Dots OCR 1.5 selected by default on eligible clean installs without automatic setup or parsing
- [x] Hardware-incompatible hosts fall back to Apple Vision; Dots requires Apple silicon, macOS 14+, and 16 GB+ memory, while setup also requires Python 3.10+
- [x] Resumable, byte-counted, SHA-256-verified Dots model setup
- [x] Dots layout JSON adapter with normalized source boxes and offline inference
- [x] Optional Baidu Unlimited-OCR remains selectable with its pinned setup
- [x] Stored Baidu selection remains selected, and interrupted Baidu runs resume only with Baidu
- [x] Docling provider removed for beta.20
- [x] Historical Baidu run provenance and checkpoints remain readable
- [x] Accessible Show boxes toolbar toggle with Reduce Motion support
- [x] Markdown copy, save, and reveal
- [x] File-backed `run.json` and `result.md` artifacts
- [x] Durable per-parser, per-page `idle` / `inProgress` / `done` / `attention` / `error` lifecycle
- [x] Accessible lazy page-state UI with visible text and symbols in addition to color
- [x] No account, network workflow, SQLite, policy, agents, or sidecars
- [ ] Clean-profile Dots OCR 1.5 dogfood on a 16 GB Apple-silicon Mac
- [ ] Clean-profile Baidu Unlimited-OCR regression on Apple silicon
- [ ] Manual large/scanned/malformed PDF regression pass

## Distribution gate

- [x] App icon and `com.okrapdf.desktop` bundle identifier
- [x] macOS 13 minimum and regular Dock/window lifecycle
- [x] Packaged PDF viewer document type
- [x] Repeatable `./scripts/build-dmg.sh <version>` build
- [x] Developer ID Application certificate available locally
- [x] Hardened-runtime signing
- [x] App and DMG notarization and stapling
- [x] Re-downloaded app and DMG accepted by `spctl` as `Notarized Developer ID`
- [x] Packaged app launch smoke test with builder-only resources hidden
- [x] Sparkle 2 in-app updates: signed `appcast.xml` feed, EdDSA keypair (secret-only private key), Install and Relaunch flow
- [x] Quarantined DMG launch smoke gate through LaunchServices in release automation
- [ ] Second-Mac clean-install verification
- [x] DMG Applications shortcut and intentional Finder window layout

The app currently has an empty entitlement set. Do not add network, JIT,
unsigned-executable-memory, or library-validation exceptions speculatively.
Add the narrowest entitlement only when a signed distribution build proves it
is required by one of the supported local parsers.

## Release command

```bash
swift test
./scripts/build-dmg.sh 1.0.0-rc.5
```

RC.5 is the current release-candidate train, not the stable release. It is
appropriate for direct-download and in-app-update testing after passing the
document-first layout and signed-artifact gates. Do not call it stable until the
remaining friend-core, second-Mac install, and signed in-place update gates in
`RELEASE_CHECKLIST.md` are recorded.
