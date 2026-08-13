# okraPDF Desktop — Release Checklist

Current train: `desktop-v1.0.0-rc.5`

Roadmap items: `D.6.3`, `Stable #15`, `D.6.9`, `D.6.13`, `D.6.14`, `D.6.15`

## Product contract

- [x] Windowed app with native PDFKit preview
- [x] Regular activation policy and Dock lifecycle
- [x] Document-first workspace with a permanent center reader, compact edge rails, and independently collapsible Workspace and Extract panels
- [x] Native toolbar with the canonical mark, document title, panel toggles, Open, source reveal, and extraction-box controls
- [x] Workspace visible and Extract tucked away by default; hiding either panel preserves its local state
- [x] Panel transitions honor Reduce Motion and expose accessible labels, help, and selected state
- [x] Hidden drawer controls are disabled and removed from accessibility; closing a drawer returns keyboard focus to its persistent rail
- [x] Open and document replacement are disabled and centrally guarded during setup or parsing
- [x] PDF drag-and-drop
- [x] **Open PDF…** picker
- [x] Explicit Parse action; opening/replacing a PDF creates no run
- [x] Dots OCR 1.5 selected by default on eligible clean installs; setup and Parse remain explicit
- [x] Dots host gate requires Apple silicon, macOS 14+, 16 GB+ memory, and setup space; incompatible hosts fall back to Apple Vision, and setup separately requires Python 3.10+
- [x] Apple Vision remains available without setup
- [x] Auto (Hybrid) native-text reuse with page-local Ollama vision fallback
- [x] Generic Ollama provider with HTTP model discovery and vision-capability filtering
- [x] Ollama model selection persists without inspecting its model directory or invoking its CLI
- [x] Docling provider removed for beta.20
- [x] Optional Baidu Unlimited-OCR remains selectable with its pinned setup/readiness state and lineage copy
- [x] Stored Baidu selection remains selected; interrupted Baidu runs resume only through the Baidu provider
- [x] Native byte-counted Baidu model download with cancel/resume state
- [x] Pinned Baidu model revision and SHA-256 verification before readiness
- [x] Truthfully labeled Baidu Unlimited-OCR simulation mode
- [x] Pinned Dots OCR 1.5 model revision and SHA-256 verification before readiness
- [x] Dots model terms disclosed before setup
- [x] Truthfully labeled Dots OCR 1.5 simulation mode
- [x] Streaming progress and local errors
- [x] Canonical per-parser page lifecycle (`idle`, `inProgress`, `done`, `attention`, `error`)
- [x] Lazy page-state strip with parser name, visible text/symbol states, and complete VoiceOver labels
- [x] Passive stall warning after 90 seconds without progress updates
- [x] Low-memory warning while a local run is active
- [x] Cross-instance managed-MLX run queue with a visible waiting state for Dots and Baidu
- [x] In-app Sparkle auto-update: Check for Updates… downloads, verifies, and relaunches into the newest signed beta
- [x] Cancel Run action with persisted cancel intent and terminal canceled state
- [x] Interrupted-run recovery and same-run Resume action
- [x] Atomic page-level Markdown checkpoints for Apple Vision, Dots OCR 1.5, and Baidu Unlimited-OCR
- [x] Dots layout-array decoding and official Qwen smart-resize box normalization
- [x] Typed normalized blocks in per-page and aggregate `result.json`
- [x] Deterministic repeated-tail suppression with diagnostics
- [x] Preview, Markdown, and JSON output modes for Apple Vision, Dots, and Baidu runs
- [x] Source-PDF bounding boxes for valid Dots and Baidu normalized layout blocks
- [x] Apple Vision structured output and source-PDF boxes for native text and scanned OCR observations
- [x] Provider-neutral source-PDF overlays for Apple Vision, Dots OCR 1.5, and Baidu Unlimited-OCR
- [x] Two-way source-box and preview-card selection across zoom, scroll, crop, and rotation
- [x] Two-way source-box and preview-card hover highlighting, including card scroll-into-view
- [x] Accessible Show boxes toolbar toggle; overlays remain screen-only and never mutate the source PDF
- [x] Copy, Save As, and Reveal actions for Markdown and JSON
- [x] No cloud upload or remote-control surface

## Persistence and privacy

