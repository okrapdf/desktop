# okraPDF Desktop Agent Map

## Source boundary

The canonical source is the monorepo subtree `apps/desktop`. The public
`okra-project/desktop` repository is generated from committed files in this
directory and owns public CI, signing, Releases, and the Sparkle appcast. Do not
reverse-sync public changes or place public-only release credentials here.

## Product boundary

This app is currently a minimal macOS 13+ windowed PDF reader and local parser. Under
`D.6.3`, keep one permanent center reader with compact edge rails and
independently collapsible local Workspace and Extract panels. Do not add tabs,
remote control, chat, cloud upload, registries, promotions, account gates, or
backoffice UI.

The supported flow is:

```text
open/drop PDF → read → choose local provider → explicit Parse → readable output
```

## Architecture

- `OkraPDF/App.swift` — normal windowed app lifecycle and File menu command
- `OkraPDF/Support/SparkleUpdaterController.swift` — Sparkle in-app updates (signed appcast, Install and Relaunch)
- `OkraPDF/AppState.swift` — open/drop state separated from explicit parsing
- `OkraPDF/ContentView.swift` — document-first PDF reader shell, drop target, rails, and collapsible panels
- `OkraPDF/Workspace/` — native toolbar, local Workspace/Extract panels, reader surface, and layout state
- `OkraPDF/PDFReaderView.swift` — native PDFKit reader bridge
- `OkraPDF/LocalProcessing/` — provider contracts, setup, coordinator, and output UI
- `OkraPDF/ProviderScripts/` — bundled managed-parser setup and worker scripts

## Build and test

```bash
swift build
swift test
```

Do not start a dev server or watch process.

## Product rules

- User-facing brand copy is always `okraPDF`.
- Extraction is local. Only explicit provider setup may download dependencies.
- Opening or replacing a PDF must never start parsing; only the Parse action may run a provider.
- Dots OCR 1.5 is the selected managed default on eligible clean installs, but
  setup and parsing remain explicit. Hardware eligibility requires Apple
  silicon, macOS 14+, and 16 GB+ memory; Apple Vision is the incompatible-host
  and zero-setup fallback. Completing Dots setup requires Python 3.10+.
  Baidu Unlimited-OCR remains an optional selectable legacy provider; preserve
  a stored Baidu selection and resume an interrupted Baidu run only with Baidu.
- The source PDF remains in place; do not reintroduce a copied-file library.
- Successful output is normalized to `result.md` beside a small `run.json` manifest.
  Providers with structured output also write `result.json` with typed blocks and normalized
  top-left layout boxes. Valid boxes render as removable, screen-only PDFKit
  annotations over the source PDF and support two-way selection and hover with
  the block preview; do not expose raw tokenizer artifacts or mutate the source PDF.
- Do not add SQLite, cloud fields, policy/spend models, chat, or document agents
  without a new roadmap item and architecture decision.
- Use system controls and accessible SF Symbols only for functional affordances.
