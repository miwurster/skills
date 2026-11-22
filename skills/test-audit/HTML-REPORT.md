# HTML report

The audit report is one self-contained HTML file, written outside the repo.
Resolve the temp dir from `$TMPDIR`, falling back to `/tmp`, and write `<tmpdir>/test-audit-<repo>-<timestamp>.html` so each run gets a fresh file.
Open it with `open` on macOS or `xdg-open` on Linux, and give the user the absolute path.

Tailwind and Mermaid come from CDNs; everything else is static.

## Scaffold

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>Test audit for {{repo}}</title>
    <script src="https://cdn.tailwindcss.com/3.4.17"></script>
    <script type="module">
      import mermaid from "https://cdn.jsdelivr.net/npm/mermaid@11.17.2/dist/mermaid.esm.min.mjs";
      mermaid.initialize({ startOnLoad: true, theme: "neutral", securityLevel: "strict" });
    </script>
  </head>
  <body class="bg-stone-50 text-slate-900 font-sans">
    <main class="max-w-5xl mx-auto px-6 py-12 space-y-12">
      <header>...</header>
      <section id="summary">...</section>
      <section id="candidates" class="space-y-10">...</section>
      <section id="kept">...</section>
    </main>
  </body>
</html>
```

## Header and summary

The header holds the repo name, the `main` SHA audited, the date, the scope, and a legend for the proof map.
The summary is one row of counts per verdict, plus the test lines and production lines the candidates would remove.
Start the candidates right after it, with no introduction paragraph.

## Candidate card

Each candidate is one `<article>` with an `id`, so the chat can link to it:

- **Title**: the test's name, in mono, followed by a short claim, such as "duplicates the CSV import contract".
- **Badge row**:
  - the verdict: `Delete` in red, `Consolidate` in amber, `Fix` in indigo
  - the junk pattern, such as `lying mock` or `test-only seam`
  - the confidence: `High`, `Medium`, or `Low`
- **Proof map**: the centerpiece, described below.
- **Evidence**: the five fields from [candidate evidence](references/audit.md#candidate-evidence), as a definition list, one line each.
- **Change**: one sentence on what applying it does, naming the keeper for `Consolidate` and the seam it unlocks, if any.

If a card needs a paragraph to be understood, redraw the proof map.

## Proof map

A Mermaid `flowchart LR` from contract to tests to production owner:

- contracts on the left, as rounded nodes
- tests in the middle, labeled with their file and layer, such as `unit`, `integration`, `e2e`
- production owners on the right

Draw the keeper with a thick dark border, the candidate in red with a dashed border, and test-only seams in amber.

```html
<div class="rounded-lg border border-slate-200 bg-white p-4">
  <pre class="mermaid">
    flowchart LR
      C([CSV rows import as transactions])
      K[tests/import.rs<br/>integration]
      X[parser::tests::parse_row<br/>unit, mocked reader]
      O[import module]
      C --> K --> O
      C -.duplicate.-> X -.mock.-> O
      classDef keeper stroke:#0f172a,stroke-width:3px;
      classDef junk stroke:#dc2626,stroke-dasharray:4 4;
      class K keeper
      class X junk
  </pre>
</div>
```

Vary the map with the pattern: a lying mock shows the mock node standing in for the owner, and a test-only seam shows an extra production node reached only from the test.

## Disputed

A `disputed` candidate gets a card like any other, with a slate `Disputed` badge in place of the confidence.
Its evidence shows each reader's verdict and argument side by side.
Leave it out of the summary counts and the recommendation; the user decides it.

## Kept on purpose

A compact table of tests that looked like junk but stay, one row each: test, the pattern it resembled, and the contract from the retention bar that keeps it.
This section stops the next audit from reopening the same tests.

## Style

- Editorial, generous whitespace; serif is optional for headings.
- One accent color, plus red for delete, amber for consolidate and seams, indigo for fix.
- Plain English in short bullets, using the skill's words: contract, owner, keeper, proof, seam, junk.