- [x] Source PDFs remain in place
- [x] No account, library database, cloud metadata, policy, spend, or audit records
- [x] Run lifecycle persisted as `run.json` under Application Support
- [x] Pollable progress snapshots and sequenced lifecycle stream persisted as `run.json` and `events.jsonl`
- [x] Parser/page lifecycle matrix persisted in `run.json` with legacy-manifest decoding
- [x] Results stored beside each run manifest as `result.md`
- [x] Apple Vision, Dots, and Baidu structured results stored beside each run manifest as `result.json`
- [x] Recent local runs re-open from the workspace sidebar
- [x] Dots OCR 1.5 and Baidu Unlimited-OCR inference force Hugging Face/Transformers offline mode
- [x] Provider setup is visibly distinct from offline extraction
- [x] Ollama is represented as a loopback HTTP integration, separate from Okra-managed Dots and Baidu setup

## Automated verification

- [x] Local-processing tests retained
- [x] Simulated Baidu Unlimited-OCR PDF → pages → worker → Markdown + JSON → manifest E2E
- [x] Simulated Dots OCR 1.5 PDF → pages → worker → Markdown + JSON → manifest E2E
- [x] Dots layout-array parsing, category mapping, malformed-output recovery, table HTML, and pixel-box normalization coverage
- [x] Mid-run `run.json` progress and 120-page checkpoint persistence coverage
- [x] Cancel ordering, orphan recovery, checkpoint resume, and child-process termination coverage
- [x] Lifecycle TDD for transitions, parser isolation, Codable round trips, health attention, cancellation, errors, and completion
- [x] Run-health stall/memory decision logic and cross-process lock queue coverage
- [x] Appcast item insertion, newest-first ordering, and re-run replacement coverage
- [x] Synthetic aToken fixture covers whitespace decoding, malformed markers, normalized boxes, HTML preservation, and repeated-tail suppression
- [x] Provider-neutral PDF overlay adapter, clipping, fixed crop/rotation geometry, annotation ownership, click-selection, and hover-state coverage
- [x] Apple Vision native-text and scanned-observation structured-output coverage
- [x] Default app state constructs every bundled provider without terminating
- [x] Ollama `/api/tags`, `/api/show`, and `/api/chat` request contracts have hermetic unit coverage
- [x] Document-first default and independent Workspace/Extract toggles have unit coverage
- [x] Packaged app starts with builder-only SwiftPM resources hidden
- [x] Quarantined notarized beta.8 through beta.15 DMGs start through LaunchServices before publishing (2026-07-28)
- [x] DMG packaging stages an Applications shortcut, embeds a checksummed Finder icon layout without GUI automation, and verifies both from the mounted release image
- [x] Remote-control, dispatch, registry, and model-catalog tests removed
- [x] Docling provider, tests, and Docling-only bundled resources removed for beta.20
- [x] `swift build` on an unrestricted macOS shell (2026-07-28)
- [x] Canonical website mark checksum and packaged-resource coverage
- [x] `swift test` on an unrestricted macOS shell (93 tests passed, 2026-07-29)
- [x] Python output-parser, resume, appcast, and protected-release tests (12/12 passed, 2026-07-29)
- [x] RC.4 brand gate, 12 Python tests, 101 Swift tests across 20 suites, and release build pass on the candidate tree (2026-08-05)
- [x] RC.5 brand gate, 26 Python tests, 111 Swift tests across 21 suites, six projection safety tests, and release build pass on the candidate tree (updated 2026-08-12)
- [x] Local ad-hoc RC.4 package launches and passes empty, loaded-document, light, dark, and 960-point drawer interaction checks (2026-08-05)
- [x] Packaged-app resource-isolation launch and quarantined local-DMG LaunchServices tests pass against the rebuilt RC.4 package (2/2, 2026-08-05)

### Pre-merge CI gate (stable #15)

`.github/workflows/pr-checks.yml` runs on every pull request and push to
`main` so code checks no longer happen only inside the credentialed release
job.

- Secretless: `permissions: contents: read`; no Developer ID, notarization,
  or Sparkle keys are imported. Signing, notarization, stapling, quarantine,
  packaged-launch, appcast signing, and publishing stay exclusive to
  `notarized-release.yml` on `desktop-v*` tags, and a green PR check never
  publishes or mutates `main`.
- Concurrency cancels superseded runs for the same PR/branch ref so the
  constrained self-hosted macOS lane is not wasted on stale commits.
