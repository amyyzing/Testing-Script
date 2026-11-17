# Ghost rule audit

Checked against all 25 `ReplicatedStorage.Modules.GhostTypes` definitions and the
in-game journal on 2026-11-17. The wiki supplies leads, not proof that an event is
unique. Some behavior is implemented outside the individual type definitions.

All 25 evidence sets are refreshed from the native client modules at startup.
Unknown enum values, missing modules, or malformed evidence retain the complete
fallback profile rather than installing a partial one. Behavior rules below
still require review when the game changes; refreshing evidence does not refresh
server-only behavior automatically.

| Ghost | Current source behavior | Automatic handling and limits |
| --- | --- | --- |
| Aswang | Salt slowdown, speed increase after kills | Qualified salt/kill speed windows |
| Banshee | Breaks 1–3 glass objects, custom wail | New glass bursts provide support, not certainty |
| Demon | Spins burning crosses, increased cross range | Qualified cross motion |
| Dullahan | Headless in photos, LOS acceleration of 0.1/s | Repeated rising speed supports; flat uncontrolled trials cannot exclude |
| Dybbuk | Throws corpses; journal describes Music Box stun | Evidence matching; physics motion alone is not accepted as a ghost throw |
| Entity | Teleports itself or an object, with smoke on object teleport | Qualified object relocation plus smoke |
| Ghoul | Cannot disable electronics; reacts to chat | Qualifies disabling observations away from living players |
| Keres | Speed drops after kills, targets lowest Energy | Kill speed windows; unknown models do not default to male |
| Leviathan | Native `LeviathanGlitch` item attribute | Direct glitch signal is strong; ordinary switch bursts are weak |
| Nightmare | False throw/shatter sounds, increased dark-room hunt chance | Evidence matching; isolated sounds/hunts cannot identify it |
| Oni | Hunt speed 14 | Known scale and two hunts required; substantial Energy separates its base 14 from Wretch |
| Phantom | Faster while invisible, blink speed 13.5 | Seven stable pairs must have invisible speed greater than visible speed |
| Ravager | Multiple throws, hunting item vortex | Sustained multi-object orbit qualification |
| Revenant | Stops hunting after a kill, rests 15s | Qualified multiplayer kill/hunt transitions |
| Shadow | Temperature-alter coefficient 0.5 | Signed net cooling per second is logged with warm-up/plateau states; uncalibrated slow cooling is weak and cannot exclude |
| Siren | Slows players in LOS; journal describes humming | Qualified LOS player-speed trials and Spirit Box humming |
| Doppelganger | Fake Orb, teleport, extinguish lights, SpiritCandle | False-Orb evidence handling; candle ability supports both it and Spirit |
| Specter | Roam probability coefficient 0 | Trials discard changes to favourite room |
| Spirit | Blue flames and SpiritCandle ability | Qualified oil gradients; candle flag alone is shared with Doppelganger |
| Umbra | No footsteps, lit-room speed coefficient 0.8 | Three playing native footstep-asset samples exclude; silence gives no support |
| Vesper | Hunts by sound, hears voices anywhere | Evidence matching; unqualified pursuit does not prove auditory targeting |
| Vex | Invisible on LIDAR, walks through walls | True replicated flag supports; late values are watched and absence is inconclusive |
| Wretch | Energy-dependent speed 9–14, avoids hunts near lit candles | Known scale requires meaningful Energy change; unknown scale requires three Energy levels sharing one scale |
| Wisp | Hunt starts in favourite room, ignores oil, lights candles | Qualified favourite-room and burning-oil passage observations |
| Wraith | Energy drain coefficient 1.5; journal confirms undisturbed salt | Qualified direct salt contact; missing salt events do not identify it |

The test suite validates code contracts and representative observations. It is
not a claim that all 25 ghosts have each been tested in a live round.

Pattern logs display RULED OUT without a percentage. Other scores are internal rule strengths, not measured probabilities. Speed channels show raw observations and waiting conditions even when no verdict is ready.
