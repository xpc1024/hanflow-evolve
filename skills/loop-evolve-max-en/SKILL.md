---
name: loop-evolve-max-en
description: English-output variant of loop-evolve-max (the full-blooded evolution loop with
  the domain expert team). Runs the identical loop with embedded experts, but all user-facing
  output is in English. Supports /loop-evolve-max-en (resume) /loop-evolve-max-en new (new cycle)
  /loop-evolve-max-en status (read-only) /loop-evolve-max-en gate approve|revise|reject
  /loop-evolve-max-en topic <desc> /loop-evolve-max-en abort /loop-evolve-max-en init.
  Trigger when the user says "loop evolve max english" / "max evolve in english".
---

# Loop-Evolve-Max-EN — English variant of loop-evolve-max

This is the **English-output variant** of `loop-evolve-max` (the full-blooded version with
the 9-expert team). It does NOT duplicate any logic — it delegates entirely to loop-evolve-max
with exactly one override: **output language = English**.

## How it works

Execute **exactly as loop-evolve-max** — read the base skill and follow it fully:

```
~/.zcode/skills/loop-evolve-max/SKILL.md              (router)
~/.zcode/skills/loop-evolve-max/references/*.md        (phase docs + route-experts)
~/.zcode/skills/loop-evolve-max/references/experts/*.md (9 expert prompts)
```

Fallback path if absent:
`$EVOLVE_HOME/skills/loop-evolve-max/` (i.e. `E:\opensource\hanflow-evolve\skills\loop-evolve-max\`).

**The single override (the ONLY thing this variant changes):**

> All user-facing output MUST be in English — phase progress, Gate prompts, AskUserQuestion
> options, status summaries, error reports, generated documents. Code identifiers stay as-is.
>
> **Critical for expert dispatch:** when dispatching expert subagents (per
> `references/route-experts.md` §4), append **"Respond in English"** to each dispatch prompt
> instead of the default Chinese instruction. This ensures the 9 experts (backend-architect,
> frontend-designer, etc.) also produce English output.

This override supersedes the user-level `~/.zcode/AGENTS.md` default (Chinese). Everything
else — `state-max.yaml`, scripts, phases, gates, expert routing, core-surface detection —
is identical to loop-evolve-max. No separate state file.

## Prerequisite check (do this first)

Confirm loop-evolve-max skill is reachable:
```
expected path: ~/.zcode/skills/loop-evolve-max/SKILL.md
```
If missing, stop and tell the user:
```
ERROR: loop-evolve-max-en depends on the loop-evolve-max skill.
Install via: bash install.sh <github_user> && bash install.sh --install-max
```
Do not continue — delegation will fail without loop-evolve-max.

## Command reference (mirrors loop-evolve-max, English output)

| Command | Behavior |
|---------|----------|
| `/loop-evolve-max-en` | Read state-max.yaml, resume current phase (English output) |
| `/loop-evolve-max-en new` | Force a new cycle (warns if current unfinished) |
| `/loop-evolve-max-en status` | Read-only: state-max.yaml + BACKLOG head + recent cycle |
| `/loop-evolve-max-en gate approve` | At a Gate: approve, advance |
| `/loop-evolve-max-en gate revise <feedback>` | At a Gate: roll back with feedback |
| `/loop-evolve-max-en gate reject <reason>` | At a Gate: abort the cycle |
| `/loop-evolve-max-en topic <desc>` | Preset next cycle's topic |
| `/loop-evolve-max-en abort` | Emergency stop |
| `/loop-evolve-max-en init` | First-time init (bootstrap state-max.yaml) |

State and artifacts shared with loop-evolve-max (same `state-max.yaml`, same `cycles/`).
