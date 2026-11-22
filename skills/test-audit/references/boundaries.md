# Proving behavior at the owning boundary

Prove a caller-visible contract through its production owner, with fixed external I/O fixtures and expected values that come from outside the subject.
Prefer focused integration tests and independent unit contracts over mocked internal decisions or whole-product boots.
Name the credible regression the test catches, and what it cannot prove.

Work in vertical slices: failing behavior, coherent repair, passing proof.
A regression goes red on the original defect, never on fixture setup.
Refactor under green tests, and keep every distinct contract when consolidating coverage.
Use synthetic content and keep credentials out of captured fixtures.

Needing many private controls is a sign of fragmented ownership; fix the ownership instead of adding test-only exports.

## Cost

- A test that takes seconds proves a contract no cheaper layer can.
- Inject clocks; time comes from the fixture, never from real timers, sleeps, or polling.
- Isolate each file's state, temp directories, and ports.
  Reuse a suite-level fixture for a process or server instead of booting one per test.
- Import narrow modules rather than broad barrels.
- Fix shared state at its source rather than serializing tests.
- In an end-to-end wait, wait for the produced state, never for an action's return.

## Regressions

For a bug in an external integration, prefer a CI-safe regression at the smallest production composition that reaches the defect: a real adapter with captured requests, or an independent parser contract.
Keep inherently live-only checks narrow and opt-in.

## Failures

A failing test is a defect until shown otherwise.
Reproduce it in the original run order before running it alone; an order-only failure usually means an earlier file leaks shared state.
Repair the producer: the product, the fixture, or the shared state.
Retries, longer timeouts, weaker assertions, and broader mocks hide the failure and leave the defect in place.
