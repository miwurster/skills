---
name: conventional-commit
description: Commit the current changes with a Conventional Commits message. Use for every commit, including "commit and push" and a step in another skill that says to commit.
---

# Conventional commit

Invoking this skill is the go-ahead to commit.
Every gate below resolves from the diff, the branch and the task context, with a **safe default** where those are silent, so the run finishes without asking.

## Process

Open with **one batch** of parallel tool calls: `git diff --staged`, `git diff`, `git status`, the branch name, and `docs/agents/issue-tracker.md` (for the scope).

1. **Read the changes**: the staged diff, or the working-tree diff and status if nothing is staged.
   The diff decides the summary.
2. Work through **Type**, **Scope**, **Breaking**, **Message shape** and **Commit**, in that order.
3. **Print** the committed message last, in a single code block: subject, body and footer exactly as committed, nothing else inside the block.
   A failed commit still prints its message, followed by the reason it failed.

## Type

The release column is what `semantic-release` bumps for that type.

| Type       | Use for                        | Release   |
|------------|--------------------------------|-----------|
| `feat`     | new feature                    | **minor** |
| `fix`      | bug fix                        | **patch** |
| `perf`     | performance improvement        | **patch** |
| `refactor` | code change, no feature or fix | none      |
| `docs`     | documentation only             | none      |
| `test`     | add or correct tests           | none      |
| `build`    | build system or dependencies   | none      |
| `ci`       | CI config and scripts          | none      |
| `chore`    | no src or test change          | none      |

- The invocation names a type (a bare `feat`, `fix`, … or a `--feat`, `--fix`, … flag from the table): use it verbatim.
- The user wants to **cut a release** ("cut a release", "ship a new version", or a clear equivalent): `feat` for a new capability, `perf` for a speedup, `fix` for everything else.
- Otherwise: the type that matches the change, whatever bump it causes.

## Scope

The scope is a ticket reference, the whole reference and nothing else.
It is optional: a subject without a ticket has no scope, and its type stands as picked.

Take the first hit, in this order:

1. A reference given in the task context this run.
2. The branch name, when `docs/agents/issue-tracker.md` names a tracker:
   - **Jira**: `<KEY>-<number>`, the project key from that doc.
   - **GitHub / GitLab**: a leading `<number>-` segment, written as `#<number>`.
3. Nothing found: no scope.

## Breaking

A breaking change cuts a **major** release, so it needs an **explicit** ask in the task: "this is breaking", "major bump", "new major version", or a clear equivalent.
The size or risk of the diff is not an ask.
Without one, the commit is non-breaking.

When asked:

- Mark the subject with `!` after the type and scope: `feat(PSD-123)!: …`.
- Add a `BREAKING CHANGE: <what broke and how to migrate>` footer after a blank line.
  The footer is what makes `semantic-release` bump major.

## Message shape

Subject:

- `<type>(<scope>): <summary>`, or `<type>: <summary>` without a scope.
- Imperative mood, lowercase after the colon, no trailing period.
- ≤50 chars; hard cap 72.

Body, wrapped at 72 chars, bullets as `-`:

- Write one for a non-obvious *why*, and always for a breaking change, a security fix or a data migration.
- Leave it out when the subject speaks for itself.

The ticket lives in the scope alone; the one footer this skill writes is `BREAKING CHANGE:`.
Subject and body describe the change itself.
The message ends with the body or the `BREAKING CHANGE:` footer: no `Co-authored-by:`, `Generated with`, or other attribution trailer.

## Commit

Commit the message exactly, through a quoted heredoc on stdin, so backticks and `$` stay literal:

```sh
git commit -F - <<'EOF'
<message>
EOF
```

Staging:

- Commit what is staged.
- Nothing staged: stage, file by file, the changes that belong to the task being committed, whoever wrote them.
  Unrelated working-tree changes stay unstaged.
- Nothing to commit: stop and report it.

Commit on the branch checked out now, the default branch included.
A new commit every time, never `--amend`, never a merge.
On "commit and push", commit and print here, then push as a separate step.

## Examples

Bug fix on a Jira ticket (branch `feature/PSD-123-cart`), self-explanatory:

```
fix(PSD-123): stop double-charge on retry
```

New feature without a ticket; the body carries the non-obvious *why*:

```
feat: add passkey login

WebAuthn lets users skip passwords on trusted devices, ahead of
the SMS-OTP provider being sunset next quarter.
```

Breaking change the task asked for:

```
feat(#204)!: drop v1 token endpoint

BREAKING CHANGE: /v1/token removed. Move clients to /v2/token;
old route returns 410.
```
