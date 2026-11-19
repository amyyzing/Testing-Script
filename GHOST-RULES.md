# Ghost rule audit

Checked against all 25 `ReplicatedStorage.Modules.GhostTypes` definitions and the
in-game journal on 2026-11-17. The wiki supplies leads, not proof that an event is
unique. Some behavior is implemented outside the individual type definitions.

All 25 evidence sets are refreshed from the native client modules at startup.
Unknown enum values, missing modules, or malformed evidence retain the complete
fallback profile rather than installing a partial one. Behavior rules below
still require review when the game changes; refreshing evidence does not refresh
server-only behavior automatically.

Checks have separate directions. A necessary condition shared by other ghosts
does not provide positive support just because it holds. A qualified contradiction
can exclude it. Missing random activations stay inconclusive, and a missing or
reparented observation target cannot count as a successful negative observation.
Cross removal cancels its motion check. Holy Oil colour checks restart their
stability window after reparenting and ignore models outside Workspace.
Specter's residence is an explicit weak heuristic exception: 30 continuous
non-hunting seconds gives low support (35), and 90 gives medium (60), capped
there regardless of repetition. These grades are not identity probabilities or
native timing thresholds. One qualified departure still excludes it.

The native Mimicry challenge lets every ghost fake one random evidence type.
When its replicated flag is active, each candidate may explain one otherwise
incompatible clue. Three observations no longer use the normal exact-evidence
shortcut, and an Orb gives Doppelganger no special boost. Challenge flag changes
refresh the candidate pool and copyable-perk confidence. Qualified behavioral
negatives remain exclusions; timeout choices use the challenge-compatible pool.

| Ghost | Current source behavior | Automatic handling and limits |
| --- | --- | --- |
| Aswang | Salt slowdown, speed increase after kills | Qualified salt/kill speed windows; pre-animation baseline survives the measured delay before the death flag |
| Banshee | Breaks 1–3 glass objects, custom wail | New glass bursts provide support, not certainty |
| Demon | Spins burning crosses, increased cross range | Qualified cross motion; removing or reparenting the Cross or tracked part cancels the observation without a negative |
| Dullahan | Native Headless flag and LOS acceleration 0.1/s | The root flag is positive-only and remains medium while Doppelganger fits; cosmetic missing heads do not count. The independent three-ramp check remains available |
| Dybbuk | Throws corpses; journal describes Music Box stun | Fresh HasBeenPlayed transition plus a deep speed drop and three-second recovery; ordinary, late and interrupted responses stay inconclusive. No idle Heartbeat. Corpse motion alone is not a ghost throw |
| Entity | Teleports itself or an object, with smoke at the object's departure point | Rapid relocation plus nearby origin smoke within three seconds; corroborated short and same-room moves qualify |
| Ghoul | Native CantDisableElectronics flag; reacts to chat | The true root flag is positive-only and remains medium while Doppelganger fits. A later qualified disabling observation still excludes Ghoul. Missing/false flags, unknown player positions and automation mutation windows are inconclusive. Its three clues also fit fake-Orb Doppelganger |
| Keres | Speed drops after kills, targets lowest Energy | Paired pre-animation/post-kill speeds; native solo trace confirmed 21 to 19 before the delayed death flag. Model gender is exclusion-only |
| Leviathan | Native `LeviathanGlitch` item attribute | Direct glitch signal is strong; ordinary switch bursts are weak |
| Nightmare | False throw/shatter sounds, increased dark-room hunt chance | Evidence matching; isolated sounds/hunts cannot identify it |
| Oni | Hunt speed 14 | Known scale and two hunts required; substantial Energy separates its base 14 from Wretch |
| Phantom | Faster while invisible, blink speed 13.5 | Seven stable pairs compare invisible and visible speed; a drifting baseline stays inconclusive |
| Ravager | Multiple throws, hunting item vortex | Sustained multi-object orbit qualification passed five native-confirmed Ravager rounds; an absent vortex stays inconclusive |
| Revenant | Stops hunting after a kill, rests 15s | Qualified abrupt hunt stopping is low support (35), including solo, because settings or round ending can imitate it. The native solo Revenant stopped about 0.7 seconds after death; the normal control kept hunting throughout eight seconds. No hard exclusion from continuation |
| Shadow | Temperature-alter coefficient 0.5 | Signed net cooling per second is logged with warm-up/plateau states; uncalibrated slow cooling is weak and cannot exclude |
| Siren | Journal describes sprint slowing and humming | Native Revenant also produced 0.8x slowdown: speed-only support is weak; no slowdown remains inconclusive. Neither identifies nor excludes Siren. Model gender is exclusion-only. Exact active Spirit Box humming passed five native-confirmed Siren rounds with full evidence; hidden or absent responses remain inconclusive |
| Doppelganger | Fake Orb, teleport, extinguish lights, SpiritCandle | False-Orb evidence handling; candle ability supports both it and Spirit |
| Specter | Roam probability coefficient 0 | Timed non-hunting residence gives low-to-medium support only; one sustained known departure from an unchanged favourite room excludes. Same-room movement is permitted; unknown rooms, favourite-room changes and hunts reset the timing. Throwing frequency is omitted |
| Spirit | Blue flames and SpiritCandle ability | Qualified oil gradients; candle flag alone is shared with Doppelganger |
| Umbra | No footsteps, lit-room speed coefficient 0.8 | A root Sound named CurrentSound excludes, regardless of playback, volume or asset. Its absence after a two-second loading grace supports. Other names are ignored; late CurrentSound creation corrects absence. Automatic completion waits while Doppelganger fits confirmed evidence |
| Vesper | Hunts by sound, hears voices anywhere | Evidence matching; unqualified pursuit does not prove auditory targeting |
| Vex | Invisible on LIDAR, walks through walls | True replicated flag supports; late values are watched and absence is inconclusive |
| Wretch | Energy-dependent speed 9–14; native CantHuntNearLitCandle flag | Known scale requires meaningful Energy change; unknown scale requires three Energy levels sharing one scale. Post-kill samples are ignored. Missing hunts near candles never support it; candle exclusion awaits qualified native proximity and hunt conditions |
| Wisp | Hunt starts in favourite room, ignores oil, lights candles | Hunt location is negative-only: an outside start excludes, while repeated inside starts add no support. Read GhostWall.CanCollide only after Holy Oil is burning; default unlit walls are non-collidable for other ghosts too |
| Wraith | Energy drain coefficient 1.5; journal confirms undisturbed salt | Qualified direct salt contact; missing salt events do not identify it. Removal or reparenting cancels a pending salt observation without a verdict |

