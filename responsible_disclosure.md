# Responsible Disclosure

Thank you for taking the time to help keep this project — and the agents that consume its skills — safe.

## Why skills need a disclosure process

Skills are loaded directly into the context of coding agents — Claude Code, Claude Agent SDK, Cursor, GitHub Copilot, Aider, Continue, Cody, Windsurf, OpenAI Codex CLI, Goose, Gemini CLI, and similar tools. A malicious or buggy skill can do more than crash a program: it can steer an agent into running unsafe shell commands, exfiltrating files, or producing insecure code. Treat security issues here with the same seriousness as a vulnerability in a runtime library.

## In scope

- Prompt-injection payloads embedded in `SKILL.md` content, descriptions, or referenced files.
- Scripts (`scripts/`) or assets that execute unsafe commands, leak secrets, or escalate privileges.
- Instructions that cause an agent to bypass user confirmation for destructive actions (`rm -rf`, force-push, credential dumping, etc.).
- Skills that read, transmit, or persist data outside the user's working directory without consent.
- Supply-chain risks: typosquatted skill names, dependency confusion, or instructions that fetch and execute remote code.

## Out of scope

- Vulnerabilities in the host agent itself — report those upstream to the agent's vendor (e.g. Anthropic for Claude Code / Claude Agent SDK, Anysphere for Cursor, GitHub for Copilot, Sourcegraph for Cody, Codeium for Windsurf, OpenAI for Codex CLI, Google for Gemini CLI, the maintainers for Aider / Continue / Goose).
- Issues that require an already-compromised machine or a malicious operator.
- Theoretical concerns without a demonstrable trigger.

## How to report

<!-- TODO: replace this block with your preferred contact channel before publishing. -->
**Contact:** _Not yet configured._ Please open a private channel with the maintainer before publishing details.

When reporting, include:

1. The affected skill (path or name) and commit hash.
2. A minimal reproduction — ideally a transcript showing the agent's behavior.
3. The impact: what an attacker could achieve, and under what assumptions.
4. Any suggested mitigation, if you have one.

Please **do not** open a public GitHub issue for security-sensitive reports.

## What to expect

- **Acknowledgement** within 5 business days.
- **Triage and severity assessment** within 10 business days.
- **Fix or mitigation** on a timeline proportional to severity. Critical issues (active exploitation, secret exfiltration) are prioritized.
- **Credit** in the changelog or release notes if you would like it. Let us know your preferred name/handle.

## Safe harbor

We will not pursue legal action against researchers who:

- Make a good-faith effort to avoid privacy violations, data destruction, and service disruption while testing.
- Report findings privately and give a reasonable window for remediation before public disclosure.
- Do not exploit a finding beyond what is necessary to demonstrate it.

If in doubt about whether your testing falls within these guidelines, ask first.
