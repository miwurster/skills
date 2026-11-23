<!--
Derived from anthropics/claude-code-security-review, .claude/commands/security-review.md, at 0c6a49f1fa56a1d472575da86a94dbc1edb78eda; rewritten, not tracked.
MIT License, see LICENSE-anthropic-security-review.
Modified: recast as a report-only review axis with the shared findings format, OWASP Top 10:2025 hunts, AI-and-agent hunts, Security rules, and a traced method in place of confidence scoring and sub-task filtering.
-->

# Security axis

Audit the diff for exploitable vulnerabilities it introduces or widens.
A finding is a concrete attack path or a broken Security rule.
Weaknesses in code the diff leaves untouched are out of scope.
Agent instructions and configuration (`SKILL.md`, `CLAUDE.md`, `AGENTS.md`, hooks, MCP config) count as code.
A bug with no security impact belongs to the Correctness axis; style belongs to Standards.
Report every finding in the format of [findings.md](findings.md).

## Method

1. **Context**: find the repo's existing security frameworks, validation and sanitization patterns, and trust boundaries: where untrusted input enters and which operations are sensitive.
2. **Comparison**: hold each changed file against that context, and mark every deviation from an established pattern and every new attack surface as a lead.
3. **Assessment**: trace each lead from untrusted input to sensitive operation, through every check on the path.

Done when every changed file has passed all three steps and every lead is either a finding or dropped with its reason.
A finding's Evidence names the attack path: the entry point, each hop, and the sink, each at `file:line`.

## Hunts

Prefix each finding's Claim with its OWASP Top 10:2025 ID, for example `A05:2025`.
The ID classifies; the Rule field stays a Security rule or a repo standard.

- **A01 Broken Access Control**: missing or bypassable authorization on a new endpoint or action, IDOR, privilege escalation, path traversal, SSRF controlling host or protocol, CORS opened to untrusted origins.
- **A02 Security Misconfiguration**: debug mode, verbose errors or stack traces to clients, permissive defaults, disabled security headers, XXE-enabled parsers, CI workflows triggerable by untrusted input with write tokens.
- **A03 Software Supply Chain Failures**: a new source of code the build or runtime executes: an unpinned action, image, script piped from the network, or a registry the repo does not already trust.
  Known-vulnerable package versions belong to the repo's dependency scanning.
- **A04 Cryptographic Failures**: weak or home-made algorithms, hard-coded keys, predictable randomness for secrets or tokens, disabled certificate validation, sensitive data sent or stored in plaintext.
- **A05 Injection**: SQL, NoSQL, OS command, template, LDAP, XPath, eval, and XSS (reflected, stored, DOM) where untrusted input reaches an interpreter.
- **A06 Insecure Design**: a security decision made on the client, a trust boundary the design never enforces, a business flow an attacker can replay or reorder for gain.
- **A07 Authentication Failures**: authentication bypass, session fixation or tokens that never expire, JWT accepted unsigned or with `alg: none`, credentials compared in non-constant time where timing is observable.
- **A08 Software or Data Integrity Failures**: unsafe deserialization (pickle, YAML, Java serialization), unsigned updates or artifacts, data trusted across a boundary without an integrity check.
- **A09 Security Logging and Alerting Failures**: secrets, passwords, tokens, or PII written to logs; an existing security event log or alert the diff removes.
- **A10 Mishandling of Exceptional Conditions**: an exception inside a security check that falls through to allow, a swallowed error that skips validation, an error response leaking internals.

## AI and agents

Apply this section when the diff calls a model or gives one tools, memory, or other agents.
Model output, and anything that reaches a model's context (user text, retrieved documents, tool results, web pages, files), is untrusted input.
Cite the matching OWASP Top 10 for LLM Applications 2026 or Top 10 for Agentic Applications 2026 ID in the Claim beside the A-ID it maps to.

- **Prompt injection** (LLM01:2026, ASI01): untrusted content reaches the context of a model that can trigger a tool or sink, with no control in code between them.
- **Sensitive data in context** (LLM02:2026): secrets, PII, or another tenant's data placed where the model can repeat it to the wrong user.
- **Excessive agency** (LLM03:2026, ASI02): a tool broader than the task needs, a destructive tool without human confirmation, tool arguments used without validation.
- **Improper output handling** (LLM10:2026): model output flowing into eval, shell, SQL, HTML, or a file path without the same treatment as user input.
- **Unbounded consumption** (LLM06:2026): unbounded loops, tokens, or spend reachable by an untrusted caller; rate at most `major`.
- **Secrets in hidden context** (LLM08:2026): credentials or tokens in a system prompt or tool schema.
- **Agentic supply chain** (LLM04:2026, ASI04): an MCP server, plugin, or skill pulled unpinned or from an untrusted source.
- **Unexpected code execution** (ASI05): agent-written code run outside a sandbox.
- **Memory poisoning** (ASI06): untrusted content written to memory or a knowledge store that a later run trusts.
- **Confused deputy** (ASI03): the agent acts with its own credentials on behalf of a caller who holds fewer rights.

## Security rules

Cite these by name in a finding's Rule.
Where the repo's `CODING_STANDARDS.md` covers the same concern, it wins.

- **Trust boundaries**: validate and normalize input at every trust boundary; deny by default.
- **No concatenation**: build queries, commands, and paths with parameters or safe APIs, never by string concatenation from untrusted input.
- **No secrets in the repo**: keep secrets out of source, committed config, and logs.
- **Vetted crypto**: take crypto and authentication from the platform or a vetted library.
- **Least privilege**: grant each component, token, and tool only the rights its task needs.
- **Fail closed**: an error inside a security check denies.
- **Trusted dependencies**: pin every dependency and take it from a registry the repo already trusts.

## Severity

- `blocker`: directly exploitable, leading to remote code execution, a data breach, or an authentication bypass.
- `major`: needs specific conditions but has significant impact; only with a concrete attack path traced.
- `minor`: a broken Security rule with no attack path traced.

## Exclusions and precedents

Each exclusion applies only where no Security rule is broken.

- Denial of service, rate limiting, and resource exhaustion, except unbounded consumption under AI and agents.
- Race conditions and timing attacks unless concretely exploitable.
- Memory safety issues in memory-safe languages.
- Files used only by tests.
- Log spoofing; logging URLs or non-sensitive, non-PII data.
- SSRF that controls only the path.
- Regex injection and regex denial of service.
- Resource leaks such as memory or file descriptors.
- A missing hardening measure or audit log with no concrete vulnerability.
- Tabnabbing, XS-Leaks, prototype pollution, and open redirects unless the exploit is concrete.
- Environment variables and CLI flags are trusted.
- UUIDs are unguessable.
- React and Angular escape output; XSS there needs `dangerouslySetInnerHTML`, `bypassSecurityTrustHtml`, or a similar escape hatch.
- Client-side code needs no authorization or authentication checks; the server enforces them.
- Shell scripts, CI workflows, and notebooks rarely see untrusted input; report one only with the specific path that delivers it.
- A system prompt is no security boundary: untrusted content in a prompt is a finding only where it reaches a tool or sink, and a control that lives only in a prompt counts as absent.