The test suite validates code contracts and representative observations. It is
not a claim that all 25 ghosts have each been tested in a live round.

Behavioral perk matches are treated as potentially copyable while Doppelganger fits the confirmed evidence. Their effective support is capped at 65 and qualifying rows are marked MEDIUM. Weak readings are not promoted. Independent evidence excluding Doppelganger releases the cap; clearing it restores the cap. High-confidence negative observations retain their existing gates.
When effective scores tie, stronger underlying observations take precedence;
this ranking does not raise the displayed confidence cap. A later native salt
disturbance corrects an earlier Wraith match and cannot be undone by another
undisturbed contact.

Post-kill speed windows retain the actual per-property change. Steps up to
0.05 also fit the measured Dullahan ramp, so those windows remain inconclusive
for Aswang and Keres even when a delayed death notification arrives nearby.
The native Aswang/Keres kill changes are larger at every offered speed scale.
A true native Headless flag also keeps the kill-speed window inconclusive:
its acceleration/reset can arrive in batches larger than the small-step gate.
The kill marker and independent Dullahan observations remain active.

In full-evidence rounds, a complete direct three-clue match wins a tie against
tentative fake-Orb support. This is a 50-point preference, not a resolved
identity: Doppelganger stays compatible, stronger behavior can override it,
and automation does not treat it as certain. The preference is disabled for
Mimicry and reduced-evidence rounds.

The current replicated `GhostTypes.Doppelganger` module directly lists room
teleporting, switching off a room light and SpiritCandle abilities, plus fake-Orb,
custom-wail and wall-walking flags. That exposed module is not an exhaustive
audit of every server consumer. It does not justify declaring other perk
matches impossible to copy, so the conservative confidence cap remains.

The ghost log shows positive, negative, explicitly MEDIUM shared-perk results,
and explicitly LOW qualified cues. Raw readings and unqualified findings stay internal.

Undisturbed-salt contact uses the native `GhostTracker` part and the ghost root,
without padding or whole-model bounds. Ground decoration and costume overlap
cannot start that test. A native disturbed-salt rename/attribute remains
authoritative even when no physical contact was observed locally.
The crossing itself must occur after creation grace; an early crossing stays
inconclusive even if the pile is still clean four seconds later.
A fresh exit and re-entry can qualify the same pile later; remaining inside
until the grace expires cannot manufacture another crossing.
Positive Wraith support additionally requires a hunting crossing. Idle-model
overlap is inconclusive; an actual disturbance still excludes Wraith immediately.
