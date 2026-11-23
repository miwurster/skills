<!--
Derived from cursor/plugins `thermos/skills/thermo-nuclear-review/SKILL.md` at 7a583913eb1b8d1a0ee76753d1a2cf072e7b54f9, rewritten, not tracked.
MIT, see LICENSE-cursor.
Modified: narrowed to behavior defects, security and the PR-discussion step dropped, hunts and a traced completion criterion added.
-->

# Correctness axis

Audit the diff for behavior defects: places where the changed code does the wrong thing at runtime.
Report findings in [findings.md](findings.md); this axis reports and fixes nothing.

## Boundary

Security belongs to the Security axis.
Style, naming, smells and documented conventions belong to the Standards axis.
Whether the change does what the spec asked belongs to the Spec axis.
This axis asks one question: given what the code is meant to do, does it behave?

## Hunts

- **Logic**: wrong conditions, inverted branches, off-by-one, wrong operator or variable, swallowed errors, a return value ignored.
- **Edge values**: empty, zero, null, negative, max, unicode, time zones and DST, and the first and last element.
- **Concurrency and re-runs**: races, shared mutable state, idempotency of retries and replays, partial failure that leaves state half-written.
- **Ripple**: a change in one module that breaks a caller elsewhere; follow every cross-module dependency the change touches.
- **Breaking changes**: altered signatures, API responses, schemas, migrations, serialized formats, config keys, environment variables, ports, or a new manual setup step that existing callers or developers will trip over.
- **Gate leaks**: behavior meant to sit behind a feature flag that becomes reachable without it.
- **Tests**: changed behavior with no test that exercises it, and tests that cannot fail because they assert nothing, mock the unit under test, or assert what the code returns rather than what it should.
- **Scale**: N+1 queries, unbounded fetches, loops or retries, and work whose cost grows with data the author tested small.

## Method

1. Read the commit list to learn what the change means to do.
2. For every changed function or code path, find its callers and trace each from the call site through the change to its effects.
   Open the code you depend on; a claim that rests on "if the other side handles it" is unfinished research.
3. Run every hunt against each traced path.
4. Report a finding only once it is traced end to end and you can name the input that triggers it.

The step is done when every changed function or code path is traced.
End the report with one line, `Traced:`, listing each traced function or path, so a gap is visible to the reader.

## False positives

- Pre-existing defects in code the diff does not touch.
- Anything a compiler, linter or type checker catches.
- Behavior changes the commits state as intended and keep in scope; report one anyway when its blast radius looks larger than the author seems to know.
- Nitpicks with no runtime consequence.

## Severity

- `blocker`: a traced input breaks behavior, corrupts or loses data, or breaks a caller, API, schema or config on landing.
- `major`: a defect on a realistic but narrower path, a missing test for changed behavior, or a scale cost that will bite at production volume.
- `minor`: a narrow edge case, or a test that could be sharper.

## Rule

A correctness finding usually cites no rule: a bug leaves Rule out.
