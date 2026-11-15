# AGENTS.md

General-purpose skills under `skills/`, installed with `npx skills`, and plugins under `plugins/`, copied into a project by `./sync`.
Everything here is public: keep employer, customer and private names out of skills, plugins and test data.

## Changing a plugin

- `command-guard`: run `bash plugins/command-guard/hooks/test-guard.sh` after any edit; it must end `failed: 0`.
  A read the guard wrongly blocks is one line in `readonly-clis.txt` plus a `check allow` case, and a `check block` case for the nearest mutation.
- `mermaid`: run `claude plugin test plugins/mermaid`.
  To update the renderer, follow the header of `plugins/mermaid/hooks/vendor/grok-mermaid.js`.
- Raise the plugin's `version` in `.claude-plugin/plugin.json` once per push that changes it.

## Vendored material

Upstream owns what vendored material does; we own what it takes to run here.
Keep `dangerous-patterns.txt` comparable to `davidondrej/skills`: groups 1 to 10 are upstream's, ours start at 11.
