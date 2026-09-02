@tool
extends Node
class_name LevelMusic
## Drop this node into any level to play a music track from
## res://audio/music/. Pick the track with the music_file dropdown
## (auto-populated from the folder), or drag a stream into
## music_override. Autoplays, loops and fades in by default.

const MUSIC_DIR := "res://audio/music/"
const AUDIO_EXTENSIONS := [".ogg", ".wav", ".mp3"]

## Track picked from audio/music/ (dropdown). Ignored if music_override set.
var music_file: String = ""
## Drag any AudioStream here to bypass the folder dropdown.
@export var music_override: AudioStream = null
## Start playing as soon as the scene loads.
@export var autoplay: bool = true
## Restart the track when it finishes (even if the import isn't looped).
@export var loop: bool = true
## Mix level for this track.
@export var volume_db: float = -6.0
## Seconds to fade in from silence when playback starts.
@export var fade_in_time: float = 1.5

var _player: AudioStreamPlayer
var _fade_tween: Tween


func _get_property_list() -> Array[Dictionary]:
	# Expose music_file as a dropdown of everything in audio/music/
	return [{
		"name": "music_file",
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_ENUM_SUGGESTION,
		"hint_string": ",".join(available_tracks()),
		"usage": PROPERTY_USAGE_DEFAULT,
	}]


static func available_tracks() -> PackedStringArray:
	var tracks := PackedStringArray()
	var dir = DirAccess.open(MUSIC_DIR)
	if dir == null:
		return tracks
	dir.list_dir_begin()
	var f = dir.get_next()
	while f != "":
		if not dir.current_is_dir():
			var name = f.trim_suffix(".remap").trim_suffix(".import")
			for ext in AUDIO_EXTENSIONS:
				if name.ends_with(ext) and not tracks.has(name):
					tracks.append(name)
		f = dir.get_next()
	tracks.sort()
	return tracks


func _ready():
	if Engine.is_editor_hint():
		return
	_player = AudioStreamPlayer.new()
	_player.bus = "Master"
	_player.process_mode = Node.PROCESS_MODE_ALWAYS  # Keeps playing in pause menus
	add_child(_player)
	_player.finished.connect(_on_finished)
	if autoplay:
		play()


func _resolve_stream() -> AudioStream:
	if music_override:
		return music_override
	if music_file != "" and ResourceLoader.exists(MUSIC_DIR + music_file):
		var res = load(MUSIC_DIR + music_file)
		if res is AudioStream:
			return res
	if music_file != "":
		push_warning("LevelMusic: track not found: " + MUSIC_DIR + music_file)
	return null


func _kill_fade() -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null


func play() -> void:
	var stream = _resolve_stream()
	if stream == null:
		return
	_player.stream = stream
	if fade_in_time > 0.0:
		_player.volume_db = -60.0
		_kill_fade()
		_fade_tween = create_tween()
		_fade_tween.tween_property(_player, "volume_db", volume_db, fade_in_time)
	else:
		_player.volume_db = volume_db
	_player.play()


func stop(fade_out_time: float = 1.0) -> void:
	if not _player.playing:
		return
	if fade_out_time <= 0.0:
		_player.stop()
		return
	_kill_fade()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_player, "volume_db", -60.0, fade_out_time)
	_fade_tween.tween_callback(_player.stop)


func crossfade_to(stream: AudioStream, fade_time: float = 1.5) -> void:
	"""Fade the current track out while the new one fades in."""
	if _player.playing:
		# Hand the old stream to a throwaway player so both can sound at once
		var old = AudioStreamPlayer.new()
		old.bus = _player.bus
		old.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(old)
		old.stream = _player.stream
		old.volume_db = _player.volume_db
		old.play(_player.get_playback_position())
		_player.stop()
		var out_tween = create_tween()
		out_tween.tween_property(old, "volume_db", -60.0, fade_time)
		out_tween.tween_callback(old.queue_free)
	music_override = stream
	fade_in_time = fade_time
	play()


func _on_finished() -> void:
	if loop:
		_player.play()
