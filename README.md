# skills

My general-purpose Claude Code skills, hooks and mods.
Each works in any repo, for anyone.

## Skills

### `conventional-commit`

Commits the current changes with a Conventional Commits message.
A ticket in the scope is optional.

### Install

Install a skill into a project with [`skills`](https://github.com/vercel-labs/skills):

```sh
DISABLE_TELEMETRY=1 npx skills add miwurster/skills -a claude-code --copy -s conventional-commit
```

Commit `.claude/skills/` and `skills-lock.json`.
`npx skills update -p` updates the installed skills to their newest version.

## Plugins

### `command-guard`

A `PreToolUse` hook on every agent `Bash` command.
It needs `jq`; without it every command passes.

- It denies the irreversible: `rm -rf /`, `dd`, `git push --force`, `gh` and `glab repo delete`, and credential reads.
- It allows only reads for `kubectl`, `gcloud`, `aws`, `terraform`, `terragrunt` and `helm`.
- It denies any command that Claude Code's own parser cannot check.

### `mermaid`

A mod that draws each ` ```mermaid ` block in a reply as box-drawing text.
It crops a diagram too wide for the window and adds a **Show full chart** button.
The button opens the diagram in a pane, where `h` and `l` pan.

### Install

Claude Code loads a plugin committed under a project's `.claude/skills/<plugin>/` in place, with no marketplace and no install.
`sync` copies it there:

```sh
./sync ../my-project command-guard mermaid
```

It copies the files the plugin runs, leaves the tests here, and writes the source commit into `<plugin>/SOURCE`.
Commit the result in the target repo.

## Tests

```sh
bash plugins/command-guard/hooks/test-guard.sh   # must end "failed: 0"
claude plugin test plugins/mermaid
```

## License

MIT, see `LICENSE`.
`plugins/command-guard/hooks/dangerous-patterns.txt` started from [davidondrej/skills](https://github.com/davidondrej/skills).
`plugins/mermaid/hooks/vendor/` is [grok-mermaid](https://github.com/xl0/grok-mermaid), Apache-2.0.
