# HOW TO MAKE A CUTSCENE — the complete walkthrough

Everything from posing a character to shipping a finished scene, in
order. Skim the table, then follow the steps.

| I want to... | Tool |
|---|---|
| Pose the camera | `CutsceneCamera` node + editor **Preview**, or F10 fly + **P** |
| A moving camera | Marker3D children on a `CutsceneCamera`, or **record a take with R** |
| Move Inke / an NPC | `CutsceneManager.move_actor()` or a `CutsceneTrigger`'s `actor_moves` |
| Move HU3 | `CutsceneManager.hu3_goto()` / trigger's `hu3_destination` |
| Record + save + replay a camera move | F10 → **R** → fly → **R** → `play_camera_recording()` |
| Start a cutscene when the player walks somewhere | `CutsceneTrigger` node |
| Start a cutscene from dialogue | `DialogueManager.dialogue_ended` + the API |

---

## 1. Posing CHARACTERS

Characters are just Node3Ds. Two workflows:

**Editor (pre-placed):** drop the NPC/prop into the scene, move and
rotate it in the viewport, save. That's its opening pose.

**Runtime (scripted staging):** before the camera shows anything, place
everyone with the CutsceneManager:

```gdscript
var cm = CutsceneManager
cm.teleport_actor($Rival, $StageMarks/RivalStart.global_position, 180.0) # yaw
cm.face_actor($Rival, player.global_position)   # turn toward a point
```

Markers are your friends: add a `Node3D` named `StageMarks` with child
`Marker3D`s (`RivalStart`, `InkeMark`, `HU3Mark`...) and pose those in
the editor. Scripts then reference marks, not magic numbers.

> Inke has no cutscene animations yet — actors glide in their idle pose.
> When animations land, `move_actor` is the one place to hook a walk
> anim.

## 2. Posing the CAMERA

**Option A — in the editor:** add a `CutsceneCamera` node, move/rotate
it, and tick the viewport's **Preview** checkbox to see exactly what it
sees while you drag. Save the scene; the pose is permanent.

**Option B — find it in-game (recommended):** play, press **F10** (or
F6), fly to the perfect angle, press **P**. That saves the pose to
`res://cinematic_shots/shots.tscn` (open it, copy the shot node into
your level) AND copies inspector-ready values to your clipboard. Toast
confirms.

Fly controls: `WASD` move, `Q/E` down/up, `Shift` fast, mouse look,
scroll = speed, **P** = save shot, **R** = record take, F10/F6 exit.

## 3. A MOVING camera — three ways

**A. Marker path (simple glide):** give a `CutsceneCamera` node some
`Marker3D` **children**. `activate()` flies through them in child order
— each marker's rotation aims the camera. Set `travel_speed` (m/s) for
distance-based pacing. Great for flyovers.

**B. Recorded take (free-form, hand-flown):**

1. Play the game, press **F10** to fly.
2. Get to your start framing, press **R** — a red `● REC` toast shows.
3. Fly the move you want, exactly how you want it, mouse-look included.
4. Press **R** again — the take saves to
   `res://cinematic_shots/rec_{level}_{n}.camrec` and the exact playback
   line is copied to your clipboard.
5. Play it back from any script:
   ```gdscript
   await CutsceneManager.play_camera_recording("res://cinematic_shots/rec_island_1.camrec")
   ```
   It glides in from the gameplay cam, replays your flight
   frame-for-frame, then glides back. The await returns when it's done.

**C. Scripted `move_to`:** for chained shots with logic between them:

```gdscript
$Cam.activate(1.0)
await $Cam.move_to($ShotB.global_transform, 2.5).finished
```

## 4. Moving CHARACTERS during the scene

```gdscript
# Walk the rival to the door at 2.5 m/s, facing his direction of travel:
await CutsceneManager.move_actor($Rival, $StageMarks/Door.global_position, 2.5)

# Two actors at once: don't await the first
CutsceneManager.move_actor($ThugA, $Marks/Left.global_position, 3.0)
await CutsceneManager.move_actor($ThugB, $Marks/Right.global_position, 3.0)
```

`move_actor` pauses a CharacterBody3D's physics for the ride (so gravity
/ AI don't fight it) and restores it after. Works on the player too.

