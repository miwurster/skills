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
- It reads a shell script the command runs, such as `bash deploy.sh` or `./deploy.sh`, and applies the first two rules to it.

### `mermaid`

A mod that draws each ` ```mermaid ` block in a reply as box-drawing text.
It crops a diagram too wide for the window and adds a **Show full chart** button.
The button opens the diagram in a pane, where `h` and `l` pan.

### Install

Claude Code loads a plugin from a `skills/<plugin>/` folder in place, with no marketplace and no install.
`sync` copies it there, from a clone of this repo.
It copies the files the plugin runs, leaves the tests here, and writes the source commit into `<plugin>/SOURCE`.

For one project, into its `.claude/skills/`; commit the result there:

```sh
./sync ../my-project command-guard mermaid
```

For yourself, in every session, into `~/.claude/skills/`, or `$CLAUDE_CONFIG_DIR/skills/` when that is set:

```sh
./sync --user command-guard mermaid
```

To update, pull this repo and run the same command again; then restart Claude Code.
To uninstall, delete the plugin's folder.

## Tests

```sh
bash plugins/command-guard/hooks/test-guard.sh   # must end "failed: 0"
claude plugin test plugins/mermaid
```

## License

MIT, see `LICENSE`.
`plugins/command-guard/hooks/dangerous-patterns.txt` started from [davidondrej/skills](https://github.com/davidondrej/skills).
`plugins/mermaid/hooks/vendor/` is [grok-mermaid](https://github.com/xl0/grok-mermaid), Apache-2.0.
