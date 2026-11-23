# Standards axis

Check that the diff follows how this repo says code should be written.
Report in the format of [findings.md](findings.md).

Behavior bugs belong to the Correctness axis, vulnerabilities to the Security axis, and whether the change does what was asked to the Spec axis.

## Standards sources

Search the repo for every file that documents how code should be written.
When `CODING_STANDARDS.md` or `CONTRIBUTING.md` exists, it is on the list.
A breach of a documented standard cites that standard in **Rule**: file and the rule.
Skip anything tooling already enforces.

## Smell baseline

On top of whatever the repo documents, this axis always carries a fixed set of Fowler code smells (_Refactoring_, ch.3) that applies even when a repo documents nothing.
Two rules bind it:

- **The repo overrides.** A documented repo standard always wins; where it endorses something the baseline would flag, suppress the smell.
- **Always a judgement call.** A smell goes in the **Claim** as "possible <Smell>", leaves **Rule** out, and is at most `major`.

Prefer the finding that deletes complexity over one that rearranges it: the simpler, smaller version that feels inevitable in hindsight.

Each smell reads _what it is_ → _how to fix_; match it against the diff:

- **Mysterious Name**: a function, variable, or type whose name doesn't reveal what it does or holds. → rename it; if no honest name comes, the design's murky.
- **Duplicated Code**: the same logic shape appears in more than one hunk or file in the change. → extract the shared shape, call it from both.
- **Feature Envy**: a method that reaches into another object's data more than its own. → move the method onto the data it envies.
- **Data Clumps**: the same few fields or params keep travelling together (a type wanting to be born). → bundle them into one type, pass that.
- **Primitive Obsession**: a primitive or string standing in for a domain concept that deserves its own type. → give the concept its own small type.
- **Repeated Switches**: the same `switch`/`if`-cascade on the same type recurs across the change. → replace with polymorphism, or one map both sites share.
- **Shotgun Surgery**: one logical change forces scattered edits across many files in the diff. → gather what changes together into one module.
- **Divergent Change**: one file or module is edited for several unrelated reasons. → split so each module changes for one reason.
- **Speculative Generality**: abstraction, parameters, or hooks added for needs the spec doesn't have. → delete it; inline back until a real need shows.
- **Message Chains**: long `a.b().c().d()` navigation the caller shouldn't depend on. → hide the walk behind one method on the first object.
- **Middle Man**: a class or function that mostly just delegates onward. → cut it, call the real target direct.
- **Refused Bequest**: a subclass or implementer that ignores or overrides most of what it inherits. → drop the inheritance, use composition.

## Done

Every changed file has been checked against every documented standard and every smell, and every finding cites `file:line`.
