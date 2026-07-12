# Testing Script

A modular Demonology evidence and behavior assistant written in Luau. The original single-file script is split into independently loaded UI, presentation, catalog, and runtime modules.

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
logic/logic.luau           Evidence scans, trackers, feature actions, and cleanup
logic/ghost-module.luau    Ghost catalog, confidence notes, filtering, and ranking
```

Modules are plain remote chunks: each returns a table or factory, and the bootstrap injects dependencies explicitly. The ghost catalog never deletes its source records; candidate lists are derived so a reset or evidence-mode change can restore ruled-out ghosts.

## Ghost data

The catalog contains the current 25-ghost roster, normalized evidence names, perk notes grouped into `Pretty Sure`, `Maybe`, and `Idk`, and source/status metadata for disputed, stub, or recently added pages. Filtering uses stable internal keys for compatibility with the runtime (`GhostWriting` and `Handprints`) while the interface displays the current names (`Inscription` and `Prints`).

Primary references:

- [Ghost types](https://demonology.fandom.com/wiki/Ghosts/Types)
- [Evidence](https://demonology.fandom.com/wiki/Evidence)
- [Game guide](https://demonology.fandom.com/wiki/Guide)
- [Skinwalker caveats](https://demonology.fandom.com/wiki/Skinwalker)

Wiki behavior can change with game updates. Confidence buckets are inference aids, not guaranteed identifications; exact evidence matches remain the strongest result.
