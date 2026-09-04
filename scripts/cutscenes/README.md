# Cameras: cutscenes, free roam, and custom dialogue shots

Everything camera-related that isn't the gameplay camera lives here:

| File | What it is |
|---|---|
| `cutscene_camera.gd` | `CutsceneCamera` node — a posable camera for cutscenes, camera paths and level previews |
| `dialogue_camera_director.gd` | The system that cuts between cinematic angles during dialogue |

---

## 1. Free roam / debug fly camera (F10 or F6)

Press **F10** (or **F6**) during play — no node needed, works in every
scene. A fly camera detaches from your current view and a hint bar
appears at the top of the screen.

> **F10 "not doing anything"?** On most laptops (and some desktop
> keyboards) F10 is a MEDIA key — the OS eats it for mute/volume unless
> you hold **Fn**. That's why **F6** is also bound. Use whichever works.

Controls while flying:

| Key | Action |
|---|---|
| `W A S D` | fly forward/left/back/right |
| `Q / E` | down / up |
| `Shift` | fly fast |
| Mouse | look |
| Scroll wheel | change fly speed |
| **`P`** | **SAVE the current pose as a shot** (see below) |
| `F10` / `F6` | exit back to gameplay |

The player is frozen while you fly, so nothing wanders off.

### What P actually does (three things at once)

1. **Saves the shot into `res://cinematic_shots/shots.tscn`** - a
   library scene of posed CutsceneCameras, named like
   `greybox_Shot1`, `greybox_Shot2`... Open that scene in the editor
   and **copy/paste the shot nodes into your levels** (or drag them
   into `custom_camera_angles`). This is the pre-scripting workflow:
   fly, press P, done - the pose is on disk.
2. **Copies an Inspector-ready snippet to the clipboard** - paste it
   into any Node3D's transform properties if you prefer that route.
3. **Shows a green "SHOT SAVED" toast** at the bottom of the screen so
   you know it worked (it also prints to the Output panel).

Note: saving to `res://` works when running from the editor (the
normal case). In an exported build only the clipboard/print happen.

---

## 2. Making your OWN dialogue camera shots (saved, permanent)

Every dialogue speaker — **DialogueTrigger**, **QuestGiver**,
**Merchant** — has these in the Inspector under **Dynamic Camera**:

- `dynamic_camera` (checkbox, default ON) — cinematic angles during the
  conversation. Auto-generated film shots unless you supply your own.
- `custom_camera_angles` (Array of Node3D) — **your shots**. When this
  array has anything in it, the auto shots are ignored and the camera
  uses YOUR angles instead — every time, in the shipped game, forever.
  They're saved in the scene like any other node data.

### Step-by-step: author shots entirely in the editor

1. **Create the shot nodes.** In the scene tree, add a child under your
   NPC/trigger (or anywhere — position is what matters):
   *Add Child Node → Node3D* (or `CutsceneCamera` if you also want to
   control FOV per shot). Name it something like `ShotWide`.
2. **Pose it.** Move/rotate it in the viewport like any node. The shot
   looks along the node's **-Z axis** (standard Godot camera forward).
   With a `CutsceneCamera` you can click the editor's **Preview**
   checkbox to see exactly what the shot sees while you drag it.
3. **Repeat** for as many angles as you want: `ShotCloseup`,
   `ShotReverse`, `ShotOverShoulder`…
4. **Assign them.** Select the NPC/trigger → Inspector → *Dynamic
   Camera* → `custom_camera_angles` → set the size and drag your shot
   nodes into the slots. **Order matters** — the conversation walks the
   array top to bottom and loops.
5. **Save the scene.** Done. From now on that conversation always uses
   your shots.

### Or: find shots in-game first (the F10 workflow)

1. Play the game, walk up to the NPC.
2. Hit **F10/F6**, fly to a nice angle, press **P**.
3. Alt-tab to the editor's Output panel, copy the printed
   `position` / `rotation_degrees`.
4. Add a Node3D in the editor, paste the values into its transform.
5. Add it to `custom_camera_angles` as above.

### How the shots play out

- The camera **starts from the current gameplay view** and glides into
  the first shot when the dialogue begins.
- It advances to the next shot **when the speaker changes** (a monologue
  holds its shot — cuts only happen on a new name).
- When the dialogue ends it glides back to the gameplay camera.
- A plain `Node3D` shot keeps the current FOV. A `CutsceneCamera` (or
  any `Camera3D`) shot also applies its **fov** — great for close-ups.
- Fewer shots than speaker changes? The array loops.

### Gotchas

- The shot node must be in the **same scene** as the speaker so the
  exported reference resolves.
- If a shot node gets freed at runtime it's skipped silently.
- `custom_camera_angles` EMPTY = auto film shots (over-the-shoulder /
  reverse / close-up / wide rotation). That's the default.

---

## 3. CutsceneCamera (posable cutscene shots + camera paths)

Add a **CutsceneCamera** node to a scene and pose it. Then from any
script:

```gdscript
$CutsceneCamera.activate(1.5)     # glide from gameplay cam, 1.5s
# ... dialogue, spawns, whatever ...
$CutsceneCamera.deactivate(1.0)   # glide back to gameplay
```

- `travel_speed` (m/s) — when > 0, all glides are paced by DISTANCE
  instead of fixed seconds. A cross-level flight takes its time; a small
  reposition stays snappy.
- **Camera paths:** give the CutsceneCamera **Marker3D children** and
  `activate()` flies through them in order (rotate markers to aim).
  Great for "here's the whole level" flyovers. No children = simple
  tween to the camera's pose.
- `move_to(pose, duration)` — chain extra shots; returns an awaitable
  Tween.
- `print_pose()` — same output as pressing P in fly mode.

### Level previews from dialogue ("go here")

Pose a CutsceneCamera at the goal (or lay a marker path along the
route), then around your dialogue:

```gdscript
DialogueManager.dialogue_ended.connect(func():
    $GoalPreviewCam.activate()          # fly out to show the goal
    await get_tree().create_timer(2.5).timeout
    $GoalPreviewCam.deactivate()        # glide cleanly home
, CONNECT_ONE_SHOT)
```
