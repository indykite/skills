# Pull request

<!--
Thanks for opening a PR. Please fill in the sections below — reviewers use them
to triage and to write the eventual changelog entry. Empty PRs without context
get bounced.

If anything here doesn't apply (e.g. doc-only change), say so explicitly rather
than deleting the section.
-->

## What this PR does

<!-- One sentence. Lead with the verb: "Add ...", "Fix ...", "Tighten ...".
     If you're adding or modifying a skill, name it in the form `<skill-name>`. -->

## When the skill should activate

<!-- Only required for skill add/modify PRs. Quote the `description` line from
     the skill's frontmatter and (briefly) the positive triggers and anti-triggers
     from `## When to use`. This is the part reviewers scrutinise hardest because
     it determines whether two skills end up fighting for the same prompts. -->

## Agents and models tested

<!-- Be specific. "Tested in Claude Code with Opus 4.7" beats "tested it."
     If you tested in more than one agent, list them — agent-portability is
     a quality-bar item per CONTRIBUTING.md. If you couldn't test against
     a real agent, say so and explain what was validated instead (e.g.
     `npx skills add ./<path> --list`, `bash -n` on scripts, manual dry-run). -->

- [ ] Tested in `agent` (`model`):
- [ ] Tested in `agent` (`model`):
- [ ] All checks in [`CONTRIBUTING.md` § Validating your skill](../CONTRIBUTING.md#validating-your-skill) ran clean (loader dry-run, `bash -n` on scripts, `jq empty` on JSON assets, file-hygiene)

## Known gaps or follow-ups

<!-- Anything intentionally out of scope: missing edge cases, unverified examples,
     features deferred to a follow-up PR, dependencies on infrastructure that
     isn't ready yet. Better to surface than to surprise. -->

## Checklist

- [ ] One skill (or one fix) per PR — no unrelated changes bundled in.
- [ ] PR title names the affected skill (e.g. `add my-skill`, `fix description in my-skill`).
- [ ] Skill conforms to the [Agent Skills specification](https://agentskills.io/specification) — see [`CONTRIBUTING.md` § Agent Skills specification compliance](../CONTRIBUTING.md#agent-skills-specification-compliance) for the per-field rules, optional fields used in this repo, and the relationship to the skills.sh / `skills` CLI loader.
- [ ] No secrets, internal URLs, or personal data committed.
- [ ] I have the right to contribute this content under the repo's [LICENSE](../LICENSE).
