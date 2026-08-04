---
name: contribute-pr-en
description: English-output variant of contribute-pr. Runs the identical community PR contribution
  flow, but all user-facing output is in English. Supports /contribute-pr-en (resume/start)
  /contribute-pr-en topic <desc> (specify topic) /contribute-pr-en docs <desc> (docs-only)
  /contribute-pr-en status (read-only) /contribute-pr-en refresh (refresh local archive)
  /contribute-pr-en gate approve|revise|reject /contribute-pr-en abort (abort + clean token).
  Trigger when the user says "contribute in english" / "PR in english" / "contribute-pr english".
---

# Contribute-PR-EN — English variant of contribute-pr

This is the **English-output variant** of `contribute-pr` (community PR contribution skill).
It does NOT duplicate any logic — it delegates entirely to contribute-pr with exactly one
override: **output language = English**.

## How it works

Execute **exactly as contribute-pr** — read the base skill and follow it fully:

```
~/.zcode/skills/contribute-pr/SKILL.md              (router)
~/.zcode/skills/contribute-pr/references/*.md        (phase docs)
~/.zcode/skills/contribute-pr/scripts/*.sh           (submit, home-sync, etc.)
```

Fallback path if absent:
`$EVOLVE_HOME/skills/contribute-pr/` (i.e. `E:\opensource\hanflow-evolve\skills\contribute-pr\`).

**The single override (the ONLY thing this variant changes):**

> All user-facing output MUST be in English — topic selection, phase progress, Gate prompts,
> AskUserQuestion options, the credential-safety notice, status summaries, error reports.
> Code identifiers stay as-is.

This override supersedes the user-level `~/.zcode/AGENTS.md` default (Chinese). Everything
else — `.contribute/state.yaml`, `.contribute/lock`, the contribution archive, PR submission —
is identical to contribute-pr. No separate state file.

## Prerequisite check (do this first)

Confirm contribute-pr skill is reachable AND loop-evolve is reachable (contribute-pr delegates
its first 13 phases to loop-evolve):
```
expected paths:
  ~/.zcode/skills/contribute-pr/SKILL.md
  ~/.zcode/skills/loop-evolve/references/*.md
```
If missing, stop and tell the user:
```
ERROR: contribute-pr-en depends on contribute-pr + loop-evolve skills.
Install via: bash install.sh <github_user>
```
Do not continue — delegation will fail.

## Command reference (mirrors contribute-pr, English output)

| Command | Behavior |
|---------|----------|
| `/contribute-pr-en` | Resume current phase, or start a new contribution |
| `/contribute-pr-en topic <desc>` | Specify topic, skip selection |
| `/contribute-pr-en docs <desc>` | Docs-only contribution, jump to hanflow-home |
| `/contribute-pr-en status` | Print current state + local contribution archive |
| `/contribute-pr-en refresh` | Refresh local archive status (gh pr view) |
| `/contribute-pr-en gate approve\|revise\|reject` | Confirm at a Gate phase |
| `/contribute-pr-en abort` | Abort current contribution, clean up credentials |

State and artifacts shared with contribute-pr (same `.contribute/state.yaml`).
