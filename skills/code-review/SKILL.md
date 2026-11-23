---
name: code-review
description: "Review the changes since a fixed point (commit, branch, tag, or merge-base) along four axes: Standards (does the code follow this repo's documented coding standards?), Spec (does the code match what the originating issue/spec asked for?), Correctness (does it behave right?), and Security (does it open an attack path?). Runs every axis in a parallel sub-agent and reports them side by side. Use when the user wants to review a branch, a PR, work-in-progress changes, or asks to \"review since X\"."
---

Four-axis review of the diff between `HEAD` and a fixed point:

- **Standards**: does the code conform to this repo's documented coding standards?
- **Spec**: does the code faithfully implement the originating issue / spec?
- **Correctness**: does the changed code behave right, at its edges and under load?
- **Security**: does the change introduce or widen an exploitable vulnerability?

Each axis runs as a **parallel sub-agent** with a fresh context window, so the axes don't pollute each other, then this skill aggregates their findings.
The review is a report: it fixes nothing, and it runs to the end without asking, so a caller can act on the findings.

## Process

### 1. Pin the fixed point

The fixed point is whatever the caller said (a commit SHA, branch name, tag, `main`, `HEAD~5`, etc.); with none given, use `git merge-base main HEAD`.

Capture the diff command once: `git diff <fixed-point>...HEAD` (three-dot, so the comparison is against the merge-base).
Also note the list of commits via `git log <fixed-point>..HEAD --oneline`.

Before going further, confirm the fixed point resolves (`git rev-parse <fixed-point>`) and the diff is non-empty.
A bad ref or empty diff ends the review here, reported as such, not inside four parallel sub-agents.

### 2. Identify the spec source

Look for the originating spec, in this order:

1. Issue references in the commit messages (`#123`, `Closes #45`, GitLab `!67`, etc.), fetched via the issue-tracker doc the repo's `AGENTS.md` or `CLAUDE.md` points at.
2. A path the caller passed as an argument.
3. A spec file under `docs/`, `specs/`, or `.scratch/` matching the branch name or feature.

With none found, the **Spec** sub-agent is skipped and the report says "no spec available".

### 3. Spawn the sub-agents in parallel

Each axis is a file in this skill's base directory: [standards.md](standards.md), [spec.md](spec.md), [correctness.md](correctness.md), [security.md](security.md).
Issue all sub-agent calls together, in the foreground.
Each prompt carries:

- The absolute path of its axis file, with the instruction to read it and apply it as the complete brief.
- The diff command and the commit list.
- For **Spec**, the path or fetched contents of the spec.

Every axis reports in the format of [findings.md](findings.md); the axis file says so, and the prompt does not restate it.

### 4. Aggregate

Present the reports under `## Standards`, `## Spec`, `## Correctness` and `## Security`, verbatim or lightly cleaned.
Do **not** merge or rerank findings, because the axes are deliberately separate (see _Why separate axes_).

End with a one-line summary: total findings per axis, and the worst issue _within each axis_ (if any).
Don't pick a single winner across axes: that's the reranking the separation exists to prevent.

## Why separate axes

A change can pass one axis and fail another:

- Code that follows every standard but implements the wrong thing → **Standards pass, Spec fail.**
- Code that does exactly what the issue asked but breaks on an empty list → **Spec pass, Correctness fail.**
- Code that is correct for every honest caller but trusts a hostile one → **Correctness pass, Security fail.**

Reporting them separately stops one axis from masking another.
Each axis file names what belongs to its neighbours, so a finding lands on one axis only.
