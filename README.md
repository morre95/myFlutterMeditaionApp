# My Meditation App

A Flutter meditation app: meditation timer with custom bells, music playlists,
session history & streaks, favorites, and optional pCloud audio streaming.

## Connecting to pCloud

pCloud is optional — the app works fully without it. Because pCloud's direct
API cannot complete two-factor authentication and pCloud has disabled new OAuth
app registration, the app connects using a **pasted access token**.

1. **Get a token with [rclone](https://rclone.org/downloads/)** (it runs the
   pCloud sign-in, including 2FA, in your browser):

   ```bash
   rclone authorize "pcloud"
   ```

   Sign in in the browser it opens, then copy the **`access_token`** value from
   the JSON it prints:

   ```json
   {"access_token":"XXXXXXXX","token_type":"bearer", ...}
   ```

2. **In the app:** go to **Settings → pCloud → Connect** (or **Library →
   pCloud**), paste the token, and choose your **data region**:
   - **United States** → `api.pcloud.com`
   - **Europe** → `eapi.pcloud.com`

   The app validates the token immediately. Once connected, browse and add
   pCloud audio from **Library → pCloud**; tracks stream on demand. Disconnect
   from **Settings** clears the stored token.

pCloud access tokens don't expire unless revoked, so this is a one-time setup.
More detail: [docs/pcloud_setup.md](docs/pcloud_setup.md).

---

# Cursor Playbook

A production-ready `.cursor/` directory template that enforces professional software engineering standards in any project using [Cursor](https://cursor.com).

Drop it into a new repo and start building with guardrails from day one.

> If you find this useful, a star helps others discover it too.

---

## Why This Exists

Cursor is powerful, but without guardrails it will:
- Introduce bandaid fixes instead of addressing root causes
- Build components in isolation that drift from the rest of the system
- Leave dead code, duplicate models, and inconsistent patterns behind
- Produce N+1 queries, silent error swallowing, and hardcoded secrets

This template prevents that. It provides **rules** (loaded every session), **skills** (reusable workflows), and **hooks** (automated checks) — all configured and ready to use.

---

## What's Included

```
.cursor/
├── hooks.json                         # Hook registry
│
├── rules/                             # Loaded automatically every session
│   ├── project-instructions.mdc       # Project commands, style, platform, architecture
│   ├── agent-behavior.mdc             # Communication, verification, self-review
│   ├── code-quality.mdc               # No dead code, no bandaids, root-cause fixes
│   ├── engineering-principles.mdc     # DRY, YAGNI, KISS, SRP, code smells, naming
│   ├── architecture.mdc               # Separation of concerns, dependency direction
│   ├── api-design.mdc                 # REST conventions, response format, pagination
│   ├── error-handling.mdc             # Structured errors, custom exceptions, fail fast
│   ├── security.mdc                   # OWASP, secrets, auth, input validation
│   ├── database.mdc                   # Schema design, constraints, query patterns
│   ├── alembic.mdc                    # Migration best practices (Python/SQLAlchemy)
│   ├── frontend.mdc                   # Components, state management, TypeScript
│   ├── frontend-consistency.mdc       # Reuse before create, no visual drift
│   ├── testing.mdc                    # Test types, structure, reliability
│   ├── performance.mdc                # Query optimization, caching, async patterns
│   ├── git-workflow.mdc               # Commits, branches, PR standards
│   ├── llm-prompts.mdc               # Jinja2 templates for prompt management
│   ├── python-standards.mdc           # Python-specific (only loads for .py files)
│   └── common-mistakes.mdc           # Project-specific pitfalls (you populate this)
│
├── skills/                            # On-demand workflows invoked by the agent
│   ├── review/SKILL.md               # Pre-commit code review against all rules
│   ├── fix-issue/SKILL.md            # End-to-end GitHub issue resolution
│   ├── review-pr/SKILL.md            # Structured PR review
│   └── security-reviewer/SKILL.md    # Delegated security audit via subagent
│
└── hooks/                             # Automated scripts on agent events
    └── lint-on-edit.sh               # Auto-lint after every file edit

agent-docs/                            # Session memory — agent notes that persist across chats
└── README.md                          # Explains the pattern
```

---

## Getting Started

After applying this template:

1. Edit `.cursor/rules/project-instructions.mdc` — replace the template commands with your actual build/test/lint commands
2. Remove rules that don't apply (no database? delete `database.mdc` and `alembic.mdc`)
3. Add project-specific details to the rules you keep
4. Start building — Cursor picks up the rules automatically

---

## License

[MIT](LICENSE) — use, modify, and distribute freely.
