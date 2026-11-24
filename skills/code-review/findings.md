# Findings

The format every axis reports in.
List findings most severe first, one block each.

- **Severity**: `blocker`, `major`, or `minor`.
  - `blocker`: broken behavior, an exploitable vulnerability, or an unimplemented requirement the change must not land with.
  - `major`: a real defect worth a decision of its own.
  - `minor`: a worthwhile improvement with low risk either way.

  Where the verify step rates it differently, it appends its own: `major (verifier: minor)`.
- **Claim**: one sentence stating the defect.
- **Evidence kind**: `executed`, `read`, or `inferred`, defined under _Evidence kinds_.
- **Evidence**: `file:line` references into the source as it stands at `HEAD`; open every file you cite and take the line number from the file, never from the diff.
  A requirement the diff never implements has no line: its evidence is the quoted spec line.
  An `executed` finding adds the check's full source, the command that runs it, and the captured output that shows it red, so another agent can recreate it.
- **Rule**: the rule the finding enforces, cited by file and rule, or by the axis rule's name.
  Leave the field out when the finding rests on judgement alone.
- **Direction**: the sketched fix, far enough that a reader can judge it without asking.
  An `inferred` finding also names the check that would turn it `executed`, or why none can run.
- **Status**: `confirmed`, `refuted`, or `unresolved`, with a one-line **Basis**.
  Only the verify step sets it.

Rate severity at the finding's traced worth: an inflated one burns the reader's trust.
A `blocker` is `executed` or `read`; an `inferred` finding is at most `major`, unless its harm is severe and irreversible (data loss, a breach) and its check stays unrun under _Executed checks_, which its Evidence then says.
An axis with nothing to report says so in one line.

## Evidence kinds

- `executed`: a check you ran against `HEAD` goes red on the defect.
- `read`: the defect is in what the source or spec says, settled by reading it: a breached documented standard, a missing requirement, a missing test, a hard-coded secret, an altered signature.
- `inferred`: runtime behavior concluded from reading code, without running it.

What code does at runtime is `executed` or `inferred`, never `read`.

## Executed checks

Every finding about runtime behavior gets an executed check: a test or script, named for the defect, that asserts the behavior the Claim says is correct and feeds it the input the finding names.
**Red** means that assertion fails; **green** means it holds.
A check that errors before its assertion (a missing dependency, an import error) has not run yet: fix the setup, or treat it as unrun.

Run it in a throwaway worktree, so the checkout under review stays as it stands:

1. `tmp=$(mktemp -d)`, then `git -C <repo> -c core.hooksPath=/dev/null worktree add --detach "$tmp" HEAD` and `git -C "$tmp" submodule update --init --recursive`.
   Installing dependencies from the repo's lockfile is allowed; other network access is not.
2. Write the check by absolute path under `$tmp`, and run it with `$tmp` as the working directory, with the repo's own test runner where one fits.
3. `git -C <repo> worktree remove --force "$tmp"`, whatever the outcome.

Read another revision with `git show <rev>:<path>`, or check it out in the throwaway worktree.

The check observes the defect without causing harm: a payload writes only a marker under `$tmp`.
A check stays **unrun** when it needs secrets, a network target, a service the repo cannot start locally, or would write outside `$tmp` (a database, the home directory); its finding stays `inferred`, and its Evidence says why.

Red keeps the finding as `executed`.
Green refutes the claim the check tested: drop the finding, or rewrite the claim to what the check left open, as `inferred`, with its Direction naming the next check.

## Done rule

A report is done when every finding about runtime behavior is `executed`, or `inferred` with its Evidence saying why its check stays unrun.
