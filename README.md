<p align="center">
  <img src="OkraPDF/AppIcon.png" alt="okraPDF" width="96" height="96">
</p>

<h1 align="center">okraPDF for macOS</h1>

<h3 align="center">Read and parse PDFs privately on your Mac</h3>

<p align="center">
  Open a PDF in place, read the original, and choose exactly when to turn it
  into structured local output. No account, document library, or cloud upload.
</p>

> **Source of truth:** desktop code is maintained at `apps/desktop` in the Okra
> monorepo. [`okra-project/desktop`](https://github.com/okra-project/desktop)
> is the generated public CI, release, signing, and Sparkle-update projection.

RC.5 candidate source adds Dots OCR 1.5 as the managed default on eligible Macs
inside the document-first workspace. The signed RC.4 download remains the
current public artifact until RC.5 completes signing and notarization; RC.4
does not include the Dots default.

<p align="center">
  <a href="https://github.com/okra-project/desktop/releases/tag/desktop-v1.0.0-rc.4">
    <img alt="Download for macOS" src="https://img.shields.io/badge/download-macOS%2013%2B-2f855a">
  </a>
  <a href="https://github.com/okra-project/desktop/releases">
    <img alt="Latest release" src="https://img.shields.io/github/v/release/okra-project/desktop?include_prereleases&label=release">
  </a>
  <a href="LICENSE">
    <img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-blue">
  </a>
</p>

<p align="center">
  <a href="https://github.com/okra-project/desktop/releases/tag/desktop-v1.0.0-rc.4">Download</a> ·
  <a href="docs/releases/README.md">Release notes</a> ·
  <a href="https://github.com/okra-project/desktop/issues/new">Report an issue</a>
</p>

![okraPDF reading a public SEC filing in the RC.4 document-first workspace](.github/assets/okra-reader-overview.png)

## Read first. Parse when you choose.

Opening a document never starts extraction. okraPDF keeps the source PDF where
it is, renders it with native PDFKit, and waits until you choose **Parse**.
The selected local parser then produces reviewable output beside a persistent
per-page run history on this Mac.

- Read text, charts, forms, and scanned pages in a native document-first workspace.
- Parse with the managed Dots OCR 1.5 default, built-in Apple Vision, optional
  Baidu Unlimited-OCR, or an installed Ollama vision model.
- Inspect extracted blocks against their source boxes without modifying the PDF.
- Preview, copy, save, or reveal Markdown and JSON output.
- Cancel and resume long runs without throwing away completed pages.

<table>
  <tr>
    <td width="33%">
      <img src=".github/assets/okra-structured-extraction.png" alt="Apple Vision extraction boxes aligned with the source PDF and structured block preview">
    </td>
    <td width="33%">
      <img src=".github/assets/okra-markdown-export.png" alt="Locally extracted Markdown beside the source PDF">
    </td>
    <td width="33%">
      <img src=".github/assets/okra-json-export.png" alt="Structured JSON output beside the source PDF">
    </td>
  </tr>
  <tr>
    <td align="center">Source-aligned blocks you can inspect</td>
    <td align="center">Readable Markdown, ready to copy or save</td>
    <td align="center">Normalized JSON for downstream workflows</td>
  </tr>
</table>

## Private by design

1. **Your PDF stays put.** okraPDF reads the file you opened instead of copying
   it into an app-owned document library.
2. **Parsing is explicit.** Reading or replacing a document does not create a
   run; extraction starts only when you click **Parse**.
3. **Processing stays local.** Apple Vision, Dots OCR, and Baidu extraction run
   on the Mac. Ollama uses only its loopback service on this Mac.
4. **Artifacts stay inspectable.** Run state, page checkpoints, Markdown, and
   JSON live under `~/Library/Application Support/Okra/Runs/`.

Dots OCR 1.5 is selected by default on an eligible clean install but never
downloads or parses automatically. Hardware eligibility requires Apple silicon,
macOS 14+, at least 16 GB unified memory, and at least 5 GB free disk; an
ineligible Mac falls back to Apple Vision. Completing setup also requires
Python 3.10+. The explicit setup downloads about 3.54 GB, shows the upstream
model terms, and verifies every pinned model artifact with SHA-256. Baidu
Unlimited-OCR remains selectable as an optional legacy parser with its separate
pinned setup. A stored Baidu selection stays on Baidu, and an interrupted Baidu
run resumes only with Baidu. Managed extraction is forced offline after setup.
Apple Vision remains available with no setup, and Ollama remains responsible
for installing and storing Ollama models.

## Local parsers

| Parser | Setup | Best fit |
| --- | --- | --- |
| **Dots OCR 1.5** (dots.mocr) | Eligible-Mac default; explicit pinned 4-bit MLX setup, about 3.54 GB | Structured OCR, reading order, tables, formulas, and source boxes on Apple silicon with macOS 14+, Python 3.10+, and 16 GB+ memory |
| **Apple Vision** | None; built into macOS | Zero-setup text and scanned PDFs |
| **Baidu Unlimited-OCR** | Optional legacy pinned 4-bit MLX setup, about 2.4 GB | Existing Baidu workflows, checkpoints, and layout extraction on Apple silicon |
| **Auto (Hybrid)** | Start Ollama and choose an installed vision model | Mixed PDFs; native text with page-level vision fallback |
| **Ollama** | Start Ollama and choose an installed vision model | Bring your own local vision model |

## Download

`desktop-v1.0.0-rc.4` is the current signed public release candidate for
Apple-silicon Macs running macOS 13 or later. RC.5 is the active source train
and will replace this download only after its release workflow succeeds.

1. Download `Okra-1.0.0-rc.4.dmg` from the
   [v1.0.0-rc.4 release](https://github.com/okra-project/desktop/releases/tag/desktop-v1.0.0-rc.4).
2. Optionally download the adjacent checksum and run
   `shasum -a 256 -c Okra-1.0.0-rc.4.dmg.sha256`.
3. Open the DMG, drag **Okra** to **Applications**, and eject the DMG.
4. Open **Okra** from Applications. The app and DMG are Developer ID signed,
   hardened, notarized by Apple, and stapled for normal Gatekeeper opening.

The app checks its signed update feed daily. Choose **Check for Updates…** in
the app menu at any time, or install a newer DMG from
[GitHub Releases](https://github.com/okra-project/desktop/releases).

## Build from source

You need macOS 13 or later and Swift 5.9 or later.

```bash
git clone https://github.com/okra-project/desktop.git
cd desktop
swift build
```

To create a local `.app` and DMG:

```bash
./scripts/build-dmg.sh 1.0.0-rc.4
```

Local packages are ad-hoc signed. The release workflow supplies the Developer
ID identity, hardened runtime, notarization, and signed Sparkle appcast.

## Test

```bash
bash scripts/verify-brand-surface.sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/tests -p '*_tests.py'
swift test
```

The test suite covers the read-before-parse contract, provider integration,
page checkpoints, cancel/resume recovery, structured output, source-box
geometry, packaging, and signed-update metadata.

## Project map

```text
OkraPDF/       SwiftUI app, PDFKit reader, and local parsing providers
Tests/         Product, provider, persistence, and packaging tests
scripts/       Verification, packaging, and release automation
docs/releases/ Versioned user-facing release notes
```

Maintainers should start with [CLAUDE.md](CLAUDE.md),
[RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md), and
[LAUNCH.md](LAUNCH.md). Historical changes are indexed in
[docs/releases](docs/releases/README.md). Repository projection and source
ownership are documented in the monorepo at
`internal/specs/desktop-repository-canonicalization.md`.

## License

okraPDF Desktop is available under the [MIT License](LICENSE).