- Each run executes `scripts/verify-brand-surface.sh`, the Python unit suite
  (`scripts/tests`), `swift test`, and `swift build -c release`.
- Tests stay hermetic: `OKRA_DESKTOP_TEST_TMPDIR` routes test workspaces to
  the runner-temporary root, `TestWorkspace` already isolates `UserDefaults`
  suites per test, and no live provider credentials or network inference are
  required.

#### macOS lane maintenance and recovery

- Lane: self-hosted runner `stevens-mac-mini-okrapdf-desktop` on the Mac
  mini, labels `self-hosted, macOS, ARM64, okrapdf-desktop-release`. PR
  checks match on the base labels only; the release job alone claims the
  `okrapdf-desktop-release` label.
- Required toolchains on the lane: Xcode/Swift 5.9+, `rg`, `python3`.
- Inspect runner health: `gh api repos/okra-project/desktop/actions/runners`
  (status should be `online`), or the repo's Settings → Actions → Runners
  page. Failed runs list their logs under the PR Checks workflow.
- Recover an offline runner: on the Mac mini, restart the runner service from
  its install directory (`./svc.sh stop && ./svc.sh start`, or the LaunchDaemon
  equivalent used at install time), then re-check the runners API. If the
  runner needs re-registration, replace it under Settings → Actions → Runners
  with a fresh registration token and the same labels.
- Branch protection: the `macos-checks` job is the required pre-merge check
  for `main`.
- Release appcasts are pushed to a dedicated `automation/appcast-*` branch.
  A maintainer opens that branch as a normal pull request so `macos-checks`
  runs before the signed feed update reaches protected `main`.

## Friend-core manual regression

Run every line below against the exact downloadable RC.4 prerelease candidate.
Record evidence on the RC.4 release tracking issue or pull request; do not use
a local build.

- [ ] Launch with Workspace visible and Extract hidden; confirm the center reader remains the largest surface
- [ ] Toggle Workspace and Extract independently from both the toolbar and edge rails
- [ ] Hide and reopen Extract during a completed run; confirm the selected provider and output remain intact
- [ ] Open a one-page text PDF and confirm no extraction starts until **Parse** is clicked
- [ ] Replace it with a multi-page scanned PDF and again confirm no automatic extraction
- [ ] Parse both documents with Apple Vision
- [ ] Confirm multi-page progress remains visible and the app stays responsive
- [ ] Copy output and paste it into a plain-text editor
- [ ] Use **Save As** and verify the resulting `.md` file
- [ ] Use **Reveal** and verify both the stored output and source PDF locations
- [ ] Repeat the Apple Vision flow with the network disconnected
- [ ] Try one invalid or corrupt input and confirm the app rejects or reports it without crashing

## Broader product regression

These retained checks do not replace the friend-core lines above. Do not mark
the real-provider checks complete from Dots or Baidu simulation.

- [x] Launch and confirm the reader window and canonical green Dock icon appear (2026-07-27)
- [ ] Drop a one-page text PDF and confirm no extraction starts
- [ ] Click Parse and confirm Apple Vision starts
- [ ] Drop a multi-page scanned PDF and confirm progress updates by page
- [ ] Copy the output and paste it into a plain-text editor
- [ ] Save the output to a chosen `.md` path
- [ ] Reveal the stored output and source PDF in Finder
- [ ] Switch provider, rerun, and confirm a new run folder and manifest are created
- [x] Run the labeled Baidu Unlimited-OCR simulation on a multi-page PDF (3 pages, 2026-07-27)
- [ ] Select Baidu boxes from both the PDF and preview on a rotated/cropped dogfood PDF
- [ ] Set up Baidu Unlimited-OCR on a 16 GB Apple-silicon Mac and extract offline
- [ ] Set up the pinned Dots OCR 1.5 model on a clean 16 GB Apple-silicon Mac and record peak memory plus multi-page stability

## Distribution

