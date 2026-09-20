# LINE Connect — LINE OA ↔ Salesforce (Managed 2GP, MVP)

Specification for **LINE Connect** (working name). It is a managed second-generation package that lets each sales rep
chat with their customers through their own LINE Official Account, from the Salesforce Contact page.
Claude Code does all of the implementation; its working rules are in [../CLAUDE.md](../CLAUDE.md).

## What we are building

- One LINE OA per sales rep ("Pattern 2"), many OAs per client org, one webhook endpoint per org.
- Reps chat with Contacts from Salesforce: text, images and files. Customers link themselves by scanning a QR code.
- Conversation history, notifications, reassignment when reps change, a daily Activity History summary, and retention.
- Private installs into client orgs first. Built to AppExchange security-review standards for a later listing.

## Read in this order

| File | What it gives you |
|---|---|
| [01-requirements.md](01-requirements.md) | Product context, flows F1–F9, MVP scope and acceptance criteria, non-functional requirements |
| [02-architecture.md](02-architecture.md) | Components, Apex classes, design decisions D1–D12, sequences, limits |
| [03-data-model.md](03-data-model.md) | **Agreed schema**, supporting metadata, linking rules, permission sets |
| [04-line-api-reference.md](04-line-api-reference.md) | LINE endpoints, payloads, signature check, URL scheme, items to verify |
| [05-setup-runbook.md](05-setup-runbook.md) | Our packaging setup, LINE setup per client, subscriber install and configure |
| [06-implementation-plan.md](06-implementation-plan.md) | Milestones M0–M12 with estimates and done-criteria |
| [07-testing.md](07-testing.md) | Apex/Jest cases, real-LINE end-to-end script, install/upgrade tests |
| [08-limitations-and-open-questions.md](08-limitations-and-open-questions.md) | Limitations, technical risks, open questions |
| [09-packaging.md](09-packaging.md) | Environments, project layout, commands, upgrade safety, subscriber realities, security review |
| [HANDOFF.md](HANDOFF.md) | **Current state of the build**: what's done, orgs in use, open decisions, traps. Read before continuing work. |
| [KICKOFF_PROMPT.md](KICKOFF_PROMPT.md) | First prompt for a new Claude Code session |
| `DECISIONS.md`, `SECURITY_NOTES.md` | Created in M0 and kept current during the build |

## Status

- Feasibility: confirmed.
- MVP estimate: **40–54 person-days** + 15–20% contingency (06).
- Needed before M0: Dev Hub choice (PBO recommended), namespace and package name (08 "Open questions — ours").
