# okraPDF Desktop v1.0.0-rc.5

> Dots OCR 1.5 is now the managed local parser selected by default on eligible
> clean installs. Opening a PDF still never downloads a model or starts extraction:
> setup and **Parse** remain explicit actions.

## What changed

- Added **Dots OCR 1.5**, the current upstream `dots.mocr` model, as a
  dedicated local Apple-silicon provider.
- Pinned the 4-bit MLX package to one immutable revision and pinned all 15
  model artifacts by exact size and SHA-256.
- Added resumable, byte-counted setup for the approximately 3.54 GB model.
- Added Dots layout-JSON parsing for reading order, titles, headings, lists,
  tables, formulas, images, headers, footers, and normalized source-PDF boxes.
- Kept Baidu Unlimited-OCR selectable as an optional legacy managed parser.
- Kept inference offline after setup with Hugging Face, Transformers, and
  datasets offline flags.
- Kept durable per-page checkpoints, cancellation, resume, Markdown, structured
  JSON, box inspection, and local run history.
- Added an install-ready DMG window with a deliberately arranged **Okra** app
  and **Applications** shortcut for the standard drag-to-install flow.

## Defaults and migration

- Eligible fresh installs select Dots OCR 1.5, but the model is not downloaded
  until you choose setup and accept the linked upstream model terms. Macs that
  do not meet its requirements fall back to Apple Vision.
- A stored Baidu Unlimited-OCR picker selection remains on Baidu. Baidu stays
  available in the provider picker for optional and legacy use.
- Interrupted Baidu runs resume only with Baidu; the app never substitutes Dots
  into an existing Baidu run. Existing Baidu model files, checkpoints, and
  historical run artifacts are not deleted or rewritten.
- Apple Vision remains available as the zero-setup option. Auto and Ollama
  remain available for local Ollama users.

## Model terms and requirements

Dots OCR is an upstream model with a supplemental model agreement in addition
to its MIT materials. The app links those terms before setup and stores the
model separately at `~/.okra/providers/dots-ocr`. Hardware eligibility requires
Apple silicon, macOS 14 or later, at least 16 GB unified memory, and at least
5 GB free disk; 24 GB memory is recommended. Completing setup also requires
Python 3.10 or later. The app itself remains usable on macOS 13 through Apple
Vision and other compatible providers. Top-level Python packages are version-pinned and the resolved
environment is recorded after setup; transitive wheels are not yet hash-locked.

## Privacy

Source PDFs remain in place. Reading a PDF creates no extraction run. The only
network activity in the managed path is the explicit one-time runtime and model
setup; processing is forced offline afterward. There is no account, cloud
upload, document library, or remote-control surface.

## Validation and known limit

Hermetic checks cover clean-install and legacy-provider selection, package
lineage, checksums, setup-state behavior, PDF rendering, the bundled worker,
official Dots JSON shape, malformed-output recovery, smart-resize box geometry,
tables/formulas, page checkpoints, aggregate Markdown/JSON, and provider-neutral
PDF overlays.
The candidate passes the brand gate, 26 Python tests, 111 Swift tests across
21 suites, six projection safety tests, and a production Swift build. The two
packaged-artifact launch checks remain reserved for the signed DMG workflow.
The drag-to-install layout is embedded deterministically, so headless CI and
release services do not need permission to automate Finder.

The exact pinned Dots weights have not yet completed a clean current-app,
multi-page memory/quality run. That remains an explicit release gate, so RC.5
is a prerelease candidate, not a stable-quality promise. Apple Vision is the
immediate zero-setup fallback, and Baidu remains available for established
local workflows.

## Install

Once the release workflow completes, download `Okra-1.0.0-rc.5.dmg` and its
adjacent `.sha256` file from the
[`desktop-v1.0.0-rc.5` GitHub prerelease](https://github.com/okra-project/desktop/releases/tag/desktop-v1.0.0-rc.5).
Verify the checksum, open the DMG, and drag **Okra** onto the adjacent
**Applications** shortcut. At
publication, the app and DMG will be Developer ID signed, hardened, notarized,
and stapled by the release workflow.

## Rollback

RC.4 remains available as the previous signed candidate. If RC.5 does not work
well on a particular Mac, choose Apple Vision or Baidu in the parser menu, or
reinstall RC.4. Existing PDFs and local run data remain on disk.

## Owner

okraPDF desktop maintainers (`D.6.15`, `okra-project/desktop`).
