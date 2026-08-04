---
name: loop-evolve-en
description: English-output variant of loop-evolve. Runs the identical hanflow self-evolution
  loop, but all user-facing output is in English. Supports /loop-evolve-en (resume current)
  /loop-evolve-en new (force new cycle) /loop-evolve-en status (read-only)
  /loop-evolve-en gate approve|revise|reject (Gate confirm) /loop-evolve-en topic <desc>
  (preset topic) /loop-evolve-en abort (emergency stop) /loop-evolve-en init (first-time setup).
  Trigger when the user says "loop evolve english" / "evolve in english".
---

# Loop-Evolve-EN — English variant of loop-evolve

This is the **English-output variant** of `loop-evolve`. It does NOT duplicate any logic —
it delegates entirely to loop-evolve with exactly one override: **output language = English**.

## How it works

Execute **exactly as loop-evolve** — read the base skill and follow it fully:

```
~/.zcode/skills/loop-evolve/SKILL.md        (router)
~/.zcode/skills/loop-evolve/references/*.md (phase docs)
```

Fallback path if the install location is absent:
`$EVOLVE_HOME/skills/loop-evolve/SKILL.md` (i.e. `E:\opensource\hanflow-evolve\skills\loop-evolve\`).

**The single override (the ONLY thing this variant changes):**

> All user-facing output MUST be in English — phase progress reports, Gate confirmation
> prompts, AskUserQuestion option text, status summaries, error reports, and generated
> documents (direction.md, design.md, audit-*.md, test-report.md, retro.md). Code
> identifiers and existing English terms stay as-is.

This override supersedes the user-level `~/.zcode/AGENTS.md` default (which is Chinese).
Everything else — state file (`state.yaml`), scripts, phases, gates, commit conventions —
is identical to loop-evolve. No separate state file.

## Prerequisite check (do this first)

Confirm loop-evolve skill is reachable:
```
expected path: ~/.zcode/skills/loop-evolve/SKILL.md
```
If missing, stop and tell the user:
```
ERROR: loop-evolve-en depends on the loop-evolve skill.
Install via: bash install.sh <github_user>   (installs loop-evolve + contribute-pr)
```
Do not continue — delegation will fail without loop-evolve.

## Command reference (mirrors loop-evolve, English output)

| Command | Behavior |
|---------|----------|
| `/loop-evolve-en` | Read state.yaml, resume current phase (English output) |
| `/loop-evolve-en new` | Force a new cycle (warns if current is unfinished) |
| `/loop-evolve-en status` | Read-only: print state.yaml + BACKLOG head + recent cycle summary |
| `/loop-evolve-en gate approve` | At a Gate: approve, advance |
| `/loop-evolve-en gate revise <feedback>` | At a Gate: roll back with feedback |
| `/loop-evolve-en gate reject <reason>` | At a Gate: abort the cycle |
| `/loop-evolve-en topic <desc>` | Preset next cycle's topic (writes pending_human_topic) |
| `/loop-evolve-en abort` | Emergency stop the current cycle |
| `/loop-evolve-en init` | First-time initialization |

All output in English. State and artifacts are shared with loop-evolve (same `state.yaml`,
same `cycles/`).
