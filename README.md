# Testing Script

A modular Demonology evidence and behavior assistant written in Luau. The original single-file script is split into independently loaded UI, presentation, catalog, and runtime modules.

## Run

```luau
loadstring(game:HttpGet("https://raw.githubusercontent.com/amyyzing/Testing-Script/main/logic.luau"))()
```

When run in the lobby, the loader opens a settings window for Job Site,
difficulty, saved Custom preset, saved equipment preset, three independent daily
challenge toggles, and Auto. When executor file APIs are available, the
selections are stored in `DemonologyAssistant/Settings.json`, following the same
folder-plus-JSON pattern used by Cobalt. They are also retained in
`getgenv().DemonologyLobbySettings` and serialized into the queued teleport
loader, so executors without file APIs still work and `local Auto = true` is no
longer needed. Passing a boolean argument is
still supported as a one-time override. With Auto enabled, the loader queues a
guarded self-loader through
`queue_on_teleport`/`queueonteleport` whenever `AttemptStart` or
`RequestReturnToLobby` initiates a teleport. A round arrival loads the GUI and
turns on Do-Round automatically after the character, map, ghost, doors, and door
remote have stayed replicated for one second. A lobby return fires
`LoadingFinished`, reapplies the remembered lobby settings, and starts the next
round automatically.

The script requires an environment that provides `game:HttpGet` and `loadstring`. Some optional features also capability-check executor APIs such as `gethui`, `firesignal`, `getconnections`, and `fireproximityprompt`. It is not a normal Roblox Studio `LocalScript`.

The bootstrap installs one session-scoped `LocalPlayer.Idled` hook that uses
`VirtualUser` to prevent the normal idle disconnect. Re-executing or destroying
the session disconnects the old hook before a replacement is installed.

Remote code is fetched at run time. Review the repository before executing it, and follow the game/platform rules that apply to your account.

Before fetching GUI modules, the bootstrap performs a discardable one-shot check
for the `Workspace.Ghost` model. When it exists, the normal in-round GUI loads.
When it does not exist, only the lobby settings GUI loads. Starting applies the
selected Job Site only when it differs from the live location frame carrying the
`Selected` attribute, preventing `ChangeJobSite` from toggling an already-selected
site back off. It reads the live difficulty label, chooses the shortest Plus or
Minus route, and requires the real server `UpdateDifficulty` response after each
`ChangeDifficulty` step until Easy/Medium/Hard/Nightmare/Custom matches. Once the
server state is confirmed, it synchronizes the client difficulty page. When
Custom is selected, it waits for the saved preset list to populate, applies the
named preset once, and requires a populated `UpdateAllCustomDifficultySettings`
payload before continuing. Difficulty preset names come from
`ComputerScreen.JobSite.DifficultySettings.PresetList`; equipment preset names
come from `ComputerScreen.Equipment.PartyLog.PresetList`. Both lists include only
Frame entries containing a `Delete` descendant. The selected equipment preset
is applied, then Challenge 1-3 are compared with their live ON/OFF labels and
`ToggleChallenge` is fired only for mismatches. Player status is then applied
before attempting to start the round: `ChangeStatus` fires only when
`LocalPlayer:GetAttribute("IsReady")` is explicitly false, so an already-ready
player cannot be toggled back to unready. Every macro dispatch has its own
0.75-second safety delay. The first run adopts the live challenge states when no
challenge preference has been saved, preventing an untouched default from
inverting an existing selection. During an automatic start, switching Auto off
or manually changing the player's ready state cancels the remaining macro
dispatches; the macro's own expected `ChangeStatus` transition is not treated as
a cancellation.

## Layout

