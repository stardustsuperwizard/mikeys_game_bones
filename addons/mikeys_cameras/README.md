# Mikey's Cameras

Version **0.1.0**

Three drop-in 3D cameras for Godot 4: third-person chase, first-person, and
fixed-angle isometric. Each is a single script you attach to a `Camera3D` and
point at a target through the inspector.

| Script | Class | What it is |
| --- | --- | --- |
| `third_person_camera_3d.gd` | `MikeyThirdPersonCamera3D` | WoW-style chase camera. Right-drag to free-look, scroll to zoom, raycast keeps it out of walls. Optional `auto_realign` swings it back behind the target. |
| `first_person_camera_3d.gd` | `MikeyFirstPersonCamera3D` | Head-mounted view. Captures the mouse while active; exposes `get_look_yaw_degrees()` so a controller can steer the body toward the look direction. |
| `isometric_camera_3d.gd` | `MikeyIsometricCamera3D` | Fixed pitch/yaw strategy view. Scroll to zoom, no mouse-look. |

## Depends on

**Nothing.** Godot 4 only — no `mikeys_game_bones`, no other addon, no
third-party code. These scripts extend `Camera3D` and touch `Node3D`,
`Input`, `InputMap`, and the physics server. That is deliberate and worth
keeping: a camera that knows what an `Actor` is stops being reusable.

The one place this addon assumes anything about its host is the default value
`fallback_target_group = &"players"` on the third-person camera, which happens
to be the group `mikeys_game_bones`' `PlayerController` adds. It is an
`@export`ed default, not a dependency — nothing here imports Bones, and
setting it to `&""` removes the assumption entirely.

## Install

Copy `addons/mikeys_cameras/` into your project's `addons/`. There
is no `plugin.cfg` and nothing to enable in Project Settings — these are
library scripts, not an `EditorPlugin`. Attach one to a `Camera3D` and set
`target_path`.

## Input bindings

**No binding is required.** Every input action this addon reads is exported
and optional, and the cameras work with none of them defined.

| Export | Default action name | Used by | Effect if the action is missing |
| --- | --- | --- | --- |
| `recenter_action` | `camera_recenter` | Third-person, first-person | The camera simply never recenters. No error. |

Everything else is raw hardware input, which needs no InputMap entry at all:
right mouse button for free-look, mouse motion for look, and scroll wheel for
zoom.

To enable recentering, add an action named `camera_recenter` (Project →
Project Settings → Input Map) and bind it to whatever you like —
`mikeys_game_world` binds it to **C**. Or point `recenter_action` at an action
you already have, or set it to `&""` to disable recentering outright.

Note that *this* repository does not define `camera_recenter`, and its `demo/`
does not use these cameras yet. That is not an oversight to fix here — it is
the exact situation the guard below exists for, and the cheapest possible test
of it: attach one of these cameras to a scene in this project and it works,
minus recentering, in silence.

### Why the action is exported instead of hardcoded

`InputEvent.is_action_pressed("some_action")` on an action the project has
never defined does not quietly return `false` — Godot raises *"Request for
nonexistent InputMap action"* on **every input event**, which in practice
means an error per mouse movement. The previous version of these scripts
called `is_action_pressed("camera_recenter")` directly, so installing this
addon into a project without that action would have produced an error storm
rather than a camera missing one feature.

A library cannot assume its host's InputMap. `_is_recenter_pressed()` guards
with `InputMap.has_action()` before asking, so an unconfigured project
degrades to "recentering doesn't happen" instead of failing loudly.

## Class naming

Every global `class_name` here is prefixed `Mikey`. Godot has no namespaces:
`class_name` is one flat registry shared with every installed addon, and
`ThirdPersonCamera3D` is close to the most likely name for a third-party
camera addon to claim. Two addons declaring the same `class_name` is a hard
project-load error, not a warning.

This mirrors the `Moba` prefix rule in `mikeys_game_bones-rules-moba`, and for
the same reason. Consumers that reference these scripts by path
(`[ext_resource type="Script" path="..."]` in a `.tscn`) are unaffected by the
names.

## Boundaries

What keeps this addon reusable — the rules that make it safe to drop into any
project:

- **No outward references.** Nothing here may reference `res://scripts/`,
  `res://scenes/`, or `res://resources/`, or any path outside this folder. The
  dependency arrow points one way: games depend on this addon, never the
  reverse.
- **No game knowledge.** A camera tracks a `Node3D`. It does not know about
  actors, character sheets, combat, or rules. If a camera needs to react to
  gameplay, the game tells it — through an export or a public method — rather
  than the camera reaching out to find out.
- **No invented input actions.** Any new input goes through an exported action
  name, guarded by `InputMap.has_action()`, defaulting to something the host
  may freely ignore.
- **Never edit a consumer's copy.** This folder is the canonical source.
  Improvements land here and flow outward.

## Consumers, and the drift this addon exists to end

These scripts previously existed as two hand-maintained copies with no shared
package between them:

- `mikeys_game_bones-rules-moba/scripts/third_person_camera_3d.gd` (182 lines)
- `mikeys_game_world/cameras/third_person_camera_3d.gd` (216 lines)

They had already diverged — the `mikeys_game_world` copy grew
`fallback_target_group` and the runtime target search, which the other never
received. Its header carried the note *"Re-sync manually if the source gets
improved; there's no shared package between the two repos."* This addon is
that package; the `mikeys_game_world` copy (the superset) is what seeded it.

Both consumers still hold their own copies and have **not** been migrated yet.
Until they are, this addon is the source of truth in name only.
