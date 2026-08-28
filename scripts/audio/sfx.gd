class_name Sfx
extends RefCounted

## Tiny sound-effect helper.
## Every combat sound in the game has an @export AudioStream slot on the
## node that plays it - drop any .wav/.ogg in the Inspector to replace the
## default. When the slot is left EMPTY we fall back to a beefy
## procedurally-generated default from here (no audio assets needed).

const SAMPLE_RATE := 22050

static var _cache: Dictionary = {}


static func play_3d(from_node: Node, stream: AudioStream, position: Vector3,
		volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	"""Fire-and-forget positional sound. Survives the emitter dying."""
	if stream == null or from_node == null or not from_node.is_inside_tree():
		return
	var p = AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = volume_db
	# Slight random pitch so repeated hits don't sound machine-gunned
	p.pitch_scale = pitch_scale * randf_range(0.94, 1.06)
	p.max_distance = 60.0
	from_node.get_tree().root.add_child(p)
	p.global_position = position
	p.finished.connect(p.queue_free)
	p.play()


# ---------------------------------------------------------------------------
# Default sounds (generated once, cached)
# ---------------------------------------------------------------------------

static func attack_whoosh() -> AudioStream:
	"""Beefy melee hit: fast noise slap + low punch."""
	return _cached("attack", func():
		var n := int(0.18 * SAMPLE_RATE)
		var samples := PackedFloat32Array()
		samples.resize(n)
		var noise_state := 12345
		for i in range(n):
			var t := float(i) / SAMPLE_RATE
			var env := exp(-t * 28.0)
			# Cheap deterministic noise
			noise_state = (noise_state * 1103515245 + 12345) & 0x7FFFFFFF
			var noise := (float(noise_state) / 0x7FFFFFFF) * 2.0 - 1.0
			# Darken the noise (one-pole lowpass feel via averaging with a sine)
			var punch := sin(TAU * (140.0 - t * 300.0) * t) * exp(-t * 18.0)
			samples[i] = clampf(noise * 0.45 * env + punch * 0.9, -1.0, 1.0)
		return _to_wav(samples))


static func slam_boom() -> AudioStream:
	"""Ground slam / stomp impact: deep sub drop with a crack on top."""
	return _cached("slam", func():
		var n := int(0.55 * SAMPLE_RATE)
		var samples := PackedFloat32Array()
		samples.resize(n)
		var noise_state := 777
		var phase := 0.0
		for i in range(n):
			var t := float(i) / SAMPLE_RATE
			# Pitch drops 130 -> 32 Hz - the "boom"
			var freq := lerpf(130.0, 32.0, minf(t / 0.28, 1.0))
			phase += TAU * freq / SAMPLE_RATE
			var body := sin(phase) * exp(-t * 6.5)
			# Initial crack: 25ms of noise
			noise_state = (noise_state * 1103515245 + 12345) & 0x7FFFFFFF
			var noise := (float(noise_state) / 0x7FFFFFFF) * 2.0 - 1.0
			var crack := noise * exp(-t * 90.0) * 0.6
			# Soft-clip for beef
			samples[i] = clampf(tanh((body * 1.6 + crack) * 1.3), -1.0, 1.0)
		return _to_wav(samples))


static func stomp_bounce() -> AudioStream:
	"""Bouncing off an enemy's head: meaty thud with a springy tail-up."""
	return _cached("bounce", func():
		var n := int(0.32 * SAMPLE_RATE)
		var samples := PackedFloat32Array()
		samples.resize(n)
		var phase := 0.0
		var noise_state := 4242
		for i in range(n):
			var t := float(i) / SAMPLE_RATE
			# Thud first (110 Hz falling), then a quick springy rise
			var freq: float
			if t < 0.08:
				freq = lerpf(110.0, 70.0, t / 0.08)
			else:
				freq = lerpf(70.0, 260.0, minf((t - 0.08) / 0.18, 1.0))
			phase += TAU * freq / SAMPLE_RATE
			var body := sin(phase) * exp(-t * 9.0)
			noise_state = (noise_state * 1103515245 + 12345) & 0x7FFFFFFF
			var noise := (float(noise_state) / 0x7FFFFFFF) * 2.0 - 1.0
			var slap := noise * exp(-t * 70.0) * 0.4
			samples[i] = clampf(tanh((body * 1.4 + slap) * 1.2), -1.0, 1.0)
		return _to_wav(samples))


# ---------------------------------------------------------------------------

static func _cached(key: String, builder: Callable) -> AudioStream:
	if not _cache.has(key):
		_cache[key] = builder.call()
	return _cache[key]


static func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	var bytes = PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in range(samples.size()):
		var v = int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	wav.data = bytes
	return wav
