# Findings

The format every axis reports in.
List findings most severe first, one block each.

- **Severity**: `blocker`, `major`, or `minor`.
  - `blocker`: broken behavior, an exploitable vulnerability, or an unimplemented requirement the change must not land with.
  - `major`: a real defect worth a decision of its own.
  - `minor`: a worthwhile improvement with low risk either way.
- **Claim**: one sentence stating the defect.
- **Evidence**: `file:line` references into the source as it stands at `HEAD`; open every file you cite and take the line number from the file, never from the diff.
  A requirement the diff never implements has no line: its evidence is the quoted spec line.
- **Rule**: the rule the finding enforces, cited by file and rule, or by the axis rule's name.
  Leave the field out when the finding rests on judgement alone.
- **Direction**: the sketched fix, far enough that a reader can judge it without asking.

Rate severity at the finding's traced worth: an inflated one burns the reader's trust.
An axis with nothing to report says so in one line.
