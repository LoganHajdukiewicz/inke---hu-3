# INKE — EVERY MOVE (PS4 DualShock 4)

Audited against the code on 2026-11-12: every input in this file is read by
a real `is_action_*` check in `scripts/characters/Player/StateMachine/*`,
`attack_manager.gd`, `paint_manager.gd`, the NPC/door scripts, or the UI.
**All moves are doable on a DS4.**

Re-run the audit after adding moves:
`grep -rn "is_action" scripts autoloaded_scripts --include=*.gd`, then make
sure every action used there has a gamepad event in `project.godot`.

## Buttons at a glance

| DS4 | Action | Used for |
|---|---|---|
| **L-Stick** | `forward/back/left/right` | Move, climb, shimmy, steer, swing pump, menus |
| **R-Stick** | `camera_*` | Camera; switch lock-on target |
| **X** | `jump` / `ui_accept` | Jump, all jump-offs, mantle, confirm, advance dialogue, buy |
| **O** | `dash` | Dash, air dash, decline choice, leave shop, close pause |
| **□** | `attack` / `interact` | Attack, talk, open doors, board boat, open shop |
| **△** | `heavy_attack` | Spin attack, climb UP a rope, leave shop |
| **L1** | `yoyo` | Grapple / yo-yo (points and enemies); pause: previous tab |
| **R1** | `spray` | Use the selected paint power; pause: next tab |
| **R2** (hold) | `run` | Run; hustle on beams; trips you off beams |
| **L3** (click) | `crouch` | Ground slam, ledge drop, dive, rope down, swing bar drop |
| **R3** (click) | `lock_on` | Lock-on toggle |
| **D-Pad ↑ ↓ ← →** | `d_pad_*` | Select paint power (Save / Heal / Fly / Combat); shop & debug rows |
| **OPTIONS** | `start` | Pause menu |
| **SHARE** | `free_camera` | Free-roam camera for cutscene posing (dev) |
| **TOUCHPAD** | `display` | Debug overlay (dev) |
| **L2** | — | **Free** (reserved) |

## 1 · Ground

| Move | DS4 | Notes |
|---|---|---|
| Walk | L-Stick | Camera-relative |
| Run | hold **R2** + L-Stick | |
| Turn camera | R-Stick | |
| Jump | **X** | Coyote time + input buffer |
| Dash | **O** | i-frames · *Merchant upgrade* |
| Long jump | **O** then **X** within 0.3s | Dash on the ground, then jump; carries dash speed · needs Dash |
| Dash jump | **X** during a dash | Keeps dash momentum |
| Spin attack | **△** | 360° hit, keeps moving |
| Light attack (yo-yo kick) | **□** | |
| Grapple / yo-yo | **L1** | Nearest grapple point or enemy in aim |
| Lock-on | **R3** | R-Stick flicks switch targets |

## 2 · Air

| Move | DS4 | Notes |
|---|---|---|
| Double jump | **X** in the air | *Merchant upgrade* |
| Air dash | **O** in the air | Once per jump · needs Dash |
| Ground slam | **L3** in the air | Hang beat, rocket down, AOE, breaks crates, ground-pound mounds · *Shockwave upgrade* = bigger/stronger |
| Stomp | land on an enemy's head | Automatic |
| Grapple from air | **L1** | |
| Wall slide | push into a wall while falling | Automatic |
| Wall jump | **X** while wall-sliding | Chain between opposite walls · *Merchant upgrade* |

## 3 · Ledges & climbing

| Move | DS4 | Notes |
|---|---|---|
| Ledge grab | fall/jump into a ledge lip | Automatic |
| Shimmy | L-Stick ← → while hanging | Wraps corners |
| Climb up | **X** or L-Stick ↑ | |
| Drop | **L3** or L-Stick ↓ | |
| Climb wall / fence | walk or jump into it | Automatic grab; L-Stick climbs |
| Wall hop | **X** on a climb wall | Burst in stick direction (up if neutral) · *Climb Kit* = faster |
| Let go of climb wall | L-Stick ↓ + **X**, or **L3** | |
| Ladder | walk into it, L-Stick ↑ ↓ | **X** leaps off |

## 4 · Swings, rails, ropes

| Move | DS4 | Notes |
|---|---|---|
| Rail grind | land on a rail | Automatic; **X** jumps off; **L1** grapples off |
| Swing bar | jump into it | Auto pump; L-Stick ↑ ↓ pumps/brakes; **X** launches; **L3** drops |
| Rope swing | jump into it | L-Stick pumps; **△** climbs up; **L3** climbs down / lets go; **X** launches |
| Grapple swing | **L1** on a swing point | **X** releases with momentum |
| Grapple an enemy | **L1** at an enemy | Pull in + hit, pops you up over it |

## 5 · Surfaces

| Move | DS4 | Notes |
|---|---|---|
| Slide | on slide floors/steep slopes | Automatic; steer L-Stick; **X** jumps off; **O** dashes out (never uphill) |
| Balance beam | walk onto it | Slow walk; **R2** hustles (and can trip you); **X** jumps off |
| Ice | walk onto it | Slippery momentum |
| Swim | enter water | L-Stick swims; **X** hops out onto banks/docks |
| Dive | hold **L3** at the surface | **X** rises, **L3** sinks; oxygen meter |

## 6 · Paint powers

| Move | DS4 | Notes |
|---|---|---|
| Pick Save paint | **D-Pad ↑** | |
| Pick Heal paint | **D-Pad ↓** | |
| Pick Fly paint | **D-Pad ←** | *Not implemented yet (code TODO)* |
| Pick Combat paint | **D-Pad →** | *Not implemented yet (code TODO)* |
| Use paint | **R1** | Save = checkpoint (stand still on ground). Heal = restore health. No spraying in water |

## 7 · World & menus

| Move | DS4 | Notes |
|---|---|---|
| Talk / interact | **□** | NPCs, quest givers, doors, boat, merchant |
| Read a sign | **X** | |
| Advance dialogue | **X** | Press while typing to finish the line |
| Dialogue choice | **X** yes / **O** no | |
| Shop browse | D-Pad / L-Stick | **X** buy · **O** or **△** leave |
| Pause | **OPTIONS** | **O** also closes it; **L1 / R1** switch tabs (Stats / Controls / Saves) |
| Rebind | Pause → CONTROLS | Saved per device |

## Merchant upgrades that change moves
Double Jump · Wall Jump · Dash (enables air dash and long jump) · Speed ·
Climb Kit (faster climbing/hops) · Shockwave (stronger slam) · plus
Health / Damage / Gear Magnet / Paint Tank (stats, no new buttons).

## Gaps / notes found in the audit
- **L2 is free** by design.
- **Fly** and **Combat** paint can be selected but do nothing yet.
- R3 only does lock-on (no crouch duplicate).
- Keyboard-only: `quit_game` (hold F1 for 1s). No pad binding, on purpose.
