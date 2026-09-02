# Music

Drop level music tracks in this folder, then add a **LevelMusic** node
to any level scene to play one.

## How to add music to a level

1. Put your track in `audio/music/` (e.g. `audio/music/greybox-theme.ogg`)
2. Open the level scene, add a child node, pick **LevelMusic**
   (or add a plain `Node` and attach `scripts/audio/level_music.gd`)
3. In the Inspector, pick your file from the **Music File** dropdown —
   it lists everything in this folder automatically
4. Done. It autoplays on scene load, loops, and fades in.

## Inspector options (on the LevelMusic node)

- **music_file** — dropdown of every track in `audio/music/`
- **music_override** — drag any AudioStream here to bypass the dropdown
- **autoplay** — start when the scene loads (default on)
- **loop** — restart the track when it ends (default on; works even if
  the file wasn't imported with looping enabled)
- **volume_db** — mix level
- **fade_in_time** — seconds to ramp from silence (default 1.5)

You can also call `play()`, `stop(fade_out_seconds)` and
`crossfade_to(stream)` on the node from scripts/cutscenes.

Loop points: for seamless loops prefer `.ogg`. If you need a custom
loop point, set it on the file in Godot's Import dock instead.
