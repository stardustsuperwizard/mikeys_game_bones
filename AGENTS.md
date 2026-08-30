# Agent Instructions

Tool-agnostic. Read in full before making a change.

## Project

`mikeys_game_bones` is a reusable RPG gameplay framework for Godot 4, plus a
small bundled demo proving it works. It is not a game. The framework is
`addons/mikeys_game_bones/`; `addons/mikeys_basic_*` and `addons/mikeys_cameras`
are companion addons; `demo/` is the framework's own reference example.

Games built on this live in their own repositories and consume these addons —
`mikeys_game_world` and `mikeys_game_bones-rules-moba` are the two that exist.
Both have forked parts of this framework in the past. Preventing the next fork
is most of what the rules below are for.

## Read first

- `docs/ARCHITECTURE_BOUNDARIES.md` — where code goes and why. This is a
  contract, not a conversation, and it is the one document that overrides your
  instincts about file placement. Parts of it are enforced by
  `tools/check-addon-boundaries.py`.
- `README.md` — the axioms and the layout.
- `docs/` otherwise is a dated decision log, useful for *why* but not binding.

## Working rules

- Make the smallest change that satisfies the request.
- Inspect existing code before introducing a new abstraction. Do not build one
  until a second real case needs it.
- Do not refactor unrelated code, and do not fix pre-existing lint or test
  failures you did not cause — say they are there instead. Lint is diff-scoped
  precisely so legacy debt does not become your problem.
- Do not add third-party dependencies.
- If a request conflicts with the documented architecture, say so rather than
  silently working around it.

## Architecture

The full reasoning is in `docs/ARCHITECTURE_BOUNDARIES.md`. The short form:

- **The dependency arrow points one way.** Games depend on addons. Addons never
  depend on games.
- **Do not edit `addons/` to make a game work.** If a contract seems wrong,
  change it deliberately and say why in the PR. "It's a small change" is how
  `mikeys_game_world` grew a 282-line fork of a 64-line file.
- **Contracts and nouns go in the addon; decisions and content go in the game.**
  Anything that *decides* something game-specific will drift, however small its
  interface.
- **Prefer composition and existing extension points** over new framework
  abstractions. `Controller`, `Action`, `Authority` already support more than
  they are currently used for.
- **Godot owns engine mechanism.** Do not write custom collision, gravity, or
  navigation systems.

## Testing and validation

Before declaring anything complete, run both:

```
tools/check-addon-boundaries.py
tools/verify.sh
```

- `verify.sh` exits **127** when Godot is not on PATH. That is *"could not
  validate"*, not *"validated successfully"* — report it as such. Never claim a
  validation you did not perform.
- Report the exact commands you ran and their results.
- Existing tests and checks represent established behavior. Do not weaken,
  skip, or relax a rule to get green. If a check is wrong, argue that it is
  wrong.

### The boundary baseline

`tools/addon-boundaries-baseline.txt` lists known violations that are accepted
for now. It is a baseline, not a suppression list:

- Never add a line to it to make your change pass. A new violation is a signal
  that the change belongs somewhere else.
- Removing a violation means removing its baseline line in the same commit —
  the check fails on a stale entry, deliberately.

## Completion

1. Verify the request's acceptance criteria.
2. Run the two commands above.
3. Summarize what changed.
4. Call out assumptions, limitations, and anything you could not validate.