```text
logic.luau                 Remote bootstrap and module loading lifecycle
gui/load-screen.luau       Loading progress and failure UI
gui/lobby-settings.luau    Lobby-only persisted map, difficulty, preset, and Auto controls
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

Door placeables prefer the nearest distinct non-exit door names, then fall back to
different physical door instances when a map gives multiple doors the same name.
Each door is closed and allowed to settle before its `DoorUnion` wide face is
recalculated. The player is held no more than two studs in front of that face,
looking toward its centre, while a temporary Scriptable camera lock lets the
camera and placement preview settle; the original camera mode is restored after
each attempt. Before the salt door approach is
chosen, the live player-to-`Camera.SaltLine.Salt` XZ distance is sampled and used
to place the salt preview on the door's XZ centre. Salt continues across unique
doors until `Uses` reaches zero; Holy Oil dispatches up to three times at distinct
doors. Both placement previews must remain within two studs of the player, touch
valid room bounds, and pass floor and clearance checks before the remote is fired.
Each newly spawned salt pile is quarantined for four seconds. Disturbance is still
observed during that window, but an initial overlap cannot become Wraith or Aswang
contact evidence unless the ghost clears the mature pile and touches it again.

Turning `Do Round` off immediately releases any door-facing render lock and
restores a live character's unanchored, rotating humanoid state. Cancellation-aware
teleports also restore movement instead of preserving a transient automation lock.

The round opener resolves the canonical `Workspace.Doors.ExitDoor` container
directly, reads its `DoorClosed` attribute as the authoritative open/closed state,
and teleports within the ten-stud interaction range before firing the door remote.
If the strict two-stud door-face position is obstructed, it falls back to the safe
grounded ripple search around the exit door.

Base Camp returns evaluate every Base Camp bound and prefer the safest result
closest to an identified Exit Door; if no exit can be identified, the Truck is the
distance reference.

The rest of the d906 flow remains recognizable: prepare configured room items,
open an exit, ask Spirit Box questions from the favourite room, escape active
hunts, and maintain displaced or stably-disabled equipment. A Pretty Sure/Certain
single-ghost identification is selected immediately regardless of hunt state. If
it arrives during setup, the room-item worker, door work, and remaining pre-round
steps are cancelled before automation moves directly to the end path. Automation
teleports to and verifies Base Camp, then fires `RequestReturnToLobby` without
waiting for the hunt to end. Otherwise, after three minutes the timer
watchdog cancels any unfinished setup or maintenance work, selects a
highest-confidence ghost, performs the same verified Base Camp return, and keeps
firing `RequestReturnToLobby` once every four seconds until `LocalPlayer.OnTeleport`
confirms the lobby teleport has begun. Neither completion path waits for a hunt
to end. A final low-confidence timeout choice is locked while returning, so normal
tracker refreshes cannot flicker the label between that choice and its earlier
multi-ghost `Idk` candidate list.

Modules are plain remote chunks: each returns a table or factory, and the bootstrap injects dependencies explicitly. The ghost catalog never deletes its source records; candidate lists are derived so a reset or evidence-mode change can restore ruled-out ghosts.

The bootstrap prefetches every runtime source with a ten-worker queue, gives each
HTTP attempt an eight-second timeout, retries each source up to three times, and
caches both source and executed modules for the run. The loading screen reports
module-level progress before the package is assembled, so one stalled request no
longer requires manually executing the loader again.

## Ghost observation lifecycle

The ghost model is fixed for the lifetime of a round. A new round destroys the
coordinator and its Roblox signal connections, clears the ledger, and constructs a
fresh coordinator; there is no `GhostGeneration` polling tracker.

- Active trackers translate hunt-state and explicit game signals into normalized events.
- Dormant trackers wake for settled hunt transitions, transparency changes, salt contact, qualified player deaths, or the shared quarter-second tick. Speed is captured as event-driven visible/invisible pairs and targeted probes, not a continuous 0.1-second stream. The room-temperature tracker uses that existing tick to collect 20 unrounded readings only after the ghost remains in the same `CurrentRoom` for five seconds. Only strictly decreasing pairs enter the cooling average; increases, unchanged pairs, and temperatures from other rooms are excluded. An exact average below 0.05°C identifies Shadow; an average above 0.06°C rules it out only when no cooling sample is below 0.05°C. The 0.05–0.06°C band is inconclusive.
- Discardable trackers read immutable model facts once, emit qualified observations such as model gender, LIDAR state, and the immediate Umbra root-sound check, then stop. Model gender is the only gender observation; Spirit Box voice folders do not add a duplicate male/female score.

Shared analyzers classify one complete window of seven settled visible/invisible
pairs. Seven repeating phase pairs classify Phantom, seven flat pairs feed
Normal/Oni speed math, and seven differing pairs with an upward step inside every
pair classify Dullahan; resets or decreases between pairs are ignored. A complete
non-Dullahan window rules Dullahan out immediately instead of waiting for the hunt
to end. The same flat-pair result compares Normal, Oni, and the Wendigo speed
expected from average Energy captured at the hunt-state switch. Three alternating
transitions can corroborate Wendigo after two Energy points of change, while a
mathematically impossible curve is a qualified rule-out regardless of that spread.
Hunting speed math uses the Small/Medium/Large map factors. Per-ghost files
own conclusions and supersession rules; `logic/logic.luau` only collects game state
and emits the qualified observations while the coordinator is active. The ledger
retains both positive and negative history, but ranking uses only effective,
non-superseded entries.

## Ghost data

The catalog contains the current 25-ghost roster, normalized evidence names, perk notes grouped into `Pretty Sure`, `Maybe`, and `Idk`, and source/status metadata for disputed, stub, or recently added pages. Filtering uses stable internal keys for compatibility with the runtime (`GhostWriting` and `Handprints`) while the interface displays the current names (`Inscription` and `Prints`).

Primary references:

- [Ghost types](https://demonology.fandom.com/wiki/Ghosts/Types)
- [Evidence](https://demonology.fandom.com/wiki/Evidence)
- [Game guide](https://demonology.fandom.com/wiki/Guide)
- [Skinwalker caveats](https://demonology.fandom.com/wiki/Skinwalker)

Wiki behavior can change with game updates. Confidence buckets are inference aids, not guaranteed identifications; exact evidence matches remain the strongest result.
