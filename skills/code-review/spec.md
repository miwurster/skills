# Spec axis

Check that the diff faithfully implements the spec it was given, no less and no more.
Report in the format of [findings.md](findings.md).

How the code is written belongs to the Standards axis, behavior bugs outside a requirement to the Correctness axis, and vulnerabilities to the Security axis.

## What to report

- **Missing or partial**: a requirement the spec asked for that the diff leaves out or only half implements.
  Its evidence is the quoted spec line; a partial one adds the `file:line` where it stops.
- **Scope creep**: behavior in the diff that the spec didn't ask for.
- **Wrong**: a requirement that looks implemented, but where the implementation looks wrong.

Quote the spec line in every finding's **Claim** or **Evidence**.

## Done

Every requirement in the spec is accounted for as met or as a finding, every changed file has been checked for behavior the spec did not ask for, and the findings meet the done rule of [findings.md](findings.md).
