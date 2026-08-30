---
applyTo: "addons/**"
---

# Addons

Everything under `addons/` is meant to be copied into someone else's project
and work there. Most rules below exist to keep that true. The reasoning is in
`docs/ARCHITECTURE_BOUNDARIES.md`; this is the operational version.

## Boundaries

- **No outward references.** Nothing here may reference anything outside
  `res://addons/` — not by path, and not by name. Godot resolves global
  `class_name` declarations and autoloads by name with no path involved, so
  `Rules.attack(...)` and `var sheet: CharacterSheet` are outward references
  just as surely as `preload("res://demo/...")` is. Enforced by
  `tools/check-addon-boundaries.py`.
- **The dependency arrow points one way.** A game depends on an addon. An
  addon depends on Godot, and possibly on a sibling addon it declares. Never
  the reverse.
- **Never edit an addon to make a game work.** If the contract is genuinely
  wrong, change it deliberately and say so; otherwise the code belongs in the
  game. This is the single rule that, unheld, produced every fork this project
  has.

## Naming

- **Prefix every global `class_name`.** Godot has no namespaces: `class_name`
  is one flat registry shared with every installed addon, and two declarations
  of the same name is a hard project-load error. `MikeyThirdPersonCamera3D`,
  not `ThirdPersonCamera3D`.
- The bare names in `addons/mikeys_game_bones/` (`Actor`, `Controller`,
  `Door`) are grandfathered. **Two conventions in this repository is an
  accepted, deliberate cost.** Do not "fix" it in either direction, and do not
  rename the existing bare-named classes.

## Input

- **Never name an input action as a string literal.** Godot raises "Request for
  nonexistent InputMap action" on *every input event* for an action the host
  project has not defined, so a hardcoded name turns a missing binding into an
  error storm. Export the action name, guard it with `InputMap.has_action()`,
  and let an unconfigured host silently lose the feature.
- Raw hardware input — mouse buttons, mouse motion, scroll wheel — needs no
  InputMap entry and is fine to read directly.

## Documentation

- Every addon has a `README.md` with a **Depends on** section naming every
  dependency, or saying `Nothing`.
- Document required input actions and any assumption about the host project.

## General

- Prefer typed GDScript.
- Use Godot's built-in physics. Do not write custom collision or gravity.
- Do not add third-party dependencies.
- Reference implementations (`SimpleAIController`, the ENet transport) are
  labelled as such and meant to be swapped. Do not grow one into the
  opinionated real version of anything — that belongs in a separate addon.

## Before declaring complete

Run `tools/check-addon-boundaries.py` and `tools/verify.sh`, and report both
results. Exit 127 from `verify.sh` means Godot was not on PATH: that is "could
not validate", not "validated successfully".
