# Testing Script

A modular Demonology evidence and behavior assistant written in Luau. The original single-file script is split into independently loaded UI, control, automation, and per-ghost observation modules.

## Run

```luau
loadstring(game:HttpGet("https://raw.githubusercontent.com/amyyzing/Testing-Script/main/logic.luau"))()
```

The script requires an environment that provides `game:HttpGet` and `loadstring`. Some optional features also capability-check executor APIs such as `gethui`, `firesignal`, `getconnections`, and `fireproximityprompt`. It is not a normal Roblox Studio `LocalScript`.

Remote code is fetched at run time. Review the repository before executing it, and follow the game/platform rules that apply to your account.

## Layout

```text
logic.luau                 Remote bootstrap and module loading lifecycle
gui/load-screen.luau       Loading progress and failure UI
gui/aesthetic.luau         Theme, reusable copy, and GUI construction
gui/gui-logic.luau         Buttons, dropdown, drag/resize, hotkey, and rendering
ghost/init.luau             Remote-safe manifest and ghost package assembly
ghost/engine.luau           Evidence normalization, catalog filtering, and ranking
ghost/runtime.luau          Ordered observer lifecycle and event dispatch
ghost/collector.luau        Raw observation feeds, hunt buffers, and lifecycle state
ghost/tracker.luau          Detection, rule-out, confidence, TTL, and persistence state
ghost/session.luau          Candidates, confidence ties, evidence guesses, and final choice
ghost/<Name>.luau           One ghost profile and its observation policy
ghost/tests/*.spec.luau     Package, observer, lifecycle, and policy regressions
logic/logic.luau            GUI feature controls, Roblox world adapters, actions, and cleanup
logic/round-automation.luau Hunt-safe Do-Round sequencing, door placement, and item recovery
```

`Do Round` prepares the seven configured room items, retains Salt Canister and
Holy Oil for unique non-exit door placements, opens an exit, asks Spirit Box
questions from the favourite room, escapes hunts, and maintains displaced or
stably-disabled equipment. Its visible timer ends on a stable Pretty Sure/Certain
identification or selects the highest-confidence remaining guess after three minutes.

Modules are plain remote chunks: each returns a table or factory, and the bootstrap injects dependencies explicitly. `ghost/init.luau` loads the singular ghost package in manifest order, builds the catalog, and exposes the observer runtime without relying on repository-relative `require` calls in the executor.

## Ghost data

The `ghost` directory contains one source definition for each of the current 25 ghosts. Every definition owns its evidence, confidence metadata, aliases, perk notes grouped into `Pretty Sure`, `Maybe`, and `Idk`, and named observation keys. Ghosts with observable automatic patterns also own a `CreateObserver` policy for their positive findings, reversible clues, and rule-outs; Nightmare, Shadow, and Vesper currently remain metadata-only.

Roblox-facing adapters send raw facts into `ghost/collector.luau`. The collector owns hunt and transparency sample buffers, `ghost/runtime.luau` dispatches those observations, and each named ghost module owns its pattern interpretation, positive observations, reversible clues, and rule-outs. `ghost/session.luau` is the single source of truth for remaining candidates, confidence ranking, Mimicry/Skinwalker handling, and final selection. `ghost/engine.luau` derives candidates instead of deleting source profiles, so resets and evidence-mode changes can restore compatible ghosts. Filtering retains the stable internal keys `GhostWriting` and `Handprints`, while the interface displays the current names `Inscription` and `Prints`.

Primary references:

- [Ghost types](https://demonology.fandom.com/wiki/Ghosts/Types)
- [Evidence](https://demonology.fandom.com/wiki/Evidence)
- [Game guide](https://demonology.fandom.com/wiki/Guide)
- [Skinwalker caveats](https://demonology.fandom.com/wiki/Skinwalker)

Wiki behavior can change with game updates. Confidence buckets are inference aids, not guaranteed identifications; exact evidence matches remain the strongest result.
