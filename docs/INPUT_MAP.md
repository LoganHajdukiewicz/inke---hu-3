# INKE & HU-3 — INPUT MAP (DualShock 4)

**The complete catalog of everything Inke can do**, with the current binding on a
PS4 DualShock controller. Actions are grouped by context. Where a context reuses
a button, that's intentional — the game is stateful, so `X` can mean *jump*,
*hop up the wall*, or *buy the upgrade* depending on where you are.

Rebinding: **Pause (OPTIONS) → CONTROLS**. Keyboard and pad bindings are
independent — rebinding one never clobbers the other. Saved to
`user://input_bindings.cfg`.

---

## Controller layout at a glance

```
        L2 (— free)                     R2  RUN (hold)
        L1  YO-YO / GRAPPLE             R1  SPRAY PAINT

     D-PAD ↑  debug row up          △  HEAVY ATTACK / SPIN
   D-PAD ← →  shop browse         □ ○  □ ATTACK·INTERACT / ○ DASH
     D-PAD ↓  debug row down        X  JUMP / CONFIRM

   SHARE  (— free)               OPTIONS  PAUSE
   L3 (click)  CROUCH / SLAM     R3 (click)  LOCK-ON
        L-STICK  MOVE                 R-STICK  CAMERA
             TOUCHPAD  (— reserved: spray tag wheel)
```

---

## 1 · Locomotion (on foot)

| Action | DS4 | Godot action | Notes |
|---|---|---|---|
| Move | **L-Stick** | `forward/back/left/right` | Analog, camera-relative |
| Camera | **R-Stick** | `camera_*` | |
| Walk → Run | **hold R2** | `run` | Analog trigger; also sprints out of a slide landing |
| Jump | **X** | `jump` | Buffered + coyote time |
| Double Jump | **X in air** | `jump` | Merchant upgrade |
| Wall Jump | **X near wall** | `jump` | Auto-detected, input-buffered; Merchant upgrade |
| Dash / Dodge | **O** | `dash` | i-frames; Merchant upgrade. Air dash allowed |
| Crouch | **L3 (stick click)** | `crouch` | see *Suggested changes* — L2 would feel better |
| Ground Slam | **L3 in air** | `crouch` | Hang beat → rocket down, AOE |

## 2 · Combat

| Action | DS4 | Godot action | Notes |
|---|---|---|---|
| Attack (yo-yo swipe) | **□** | `attack` | 3-hit combo on repeat presses |
| Heavy Attack | **△** | `heavy_attack` | Slower, more damage, breaks shields |
| Spin Attack | **△ while running** | `heavy_attack` | AOE spin, keeps momentum |
| Yo-yo Throw / Grapple | **L1** | `yoyo` | Targets enemies & grapple points |
| Lock-On | **R3 (stick click)** | `lock_on` | Camera locks nearest enemy |
| Ground Slam (combat) | **L3 in air** | `crouch` | 2 dmg AOE, breaks boxes, bounces off enemies |

## 3 · Traversal specials

| Action | DS4 | Godot action | Notes |
|---|---|---|---|
| Climb (on climb wall) | **L-Stick** | move | Auto-grab on contact |
| **Wall Hop** | **X on climb wall** | `jump` | Burst in stick direction (up if neutral) — fastest way up |
| Drop from climb wall | **L-Stick ↓ + X** | `back`+`jump` | Let go and fall |
| Ladder leap | **X on ladder** | `jump` | Classic leap-away |
| Ledge climb | **L-Stick ↑ or X** | `forward`/`jump` | From ledge hang |
| Ledge drop | **L3** | `crouch` | From ledge hang |
| Rail grind | *automatic* | — | Land on a rail; balance with L-Stick |
| Rope / Swing bar | *automatic* | — | X to release with momentum, L3 to drop |
| Slide | *automatic on slides* | — | Steer with L-Stick, O to dash out (never uphill) |
| Balance beam | *automatic* | — | Slow-walk with L-Stick, R2 to hustle |

## 4 · World & paint

| Action | DS4 | Godot action | Notes |
|---|---|---|---|
| Interact / Talk | **□** | `interact` | NPCs, doors, buttons, signs |
| Spray Paint | **R1** | `spray` | Tags walls, refills at spray cans |
| Advance dialogue | **X** | `ui_accept`/`jump` | Hold to skip typing |
| Dialogue choice | **X accept / O decline** | `jump`/`dash` | RE4-style |
| Pause | **OPTIONS** | `start` | Stats + Controls (rebind menu) |

## 5 · Shop (Merchant)

| Action | DS4 | Godot action |
|---|---|---|
| Browse upgrades | **D-Pad ← → (or L-Stick)** | `d_pad_left/right`, `left/right` |
| Scroll rows | **D-Pad ↑ ↓** | `d_pad_up/down` |
| Buy | **X** | `ui_accept` |
| Leave | **O** | `ui_cancel`/`dash` |

## 6 · Debug (dev builds)

| Action | DS4 | Godot action |
|---|---|---|
| Debug overlay | **TOUCHPAD** (suggested) / ` on KB | `display` |
| Overlay scroll | **D-Pad ↑ ↓** | `d_pad_up/down` |
| Quit game | — (KB F11 hold) | `quit_game` |

---

## Suggested changes (free buttons on a DS4)

Currently **L2**, **SHARE** and **TOUCHPAD** are free. Suggestions:

1. **Crouch/Slam → L2** — clicking L3 *while steering with the same stick* is
   the single worst ergonomic spot for a move you do mid-sprint. A hold-able
   analog trigger is the genre standard (and enables analog "sneak" later).
   Easy to try: Pause → CONTROLS → rebind Crouch, no code needed.
2. **SHARE → photo mode** when it exists; it's the thematically perfect button
   for a graffiti game (frame your tag, share it).
3. **TOUCHPAD → spray-paint color wheel** (when multiple paint types unlock);
   4 swipe quadrants = 4 paints.
4. **Keep L1 = yo-yo**: throw + camera-aim on the right stick simultaneously.
5. **Keep R3 = lock-on**: click-the-camera-stick to lock the camera is
   self-describing and matches Souls/DMC muscle memory.
6. **Long jump candidate**: L2(crouch) + X while running — the combo slot is
   reserved; classic 3D-platformer move, zero new buttons.

## Design rules

- **X is always "yes"**: jump, confirm, buy, advance dialogue.
- **O is always "escape"**: dash away, decline, leave shop.
- **□ is always "hands"**: attack, interact, talk.
- **△ is always "big swing"**: heavy, spin.
- Movement upgrades never add buttons — they extend what X/O already do, so
  muscle memory survives every purchase.
- All floating world prompts render the **live binding for the active device**
  via `InputManager.prompt()` — rebind □ to △ and every sign in the world
  updates instantly.
