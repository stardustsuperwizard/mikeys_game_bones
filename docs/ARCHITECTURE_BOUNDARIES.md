# Architecture Boundaries

**Where code goes, and why.**

Every other file in `docs/` is a dated conversation — a record of how a
decision got made. This one is not. It is a contract: the rules a change has
to satisfy, and the reasoning that makes them worth keeping. It is undated on
purpose, because it is meant to be current rather than historical.

Parts of it are enforced by `tools/check-addon-boundaries.py`. Everything else
is a judgement call that a human or an agent has to make deliberately.

---

## 1. The one rule

> **The dependency arrow points one way. Games depend on addons. Addons never
> depend on games.**

Everything below is a consequence of that sentence.

An addon that knows what your game is stops being an addon. It becomes a
fork — a copy you now maintain forever, in a folder named as if it were
vendor code, where an upgrade means a merge conflict instead of a delete and
replace.

## 2. "Will it change?" is the wrong test

The intuitive rule is *stable things go in the addon, volatile things stay in
the game*. It sounds right and it does not survive contact with this codebase.

Measured across `mikeys_game_bones`, `mikeys_game_world` and
`mikeys_game_bones-rules-moba` at the point this document was written:

| Component | Conceptual churn | What actually happened |
| --- | --- | --- |
| `Controller` | Very low — a 13-line interface, rarely revised | `mikeys_game_world` grew the vendored `player_controller.gd` from 64 to 282 lines, in place |
| Cameras | High — constantly retuned | Perfectly vendorable; drifted only because there was no package to put them in |
| `Actor` | Low | Byte-identical across two repos, untouched |

Churn predicted none of it. What predicted all of it:

> **Anything that *decides* something game-specific will drift, however small
> its interface. Anything that only holds state and delegates will not.**

`Actor` is stable because it makes no decisions — it holds a character sheet
and hands work to `ActionRunner`. `Controller` is where intent is authored,
and intent is precisely where every game differs. A 13-line interface was
never going to hold that.

So the test is not "will this change?" It is:

1. **Which way does the dependency point?**
2. **Does this file decide anything, or does it only carry?**

## 3. The evidence this document is arguing from

Two games were built on Bones. They hit the same problem — click-to-move,
turning, face-your-target — and solved it two different ways.

**`mikeys_game_bones-rules-moba` built outside `addons/`:**

- `scripts/player_controller_3d.gd` (575 lines) `extends Controller`
- `scripts/player_body_3d.gd` (21 lines) `extends ActorBody3D`
- Its vendored copy of `addons/mikeys_game_bones/controllers/` is byte-identical
  to upstream. No scene in that repo even references the vendored
  `PlayerController`.

**`mikeys_game_world` edited the vendor files in place:**

- `controller.gd`: added `get_turn_input()` and `should_auto_face_movement()`
- `player_controller.gd`: rewritten, 64 → 282 lines
- `actor_body_3d.gd`: +40 lines of facing-priority logic

Same requirement. One repo can take a Bones upgrade by deleting the folder and
unzipping a new one. The other cannot, ever, without resolving a conflict.

Note that `mikeys_game_world`'s two additions to `controller.gd` are a
genuinely good idea — AI and players need different auto-facing behavior. That
is the trap. The edit was *correct*; it was just made in the wrong place, and
so it is now stranded in one game instead of being Bones v1.1.

**The cameras are the same story with a different ending.** They existed as two
hand-maintained copies with no shared package: 216 lines in
`mikeys_game_world/cameras/`, 182 in `mikeys_game_bones-rules-moba/scripts/`.
The `mikeys_game_world` copy had grown a runtime target search the other never
received. Its header carried the note *"Re-sync manually if the source gets
improved; there's no shared package between the two repos."* That comment is a
bug report about the absence of `addons/mikeys_cameras/`.

## 4. The tiers

### Tier 1 — `addons/mikeys_game_bones/` — contracts and nouns

`Actor`, `Controller`, `Action`/`ActionRunner`/`ActionResult`, `Authority`,
`GameObject`, `ObjectDefinition`, `WorldManager`, the presentation bodies.

Minimal interfaces and the state they carry. Bones defines *what a Controller
is*; it does not define how any particular game decides.

> **If you are editing a file in here to make your game work, stop.** Either
> the contract is genuinely wrong — change it here, deliberately, and version
> it — or your code belongs in Tier 4. There is no third case, and "it's just
> a small change" is how all 282 of those lines got written.

### Tier 2 — ruleset addons — `mikeys_game_rules_*`

A complete, self-contained ruleset. Depends on Godot and Tier 1 only, never on
a game. Every global `class_name` prefixed.

`mikeys_game_bones-rules-moba/rules/` is the working model, and it is worth
studying because it proves the boundary is not about size or stability: that
module is large and under heavy active development, and it is still cleanly
liftable. What makes it liftable is `rules/tests/extraction_contract_test.gd`,
which fails the build if anything under `rules/` references `res://scripts/`,
`res://scenes/` or `res://resources/`.

The lesson is not "rules are stable." It is **"the arrow is enforced."**

### Tier 3 — kit addons — `mikeys_basic_ai`, `mikeys_basic_networking`, `mikeys_cameras`

Self-contained capabilities. Two flavors:

