<!--
Derived from the ideas of captivus/agent-review `SKILL.md` at 031841cb9e2d3403546d5e5b56cd877c51d86006, written fresh, not tracked.
MIT, see LICENSE-agent-review.
-->

# Verify

Try to refute each finding you were given, against the code as it stands at `HEAD`.
The findings are in the format of [findings.md](findings.md).
You set each finding's Status, and add an upgraded Evidence kind or your own Severity where they differ; you write checks only in a throwaway worktree, as findings.md describes under _Executed checks_, so the reviewed checkout stays as it stands.

## Method

For each finding:

1. Open every `file:line` in its Evidence, including the callers the claim depends on.
2. Settle the claim by the strongest check its evidence kind allows:
   - `executed`: read the check and confirm its assertion encodes the behavior the Claim says is correct, then recreate it from the Evidence in a fresh worktree and run it.
     Red confirms it; an assertion that encodes a misreading refutes it.
   - `inferred`: write and run the check its Direction names, or one of your own.
     Red confirms it and upgrades it to `executed`, with the check added to its Evidence as findings.md describes; green refutes it.
     Where its Evidence says the check stays unrun, settle it by reading.
   - `read`: reread the cited source, the quoted spec line against the spec you were given, and any cited **Rule**.
     A finding with no Rule is `confirmed` when the cited code shows the shape its Claim describes; disagreement with the judgement is no refutation.
3. Set **Status** with its **Basis**:
   - `confirmed`: the check went red, or the source says what the claim says.
   - `refuted`: the check went green, the cited code does not say what the claim says, or the rule does not apply.
   - `unresolved`: no check could run and reading cannot settle it.
4. Rate the severity again by findings.md, and append yours where it differs.

Doubt lands on `unresolved`; `refuted` needs evidence that the claim is false.

## Report

Return every finding you were given, in its original order, with Status, Basis, and any upgraded Evidence kind or Severity.

## Done

Every finding has a Status whose Basis is a check you ran or a source line you read; an `unresolved` Basis names why neither could settle it.
