# SFX

Drop sound effect files here and wire them up in the Inspector.

The game currently generates its combat sounds procedurally at runtime
(see `scripts/audio/sfx.gd`), but every sound has an Inspector override
slot — set the slot and your file plays instead of the generated one:

| Where in the Inspector | Export | Default |
|---|---|---|
| Inke → AttackManager → Sound | `attack_sound` | generated whoosh |
| Inke → StateMachine → GroundSlamState | `slam_sound` | generated boom |
| Any enemy → Sound | `stomp_sound` | generated bounce |

To use a file from this folder: select the node, expand its Sound
group, and drag the audio file from `audio/sfx/` into the slot.
`volume_db` exports sit next to each slot for balancing.

Keep files organized in subfolders if it grows, e.g. `sfx/combat/`,
`sfx/ui/`, `sfx/movement/` — the slots don't care about paths.
