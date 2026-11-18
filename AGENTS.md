## Verification checks

Run these checks in order before you report a change to a plugin as done:

1. `bash plugins/command-guard/hooks/test-guard.sh`, which must end `failed: 0`
2. `claude plugin test plugins/mermaid`

## Naming

Everything here is public, so use generic names in skills, plugins and test data, never an employer's, customer's or private one.

## Changing a plugin

- `command-guard`: a read the guard wrongly blocks is one line in `readonly-clis.txt` plus a `check allow` case, and a `check block` case for the nearest mutation.
- `mermaid`: to update the renderer, follow the header of `plugins/mermaid/hooks/vendor/grok-mermaid.js`.
- Raise the plugin's `version` in `.claude-plugin/plugin.json` once per push that changes it.

## Vendored material

Upstream owns what vendored material does; we own what it takes to run here.
Keep `dangerous-patterns.txt` comparable to `davidondrej/skills`: groups 1 to 10 are upstream's, ours start at 11.

## Agent skills

### Issue tracker

GitHub issues in `miwurster/skills`, via `gh`.
To file, read, claim, label or close an issue, follow `docs/agents/issue-tracker.md`.

### Triage labels

The five default labels, each equal to its role name.
To apply or read one, follow `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `GLOSSARY.md` and `docs/adr/` at the repo root.
Before naming a domain concept or changing what an ADR decides, follow `docs/agents/domain.md`.
