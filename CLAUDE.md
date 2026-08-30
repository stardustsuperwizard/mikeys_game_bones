# CLAUDE.md

This file exists so Claude Code reads the same contract every other tool does.
There is one source of truth; this is a pointer to it, not a copy.

## Read first

- `AGENTS.md` — project context, working rules, architecture constraints,
  validation and completion requirements. Tool-agnostic; read it in full before
  any change.
- `docs/ARCHITECTURE_BOUNDARIES.md` — where code goes and why. `AGENTS.md`
  defers to it for the details.

## Path-scoped instructions

Copilot picks these up automatically via `applyTo:` frontmatter; Claude Code
does not, so check manually before editing:

| Directory | Also read |
| --- | --- |
| `addons/**` | `.github/instructions/addons.instructions.md` |

## Before declaring anything complete

```
tools/check-addon-boundaries.py
tools/verify.sh
```

`verify.sh` exiting 127 means Godot was not on PATH — that is "could not
validate", not "validated successfully". Say which of the two happened.

## No Issue pipeline here

Unlike `mikeys_game_bones-rules-moba`, this repository has no planner /
executor / reviewer workflow and no `agent:review` gate. There is no Issue to
close and no label to add. A PR here needs a clear description of what changed
and why, and honest reporting of what was and was not validated.
