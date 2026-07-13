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
logic/logic.luau           UI/action logic and Roblox signal-to-observation adapters
logic/round-automation.luau Hunt-safe Do-Round sequencing, door placement, and item recovery
logic/ghost-module.luau    Ghost catalog, confidence notes, filtering, and ranking
ghost/*.luau               One observation policy module per ghost
ghost/coordinator.luau     Event routing, lifecycle, and observer coordination
ghost/evidence-ledger.luau Append-only positives, negatives, rule-outs, and supersession
ghost/trackers/             Active, dormant, and discardable broad trackers
ghost/analyzers/            Shared speed-pair pattern and map-speed math
```

`Do Round` keeps the sequencing from automation revision
`d906b7e1337944d5f67ab7d4e4727f0091894367`, with stricter geometry and
confirmation around its existing operations. Room-item checks accept overlap with
any favourite-room bounding box and use the root `Workspace.Items` model's
`ItemName`; inventory confirmation uses `LocalPlayer.ToolsHolder`. Pickups are made
from at most eight studs away.

Door placeables use the nearest distinct non-exit door names. Each door is closed
and allowed to settle before its `DoorUnion` wide face is recalculated. The player
is held two studs in front of that face, looking toward its centre, while
the camera and placement preview settle. Salt continues across unique doors until
`Uses` reaches zero; Holy Oil dispatches once at a different door. Both placement
previews must remain within two studs of the player, touch valid room bounds, and
pass floor and clearance checks before the remote is fired.

Base Camp returns evaluate every Base Camp bound and prefer the safest result
closest to an identified Exit Door; if no exit can be identified, the Truck is the
distance reference.

The rest of the d906 flow remains recognizable: prepare configured room items,
open an exit, ask Spirit Box questions from the favourite room, escape active
hunts, and maintain displaced or stably-disabled equipment. The timer ends on a
stable Pretty Sure/Certain identification or chooses among the highest-confidence
remaining ghosts after three minutes.

Modules are plain remote chunks: each returns a table or factory, and the bootstrap injects dependencies explicitly. The ghost catalog never deletes its source records; candidate lists are derived so a reset or evidence-mode change can restore ruled-out ghosts.

The bootstrap fetches ghost-package sources with a six-worker queue, retries each
source up to three times, and caches both source and executed modules for the run.
The loading screen reports module-level progress before the package is assembled,
so the per-ghost layout does not become a long serial request chain.

## Ghost observation lifecycle

The ghost model is fixed for the lifetime of a round. A new round destroys the
coordinator and its Roblox signal connections, clears the ledger, and constructs a
fresh coordinator; there is no `GhostGeneration` polling tracker.

- Active trackers translate hunt-state and explicit game signals into normalized events.
- Dormant trackers wake for settled hunt transitions, transparency changes, salt contact, or qualified player deaths. Speed is captured as event-driven visible/invisible pairs and targeted probes, not a continuous 0.1-second stream.
- Discardable trackers read immutable model facts once, emit qualified observations such as model sex, LIDAR state, and the immediate Umbra root-sound check, then stop.

Shared analyzers classify Phantom/Dullahan pair patterns and normalize hunting
speed using the Small/Medium/Large map factors. Per-ghost files own conclusions and
supersession rules; `logic/logic.luau` only collects game state and emits the
qualified observations while the coordinator is active. The ledger retains both
positive and negative history, but ranking uses only effective, non-superseded
entries.

## Ghost data

The catalog contains the current 25-ghost roster, normalized evidence names, perk notes grouped into `Pretty Sure`, `Maybe`, and `Idk`, and source/status metadata for disputed, stub, or recently added pages. Filtering uses stable internal keys for compatibility with the runtime (`GhostWriting` and `Handprints`) while the interface displays the current names (`Inscription` and `Prints`).

Primary references:

- [Ghost types](https://demonology.fandom.com/wiki/Ghosts/Types)
- [Evidence](https://demonology.fandom.com/wiki/Evidence)
- [Game guide](https://demonology.fandom.com/wiki/Guide)
- [Skinwalker caveats](https://demonology.fandom.com/wiki/Skinwalker)

Wiki behavior can change with game updates. Confidence buckets are inference aids, not guaranteed identifications; exact evidence matches remain the strongest result.
