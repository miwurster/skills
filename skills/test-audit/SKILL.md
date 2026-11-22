---
name: test-audit
description: "Test value gate. Use when writing, changing, or reviewing a test, or auditing a test suite for duplicate, implementation-coupled, or junk proof and test-only production seams."
---

# Test Audit

A test earns its place by proving a **contract**: caller-visible behavior, an invariant, or an independent external promise.
Each contract has one **owner** test at the strongest boundary that reaches it, the **keeper**.
Everything else is **junk** to reject when writing and to remove when auditing.

Two branches:

- **Writing or changing a test**: run the [authoring gate](#authoring-gate) on every new or changed test.
- **Auditing a suite**: run the [audit](#audit), in coherent owner batches.
  Aim at proof quality; a deletion count is never the goal.

## Authoring gate

Before adding a test, answer all four:

1. Which observable behavior, invariant, or independent contract does it protect?
2. Which credible regression makes it go red?
3. Why does existing proof miss that regression?
   One owner per contract; a second layer earns a test only for a distinct transport or lifecycle risk.
   Extend an existing table or shared fixture before adding a new file, and consolidate repeated setup.
4. Does it need an export, flag, wrapper, or injection hook that no production caller uses?
   Then move the proof to the real boundary and leave production untouched.

A test that cannot answer 1 and 2 stays unwritten.
For where the boundary sits and how to write the regression, read [references/boundaries.md](references/boundaries.md).

Rules that hold for every test:

- A regression goes red before the fix, for the intended reason, and green after it.
  When the pre-fix run is unavailable, say so in the report.
- One owner regression covers a bug; leave the other layers it crosses alone.
- A behavior-preserving refactor keeps the test green.

## Junk patterns

Reject these when writing a test:

- self-comparisons, and expected values the subject itself generates
- copied inventories, and greps over source text
- assertions on implementation details or call shapes
- a second proof of a contract another test already owns
- test-only production seams
- mocks that supply the very behavior under assertion
- fixtures that fabricate receipts or ordering the owner should produce, or claim persistence on a path the code never writes
- negative controls that go red on an unrelated guard
- names that promise behavior the test never exercises

When auditing, use the [full checklist](references/audit.md#junk-patterns).

## Retention bar

Keep tests that guard an independent contract, even when they are static or slow:

- public API, SDK, protocol, config, and CLI surface
- migrations and storage formats
- security, platform, and defaults
- exact bytes a user or another system depends on, such as prompts, generated code, or file formats
- packaging, release, and architecture rules
- observable ordering

Source inspection stays when it is the cheapest guard of a user-facing contract and survives an identifier-only rename.
A test that already fails at the baseline may be catching a real bug: reproduce it and repair the owner.

## Audit

1. **Discover**, read-only.
   Follow [candidate evidence](references/audit.md#candidate-evidence) for every candidate.
   Done when every candidate has a verdict, all five evidence fields, and a confidence.
   A candidate with missing evidence stays `Retain`.
   A candidate that two readers judged differently is `disputed`: it goes in the report with both arguments, never as a recommendation.
2. **Report.**
   Write the HTML report as described in [HTML-REPORT.md](HTML-REPORT.md) and open it.
   Then ask: "Which candidates should I apply?"
3. **Apply** the chosen candidates in owner batches.
   Batches whose file sets are disjoint can run as parallel subagents in one checkout; each edits and tests only its own files.
   Delete the production seams the removed tests unlock, along with the tests.
   Move a retained regression to its owner before deleting its old home.
   For every new, fixed, or moved assertion, make one deliberate **mutation** of the production owner, watch the test go red, and restore the owner byte for byte.
4. **Validate** as described in [validation](references/audit.md#validation).
   Done when every new, fixed, or moved assertion has a caught mutation, the owner and sibling tests are green, the repo's own checks pass, and the diff has been reviewed.
5. **Hand off** in the chat:
   causes found, contracts retained, proof run and its cost, production versus test lines removed, and follow-ups.
   Commit and push only when the user asks.