- **Reference implementations** (`mikeys_basic_ai`, `mikeys_basic_networking`)
  implement a Tier 1 contract and exist to prove it works end to end. Labelled
  as swappable, and meant to be swapped.
- **Independent libraries** (`mikeys_cameras`) implement no Bones contract and
  depend on nothing at all. A camera tracks a `Node3D`. It does not know what
  an `Actor` is.

Future GM tooling lands here too. `Controller`, `Authority` and `Action`
already support a GM client without any Tier 1 change — which is the sort of
thing good contracts buy you.

### Tier 4 — the game — everything outside `addons/`

Scenes, content `.tres`, binders, boot sequence, UI wiring, **and every
concrete controller.**

## 5. Controllers

**The `Controller` contract lives in the addon. Every concrete controller
lives in the game.**

Bones currently ships `player_controller.gd` at top level, framed as if it
were usable. Both games discarded it and wrote a replacement 4–9× its size.
Shipping it as a peer of the interface is what invited `mikeys_game_world` to
edit it rather than subclass it.

It should be demoted to `demo/` or labelled a reference implementation the way
`SimpleAIController` already is. That is the single change most likely to
prevent the next fork.

## 6. Cameras

Cameras are *more* vendorable than rules, not less. A camera has no rules
knowledge, no game knowledge, and no Bones knowledge — `addons/mikeys_cameras/`
imports nothing from Tier 1 and is stricter than the ruleset module on that
axis.

Its one concession is `fallback_target_group = &"players"`, the group Bones'
`PlayerController` adds. That is an `@export`ed *default*, not a dependency:
nothing imports Bones, and setting it to `&""` removes the assumption.

**Input actions are the trap here.** A library that calls
`is_action_pressed("some_action")` against a hardcoded name does not degrade
gracefully in a project that never defined it — Godot raises *"Request for
nonexistent InputMap action"* on **every input event**. So:

> **A library documents its bindings, exports their names, and never assumes
> its host's InputMap.** Export the action name, guard with
> `InputMap.has_action()`, and let an unconfigured host silently lose the
> feature instead of drowning in errors.

`check-addon-boundaries.py` warns on hardcoded action names.

## 7. Naming

Godot has no namespaces. `class_name` is **one flat registry shared with every
installed addon**, and two declarations of the same name is a hard
project-load error, not a warning.

Anything destined to ship into someone else's project gets a prefix —
`MobaAbility` in the ruleset module, `MikeyThirdPersonCamera3D` in the cameras
addon. The risk is highest for exactly the names that feel most natural:
`ThirdPersonCamera3D` is close to the single most likely name for a
third-party camera addon to claim.

Tier 1's bare names (`Actor`, `Controller`, `Door`) are grandfathered. Two
conventions in one project is an accepted, deliberate cost — do not "fix" it
in either direction.

`check-addon-boundaries.py` fails on any duplicate `class_name` across addons.

## 8. What is enforced, and what is not

Run `tools/check-addon-boundaries.py` (also the first step of
`tools/verify.sh`, before the Godot-dependent checks, so it still runs in an
environment with no Godot installed).

| Rule | Severity |
| --- | --- |
| An addon references `res://` outside `res://addons/` | **error** |
| The same `class_name` declared by two addons | **error** |
| An input action named as a string literal in an addon | warning (`--strict` to fail) |

Everything else in this document — the tier a file belongs in, whether
something "decides" or merely "carries", whether a contract change is
justified — is a judgement call. The script exists to catch the mistakes that
are mechanical. It cannot catch a bad boundary, only a broken one.

## 9. Known open violations

An honest ledger. These are true at the time of writing and are not fixed by
the existence of this document:

- **Neither consumer has migrated onto `addons/mikeys_cameras/`.**
  `mikeys_game_world/cameras/` and
  `mikeys_game_bones-rules-moba/scripts/third_person_camera_3d.gd` are still
  independent copies. Until they move, this addon is the source of truth in
  name only.
- **`mikeys_game_world` has forked Tier 1** — `controller.gd`,
  `player_controller.gd` and `actor_body_3d.gd`. The `controller.gd` additions
  deserve promotion into Bones proper; the rest belongs in Tier 4 as a
  `Controller` subclass, which is what `rules-moba` already does.
- **`Rules` means two incompatible things.** In `mikeys_game_world` it is an
  autoload with a swappable `RulesProvider` strategy. In `rules-moba` it is
  `class_name Rules extends Object` with static methods and no provider. Same
  name, same job, two shapes — and because `class_name` is one flat registry,
  they can never coexist. This needs deciding before anything gets composed.
- **`mikeys_game_world` has no `AGENTS.md`, no `CLAUDE.md`, and no CI.**
  `rules-moba` has all three. That correlates exactly with which repo drifted.
- **Bones ships `PlayerController` as a peer of `Controller`** — see §5.

## 10. Adding a new addon

1. Does it reference anything outside `addons/`? If yes, it is not an addon
   yet.
2. Does it decide something specific to one game? If yes, it belongs in Tier 4.
3. Prefix every global `class_name`.
4. Export every input action name; guard with `InputMap.has_action()`.
5. Write a README with a **Depends on** section that names every dependency, or
   says `Nothing`.
6. Run `tools/check-addon-boundaries.py`.
