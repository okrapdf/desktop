# okra CLI Design — Local, Ollama-Style, 1:1 with the Desktop App

Status: Draft (design first; no code yet)
Roadmap: D.7.0 (proposed) · Repo: `okra-project/desktop`
Audience: humans in a terminal + coding agents driving okraPDF non-interactively

---

## 1. Principle

> **One engine, two surfaces.** The `okra` CLI and the okraPDF desktop app are two
> front-ends over the same local parsing engine, the same provider installs, and
> the same run artifacts. Anything the app can do, the CLI can do. Nothing more.

Ollama is the reference interaction model: a tiny verb set, noun-first
discoverability, scriptable output, and the confidence that the CLI and the app
are never out of sync because they share code and state.

Non-goals (unchanged from `CLAUDE.md` / `LAUNCH.md` product rules):
- No chat/Q&A, collections, redaction, accounts, cloud upload, MCP server.
- No document library. Source PDFs stay in place; runs reference them by path.
- No background daemon. `okra parse` runs in the foreground (or `--detach` writes
  the same artifacts the app's orphan-recovery already understands).

The existing cloud CLI (`@okrapdf/cli`, ~125 commands) is a separate product and
is out of scope here — see §7 for the coexistence plan.

## 2. Command surface

Ten verbs. No sub-subcommands deeper than one level. Every command accepts
`--json` for machine output and exits non-zero on failure with a stable
error code (`okra help errors`).

### Document → output (the core loop)

| Command | Desktop equivalent | Notes |
|---|---|---|
| `okra parse <pdf> [--model unlimited-ocr\|docling\|apple-vision] [--pages 1-5] [--simulate]` | "Parse with {provider}" button | Foreground, live progress on stderr, writes run artifacts. Prints `runId` last line. `--simulate` is always labeled, same as app. |
| `okra show <runId> [--format md\|json\|blocks]` | Preview/Markdown/JSON picker + Copy | Streams `result.md` / `result.json` to stdout. `blocks` = pretty block view. |
| `okra open <pdf> [runId]` | Open PDF… (⌘O), open recent run | Launches/reuses the GUI at that document or run. The only command that touches the app UI. |

### Runs (what ollama calls `ps` + history)

| Command | Desktop equivalent | Notes |
|---|---|---|
| `okra runs` | Recent runs sidebar | Table: runId, doc, model, status, pages, when. |
| `okra status <runId> [--watch]` | Run progress view + health monitor | Reads `run.json`; `--watch` tails `events.jsonl` (cursor-based, agent-friendly). |
| `okra cancel <runId>` | Cancel Run | Writes the persisted `canceling` intent the app already honors. |
| `okra resume <runId>` | Resume from Page N | Per-page checkpoint resume; no-op for docling (same as app). |
| `okra rm <runId>` | — (app: delete run artifacts) | Removes `Runs/{runId}`. Confirm unless `--force`. |

### Models (the ollama part)

Providers are presented to users as **models**, matching the app's direction in
D.6.9 (`LocalParserDefinition` + `LocalModelPackageManifest`):

| Command | Desktop equivalent | Notes |
|---|---|---|
| `okra list` | Provider picker + setup states | Installed models, sizes, capabilities (ocr/tables/formulas/bboxes), ready or not. `apple-vision` always listed, zero setup. |
| `okra pull <model>` | "Set up {provider}" with phases/byte progress | Resumable download, SHA-256 verify, `.ready` marker. Cancel-safe via resume data. `Ctrl-C` then re-run continues. |

### Meta

| Command | Notes |
|---|---|
| `okra doctor` | Checks: app bundle present, model dirs, checksums, stale `worker.lock`, orphaned runs. Mirrors the app's orphan-recovery + health logic. |
| `okra version` / `okra help` | Prints app bundle version (single source of truth — no separate CLI version). |

Full grammar fits on one screen of `--help`, like `ollama --help`.

## 3. Shared state (why 1:1 stays true)

The CLI never invents its own storage. It reads and writes exactly what the app
reads and writes:

```
~/.okra/providers/{docling,unlimited-ocr}/{venv,model,.ready,worker.lock}
~/Library/Application Support/okraPDF/Runs/{runId}/
  run.json            # atomic pollable snapshot (status/fraction/message)
  events.jsonl        # append-only lifecycle stream
  page-progress.json  # per-page checkpoint manifest
  page-results/page-NNNN.{md,json}
  result.md, result.json
```

Consequences:
- A run started in the terminal appears in the app's sidebar. A run started in
  the app can be `okra status`-watched, `okra cancel`ed, or `okra resume`d from
  the terminal.
- The existing `worker.lock` flock serializes Unlimited-OCR across CLI and app
  instances — no new coordination needed.
- The app's orphan-recovery adopts interrupted CLI runs on next launch.

## 4. Implementation shape

**Language: Swift, in this repo**, as a second SwiftPM executable target
(`okra-cli`) that links the same `LocalProcessing` module the app uses
(`LocalProcessingProvider`, `LocalProcessingCoordinator`, checkpoint store,
model manifests). No TypeScript, no Node — one language, one build, zero drift.

- Refactor: `LocalProcessingCoordinator` is currently app-coupled (717 lines,
  SwiftUI-facing). Extract a headless `OkraEngine` library target; app and CLI
  both depend on it. This is the only significant refactor.
- CLI argument parsing: `swift-argument-parser` (one new dependency).
- Human output: tables + progress bars on stderr; results on stdout (pipe-clean).
  `--json` everywhere for agents.

## 5. Bundling & distribution (ship together, update together)

- The `okra` binary ships **inside the app bundle** at
  `Okra.app/Contents/MacOS/okra`, signed and notarized with the app, versioned
  with the app. One Sparkle appcast updates both — no version skew possible.
- Install-to-PATH: first run of the app (or `okra doctor --install`) offers to
  symlink `/usr/local/bin/okra` → bundle binary. Uninstall removes the symlink.
- The npm `@okrapdf/cli` remains the cloud product (see §7). Local `okra` takes
  precedence by PATH order; `okra doctor` reports which one is first on PATH.

## 6. Agent affordances (why agents can drive it)

- `--json` on every command; `runId` is the universal handle.
- `okra parse ... --json` emits one JSON event per line on stdout (same schema
  as `events.jsonl`) so agents can stream progress without polling files.
- Stable exit codes: `0` ok, `2` user error, `3` model-not-ready (with
  `okra pull` hint on stderr), `4` canceled, `5` engine failure.
- `okra status --watch` is cursor-based and resumable — safe for long agent
  sessions and retries.
- No interactive prompts when stdin is not a TTY: commands fail with a helpful
  error instead of hanging an agent.
- A future `okra select` / `okra ask --selection` bridge (the aspirational
  Codex-native panel workflow in the meta-repo skill) can layer on top later
  via `okra open` + run artifacts — explicitly out of scope for D.7.0.

## 7. Relationship to the cloud CLI

| | local `okra` (this design) | `@okrapdf/cli` (npm) |
|---|---|---|
| Scope | Desktop 1:1, local files only | Cloud API (~125 cmds) |
| Ships with | Desktop app bundle | npm |
| Auth | None | `okra_xxx` API key |
| Future | The default "okra" for local work | Unchanged; may later gain `okra cloud …` alias if the names collide in practice |

The collision is real but acceptable short-term: different install channels.
Decision deferred: whether the npm CLI eventually renames its local-affecting
verbs. Flagged for the v0.6 line, not blocking this design.

## 8. Milestones

- **D.7.0a** — Extract `OkraEngine` library target; app behavior unchanged
  (app tests stay green).
- **D.7.0b** — `okra list / pull / parse / show` against the engine; ship
  unsigned CLI via `swift build` for dogfood.
- **D.7.0c** — `runs / status / cancel / resume / rm`; cross-surface tests
  (CLI start → app resume; app start → CLI cancel).
- **D.7.0d** — Bundle into .app, notarize, PATH symlink, `doctor`; release
  with desktop beta and announce in release notes.
- **D.7.0e** — Agent polish: `--json` audit, exit-code doc, `help errors`,
  non-TTY behavior tests.

## 9. Open questions

1. `okra open` vs the existing npm CLI's `okra open <docId>` (prints a cloud
   URL) — rename ours to `okra view`? (Leaning: keep `open`, cloud CLI is the
   one that should move.)
2. Should `okra parse` default model be `unlimited-ocr` (best quality, 2.4 GB
   pull) or `apple-vision` (zero setup)? Ollama precedent says: error with a
   `okra pull` hint when the model isn't ready; default = `unlimited-ocr`.
3. Keep `--simulate` in the shipped binary, or debug-only builds? (Leaning:
   keep, always labeled — the app already ships it.)