- [x] GitHub prerelease `desktop-v0.5.0-beta.5` with DMG and SHA-256 asset (2026-07-24)
- [x] GitHub prerelease `desktop-v0.5.0-beta.6` with DMG and SHA-256 asset (2026-07-27)
- [x] GitHub prerelease `desktop-v0.5.0-beta.7` with DMG and SHA-256 asset (2026-07-27)
- [x] GitHub prerelease `desktop-v0.5.0-beta.8` with startup fix, DMG, and SHA-256 asset (2026-07-27)
- [x] GitHub prerelease `desktop-v0.5.0-beta.9` with canonical mark, page checkpoints, DMG, and SHA-256 asset (2026-07-27)
- [x] GitHub prerelease `desktop-v0.5.0-beta.10` with structured Baidu output, DMG, and SHA-256 asset (2026-07-27)
- [x] GitHub prerelease `desktop-v0.5.0-beta.11` with durable cancel/resume, DMG, and SHA-256 asset (2026-07-27)
- [x] GitHub prerelease `desktop-v0.5.0-beta.12` with truthful run health, DMG, and SHA-256 asset (2026-07-28)
- [x] GitHub prerelease `desktop-v0.5.0-beta.13` with beta update awareness, DMG, and SHA-256 asset (2026-07-28)
- [x] GitHub prerelease `desktop-v0.5.0-beta.14` on the public okra-project org with DMG and SHA-256 asset (2026-07-28)
- [x] GitHub prerelease `desktop-v0.5.0-beta.15` under the permanent `okra-project/desktop` name with DMG and SHA-256 asset (2026-07-28)
- [x] GitHub prerelease `desktop-v0.5.0-beta.16` with Sparkle in-app updates, signed appcast feed, DMG, and SHA-256 asset (2026-07-28)
- [x] GitHub prerelease `desktop-v0.5.0-beta.17` with Sparkle click-to-restart E2E proof, DMG, SHA-256 asset, and appcast update (2026-07-28)
- [x] GitHub prerelease `desktop-v0.5.0-beta.18` with Baidu source-PDF bounding boxes, DMG, SHA-256 asset, and appcast update (2026-07-28)
- [x] Sparkle.framework embedded, Developer ID signed, notarized, and stapled with the app
- [x] EdDSA update signing: private key in repo secrets only, public key in the bundle
- [x] Developer ID Application signature for team `449BD89VDV`
- [x] Hardened runtime
- [x] App and DMG accepted by Apple notarization and stapled
- [x] Re-downloaded app and DMG accepted by `spctl` as `Notarized Developer ID`
- [x] Public `desktop-v1.0.0-rc.1` prerelease with DMG and SHA-256 assets (2026-07-29)
- [x] Exact RC.1 passes automated signing, notarization, Gatekeeper, DMG, and quarantine-launch gates (2026-07-29)
- [x] Exact RC.1 is re-downloaded, verified, and installed on this MacBook (2026-07-29)
- [x] Public `desktop-v1.0.0-rc.2` prerelease with generic Ollama HTTP integration (2026-07-29)
- [x] RC.2 appcast branch passes `macos-checks` and merges to protected `main` (2026-07-29)
- [ ] Exact RC.2 is re-downloaded, verified, installed, and dogfooded against local Ollama
- [x] Public `desktop-v1.0.0-rc.3` prerelease with dark-mode source-box visibility fix (2026-08-03)
- [x] RC.3 appcast branch passes `macos-checks` and merges to protected `main` (2026-08-03)
- [ ] Exact RC.3 is re-downloaded, verified, installed, and dark-mode box visibility confirmed
- [x] Public `desktop-v1.0.0-rc.4` prerelease with the D.6.3 document-first workspace (2026-08-05)
- [x] RC.4 appcast branch passes `macos-checks` and merges to protected `main` (PR #69, 2026-08-05)
- [x] Exact RC.4 is re-downloaded and passes checksum, disk-image integrity, Developer ID, hardened-runtime, notarization/stapling, Gatekeeper, embedded version/build, and quarantined LaunchServices checks (2026-08-05)
- [x] Exact signed RC.4 empty, loaded-document, Workspace, and Extract layouts are inspected in light appearance; the identical candidate code passes light, dark, wide, and compact inspection before tag (2026-08-05)
- [ ] Exact RC.4 is installed into Applications and dogfooded in dark appearance
- [ ] Public `desktop-v1.0.0-rc.5` prerelease publishes a signed/notarized DMG and SHA-256 asset
- [ ] RC.5 appcast branch passes `macos-checks` and merges to protected `main`
- [ ] Exact RC.5 is re-downloaded and passes checksum, disk-image, signature, notarization/stapling, Gatekeeper, embedded-version, and quarantined-launch checks
- [ ] Friend-equivalent clean-Mac install and Apple Vision extraction recorded on issue #47
- [ ] Signed in-place **Install and Relaunch** update evidence recorded on issue #39
