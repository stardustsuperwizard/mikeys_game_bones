# Mikey's Game Bones

A reusable RPG gameplay framework for Godot 4, plus a small bundled demo proving it works. Not a game — a starting point for one. Works two ways at once, in the same spirit as [Maaack's Godot Game Template](https://github.com/Maaack/Godot-Game-Template): clone the whole repo as a template to start a new project, or copy just the addon folder into an existing project's `addons/` to use it as a plugin.

## What this repo actually is

Three things living together on purpose:

- **`addons/mikeys_game_bones/`** — the framework itself. Genre-agnostic gameplay semantics: what a game object is, what an action is, how rules resolve it, who's allowed to ask.
- **`addons/mikeys_basic_ai/`, `addons/mikeys_basic_networking/`** — reference/default implementations of the extension points the framework defines (a dumb chase-and-attack AI, a bare ENet transport). Meant to be swapped, not kept.
- **`demo/`** — the framework's own minimal bundled example: a tiny lite-d20 rules engine, a player, a goblin, a door, in both 3D and 2D. Proof the pieces fit together, not a real game.

A real game built from this — with real content, real art, its own rules engine, its own release lifecycle — belongs in its *own* repo, consuming these addons rather than living inside them. `misadventures_rpg` is that repo.

## Goals

1. Provide the semantic layer between Godot's engine primitives and RPG concepts — actors, actions, rules, combat, AI, GM tooling — that Godot deliberately doesn't provide itself.
2. Make every genre-specific decision swappable, not hardcoded: which rules engine, which AI, which networking transport, whether there's a GM at all. A game built on Bones should be able to replace any one of these without touching Bones.
3. Support single-player first, multiplayer as a natural extension rather than a redesign. `Actor`/`Action`/`Rules` never need to know whether they're running locally or across a network.
4. Prefer existing Godot systems and community addons over writing new ones. Only build when nothing sufficient exists, or when the RPG semantic layer genuinely needs expressing.
5. Make new game *content* addable as data — new NPCs, items, props — without touching scripts. New game *behavior* is the one thing that should require code.
6. Use the Godot editor itself as the primary tool for building stories, not a bespoke content pipeline.

## Axioms

The load-bearing rules this project has actually held to, not aspirations:

- **Game objects represent what exists. Actions represent what is attempted. Rules determine what happens. Godot represents the result.** The full reasoning is in [`docs/20260815T130000Z - Game Objects and Rules.md`](docs/20260815T130000Z%20-%20Game%20Objects%20and%20Rules.md).
- **Bones defines contracts, not features.** `Controller`, `Action`, `Rules`, `Authority` are minimal interfaces. Bones ships at most one clearly-labeled reference/default implementation per contract (`SimpleAIController`, the ENet transport, `LiteRulesProvider` in `demo`) — never the "real," opinionated version of anything genre-specific. A serious AI, a better rules engine, a GM toolkit: all separate addons implementing the same contract.
- **Presentation is separate from gameplay semantics.** `Actor` is a plain `Node`, not a `CharacterBody3D` — it owns a swappable presentation body (`ActorBody3D`/`ActorBody2D`). Nothing above that line cares which one it has.
- **Don't build an abstraction until a second real case needs it.** Every interface in this framework exists because something concrete demanded it, not because it might someday. When in doubt, keep the concrete case simple and obvious rather than generalize early.
- **New content should be data. New behavior should require code.** If adding a goblin variant means writing a script, something's wrong.
- **Godot owns engine mechanism; Bones owns RPG mechanism.** Nodes, physics, rendering, navigation, input, networking transport — Godot's job, not reimplemented here. Actors, traits, actions, rules, authority, quests — the layer Godot doesn't have an opinion about.

## Layout

```
addons/
├── mikeys_game_bones/        GameObject, ObjectDefinition, Actor, Controller,
│                             Action/ActionRunner/Rules/Authority, WorldManager
├── mikeys_basic_ai/          SimpleAIController -- reference AI, swap it out
├── mikeys_basic_networking/  ENet transport only -- reference networking, swap it out
└── mikeys_cameras/           third-person, first-person, isometric Camera3Ds --
                              depends on nothing, not even Bones

demo/                        the framework's own bundled reference demo
├── rules/                    a tiny lite-d20 engine (RulesProvider/RulesManager)
├── data/                     example content: a player, a goblin, a door
├── scenes/                   the demo room, 3D and 2D presentations
├── runtime/                  this demo's own boot sequence
└── ui/                       this demo's own interaction prompt

docs/                        the design conversations behind this architecture --
                              read chronologically, they're the actual decision log
├── ARCHITECTURE_BOUNDARIES.md   where code goes and why -- the one doc that is
                                 a contract rather than a conversation
tools/verify.sh              headless smoke test
tools/check-addon-boundaries.py  enforces ARCHITECTURE_BOUNDARIES.md mechanically
```

`addons/` is gitignored except our own `mikeys_*` addons — third-party addons are re-downloadable and not tracked; ours aren't third-party.

## Usage

Two ways to start from this:

### As a template

Requires Godot 4.7+. Clone the whole repo and open it in Godot — `project.godot` boots straight into `demo`'s demo room. No main menu; nothing installs one here. Replace `demo/` with your own content once you've got real scenes standing up (or delete it), and keep `addons/`.

### As a plugin

Copy `addons/mikeys_game_bones/` — and whichever of `mikeys_basic_ai/` or `mikeys_basic_networking/` you actually want — into an existing project's `addons/` folder. Nothing in it assumes it owns your project's main scene, autoloads, or boot sequence.

Unlike Maaack's template, there's no `EditorPlugin`/`plugin.cfg` here and nothing to enable under **Project Settings > Plugins** — Bones defines contracts, not features (see Axioms above), so it ships as plain scripts rather than an editor plugin. "Plugin" means drop-in addon, not an Asset Library install with a setup wizard.

## Verification

`tools/verify.sh` smoke-tests the project: rescans all scripts for parse errors, then boots the project and `demo/scenes/world/demo_room_2d.tscn` headless and checks for runtime errors. Not a behavior test — it doesn't assert in-game outcomes, just that everything loads and runs. Run it after moving or renaming files, or before committing.
