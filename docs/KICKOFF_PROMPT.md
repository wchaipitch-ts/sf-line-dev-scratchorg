# Kickoff prompt

Paste this into a new Claude Code session opened in `/Users/chaipitchwongwangpaisarn/Documents/sf-line-dev`.
`CLAUDE.md` loads automatically and holds the rules; this prompt only starts the work.

---

We're building the LINE Connect managed 2GP package described in `docs/`.
Read `docs/README.md` and then files 01–09 in order before writing anything.
Then start M0 from `docs/06-implementation-plan.md`:
list the [HUMAN] steps I need to do for the Dev Hub and namespace, and prepare everything you can do without them.
Stop and report back before M1.

---

## Prompts for later milestones

- `Dev Hub alias is line-devhub, namespace is <ns>, package name is <name>. Continue M0.`
- `Continue with M<n> of docs/06-implementation-plan.md.`
- `M<n> [HUMAN] steps are done: <details>. Run the done-criteria check.`
- `Create the beta for M<n> and install it into sf-line-dev.`
- `Write docs/QA_RESULTS_<version>.md from the E2E run.`