## 5. Moving HU3

HU3 normally auto-follows Inke. The cutscene API overrides that:

```gdscript
await CutsceneManager.hu3_goto($Marks/Console.global_position, 6.0)  # fly there
CutsceneManager.hu3_face(player.global_position)                     # look at Inke
# ... dialogue ...
CutsceneManager.hu3_release()   # back to following (release_control also does this)
```

While overridden he hovers in place and ignores gears/following.

## 6. RECORD, SAVE, PLAY BACK

Covered in 3B — the full loop is:

| Step | Key/API |
|---|---|
| Record | F10 fly mode → **R** start → fly → **R** stop |
| Saved where | `res://cinematic_shots/rec_{level}_{n}.camrec` (JSON, 20 fps) |
| Play back | `await CutsceneManager.play_camera_recording(path)` |
| In a trigger | set `camera_recording` on a `CutsceneTrigger` |

Recordings only save when running from the editor (`res://` writable).

## 7. INITIATING cutscenes

### A. In-world (walk into an area) — no code

Add a **CutsceneTrigger** node (Area3D) where the scene should start and
configure in the Inspector:

- `box_size` — the trigger volume
- `camera_recording` — a .camrec take, **or** `cutscene_camera` — a
  posed CutsceneCamera in the scene (+ `camera_hold` seconds)
- `actor_moves` — pairs of NodePaths: `[actor, marker, actor, marker…]`,
  walked in order at `actor_speed`
- `hu3_destination` — marker to fly HU3 to
- `dialogue_file` — dialogue JSON to play mid-scene
- `trigger_once` — almost always ON

It freezes the player, runs camera + moves + dialogue, unfreezes. Done.

### B. From dialogue

Two patterns. **After a conversation ends** (e.g. NPC says "look over
there!" then the camera shows it):

```gdscript
DialogueManager.dialogue_ended.connect(func():
    CutsceneManager.take_control()
    await CutsceneManager.play_camera_recording("res://cinematic_shots/rec_island_2.camrec")
    CutsceneManager.release_control()
, CONNECT_ONE_SHOT)
```

**Mid-cutscene dialogue** (freeze first, talk during the scene):

```gdscript
CutsceneManager.take_control()
$RevealCam.activate(1.2)
DialogueManager.start_dialogue("BossReveal")   # from res://dialogue/{scene}/
await DialogueManager.dialogue_ended
$RevealCam.deactivate(1.0)
CutsceneManager.release_control()
```

(For simple talking-head scenes you don't need any of this — every
DialogueTrigger/QuestGiver/Merchant already has `dynamic_camera` auto
shots and `custom_camera_angles`. See `README.md` in this folder.)

### C. From any script

```gdscript
func play_intro() -> void:
    var cm = CutsceneManager
    cm.take_control()                                   # freeze player, hide HUD
    cm.teleport_actor($Boss, $Marks/Throne.global_position, 180)
    await cm.play_camera_recording("res://cinematic_shots/rec_lair_1.camrec")
    await cm.move_actor($Boss, $Marks/Front.global_position, 2.0)
    cm.hu3_goto($Marks/HideSpot.global_position)        # HU3 hides (not awaited)
    DialogueManager.start_dialogue("BossIntro")
    await DialogueManager.dialogue_ended
    await cm.wait(0.5)                                  # beat
    cm.release_control()                                # unfreeze everything
```

## 8. API cheat sheet

```gdscript
CutsceneManager.take_control()                    # freeze player + cutscene mode
CutsceneManager.release_control()                 # undo everything
await CutsceneManager.move_actor(node, pos, speed)
CutsceneManager.face_actor(node, pos)
CutsceneManager.teleport_actor(node, pos, yaw_deg)
await CutsceneManager.hu3_goto(pos, speed)
CutsceneManager.hu3_face(pos)
CutsceneManager.hu3_release()
await CutsceneManager.play_camera_recording(path)
await CutsceneManager.wait(seconds)

$CutsceneCamera.activate(blend)  /  .deactivate(blend)
$CutsceneCamera.move_to(pose, dur)                # returns awaitable Tween
```
