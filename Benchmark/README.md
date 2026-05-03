# Benchmark

This executable profiles the Markdown editor's core data and presentation paths.
It is intended to catch performance regressions before recording a full
Instruments trace.

## Run

From the repository root:

```sh
swift run -c release Benchmark
```

Use `-c release`. Debug builds include optimizer noise and are not useful for
comparing timings.

## Covered Paths

`parse.large-document`

Parses a large mixed Markdown document. This tracks parser cost after changes to
block identity or line scanning.

`render.preview` and `render.active-list-group`

Render the full document in preview mode and with one list group active. These
measure the attributed-string and source/visible mapping generation paths.

`rewrite.paragraph-insert` and `parse.prefix-edited-large-document`

Apply an inline edit near the top of the document and parse the edited source.
This covers the optimization that keeps code block IDs stable when content
before code blocks changes.

`presentation.visible-to-source-lookups` and
`presentation.source-to-visible-lookups`

Perform repeated offset mapping over the whole rendered document. These cover
the binary-search lookup path in `MarkdownPresentation`.

`controller.prefix-typing-before-code-blocks`

Simulates repeated typing in a paragraph before many code blocks through
`MarkdownEditorController`. This covers the controller edit path that previously
caused repeated full presentation rebuilds and code block identity churn.

## Output Checks

The final counters are as important as the timings:

```text
code.blocks=100
code.block.ids.retained.after-prefix-edit=100
```

`code.block.ids.retained.after-prefix-edit` should match `code.blocks` for the
current benchmark document. If it drops, a prefix edit would again cause
downstream code block views to be treated as new views in the iOS editor.

The lookup checksums are deterministic sanity checks:

```text
visible.lookup.checksum=...
source.lookup.checksum=...
```

They make sure the optimizer cannot remove the lookup loops and help flag
unexpected mapping behavior changes.

## Interpreting Results

Compare timings between release builds on the same machine. A single run is good
for quick feedback; use several consecutive runs before drawing conclusions.

This benchmark does not instantiate the iOS-only Runestone views. It covers the
data-level causes of the previous Instruments issue: stable block IDs, controller
typing before code blocks, and source/visible offset lookup cost. Use Time
Profiler on the Example app to validate UIKit, Runestone, and Tree-sitter costs.
