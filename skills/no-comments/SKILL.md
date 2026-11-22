---
name: no-comments
description: "Comment gate. Use when about to write a code comment or docstring, or when sweeping files or a diff for comments to remove."
---

# No Comments

Code is **self-documenting**: its names, types, and structure say what it does, so it needs no comments.
Every comment falls into one [category](#categories), and its category decides its fate.
Only a **keep** stays as a comment; when in doubt, a comment goes.

Two branches:

- **Writing code**: categorize every comment before it is written, and write only a keep.
- **Sweeping files or a diff**: run the [sweep](#sweep).

## Categories

Try the categories in this order; the first that fits wins.

- **Directive**: a line a tool reads (lint suppression, formatter or type-checker pragma, license header).
  A license header and a suppression of a style-only or faulty rule stay.
  A suppression of a rule that guards correctness or safety goes, and its symbol is reshaped until the rule passes.
- **Stale**: names code, behavior, or a world that is no longer true.
  It goes.
- **Keep**: explains behavior forced by something we cannot change (a library, an identity provider, a platform, a protocol, a law) that the code alone would make look wrong, or is a docstring on a public API whose contract says more than the signature.
  It stays, and stands on its own: it names no ADR, ticket, or pull request, and tells no history.
  Where a decision came from belongs in the commit message.
- **Constraint**: guards a rule the code must keep.
  Its proof is a test, type, or lint rule, not a comment.
- **Decision record**: carries the why behind a non-obvious choice.
  It lives in an ADR, next to the decision rather than the code.
- **Excuse**: explains our own code instead of letting the code say it: a hack, a workaround, a "for now", a TODO, a surprise.
  An excuse lets the hack live on and get copied, so the code is reshaped (renamed, extracted, typed, or fixed) until it needs no excuse.
  A fix too big for the change becomes an issue.
- **Tautology**: repeats what the code already says.
  It goes.

## Sweep

Scope is the files or diff the user names; otherwise the diff against `main`, working tree included.

1. **Hunt.**
   Dispatch a subagent with the scope and this file's path, and have it categorize every comment in scope.
   It leaves keeps, constraints, and directives that stay in place.
   It deletes every other comment, marks the symbol behind every excuse and every dropped correctness suppression `RESHAPE`, and edits nothing but comments.
   It reports per file each comment's category: keeps with the forced behavior each names, `RESHAPE` flags with the excuse in one line, constraints with the rule each guards, and the why each decision record carried.
   Done when every comment in scope has a category.
2. **Verify** the report against its diff.
   Revert any edit outside comments or outside scope.
   A keep survives only with proof that its forced behavior is true today on a live path: trace the named call, or read its history (`git log -S`, `git blame`, the pull request).
   A keep that stays unproven is stale and goes.
   Restore a deleted comment only when it meets a keep exactly.
   Check every decision record's why against the repo's ADRs, and note each one no ADR covers.
3. **Reshape** every `RESHAPE` flag in scope with the smallest change that makes the code say it.
   A reshape whose root cause lies outside scope, or that outgrows the change, becomes an issue candidate.
4. **Encode, record, and file**, with the user's approval, asked in one go.
   For each constraint, offer the cheapest in-scope test, type, or lint rule that enforces it.
   For each uncovered why, offer a new ADR or an amendment to the ADR closest to it.
   For each issue candidate, offer an issue naming the hack and the code it lives in.
   For an approved encoding, write it, make the rule break once, watch the encoding go red, restore the code byte for byte, and delete the comment.
   Write an approved ADR and file an approved issue as the repo's `AGENTS.md` or `CLAUDE.md` describes.
   Delete every other constraint, and report its rule, every unrecorded why, and every unfiled issue candidate as open.
5. **Report** in the chat: deletions per category, restores, reshapes, encodings, ADRs written, issues filed, and what stays open.
