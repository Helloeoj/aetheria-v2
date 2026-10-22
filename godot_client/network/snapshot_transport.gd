extends RefCounted
## Compressed, independently ordered snapshot chunks. Never publish partial state.
const Protocol = preload("res://network/world_protocol.gd")
const MAGIC := 0x41534e31
const HEADER_SIZE := 56
const PACKET_SIZE := 900
const CHUNK_SIZE := PACKET_SIZE - HEADER_SIZE
const MAX_RAW := Protocol.MAX_PAYLOAD
const MAX_COMPRESSED := MAX_RAW + 1024
const MAX_PENDING := 4
const MAX_PENDING_BYTES := 512 * 1024
const RETENTION_MS := 1000
var _pending: Dictionary = {}
var _pending_bytes := 0
var _last_complete := -1

static func chunk(snapshot: Dictionary) -> Array[PackedByteArray]:
	var packets: Array[PackedByteArray] = []
	var serial: Variant = snapshot.get("snapshot_id")
	if not _valid_serial(serial) or snapshot.get("type") != "snapshot":
		return packets
	var raw := Protocol.pack(snapshot)
	if raw.is_empty() or raw.size() > MAX_RAW:
		return packets
	var compressed := raw.compress(FileAccess.COMPRESSION_DEFLATE)
	if compressed.is_empty() or compressed.size() > MAX_COMPRESSED:
		return packets
	var digest := _digest(compressed)
	var count := ceili(float(compressed.size()) / CHUNK_SIZE)
	for index in count:
		var packet := PackedByteArray()
		packet.resize(HEADER_SIZE)
		packet.encode_u32(0, MAGIC)
		packet.encode_u64(4, int(serial))
		packet.encode_u32(12, raw.size())
		packet.encode_u32(16, compressed.size())
		packet.encode_u16(20, index)
		packet.encode_u16(22, count)
		for offset in digest.size():
			packet[24 + offset] = digest[offset]
		packet.append_array(compressed.slice(index * CHUNK_SIZE, mini((index + 1) * CHUNK_SIZE, compressed.size())))
		packets.append(packet)
	return packets

func reset() -> void:
	_pending.clear()
	_pending_bytes = 0
	_last_complete = -1

func accept(packet: PackedByteArray, now_ms: int = -1) -> Dictionary:
	var now := Time.get_ticks_msec() if now_ms < 0 else now_ms
	for id: int in _pending.keys():
		if now - int(_pending[id].created) >= RETENTION_MS:
			_erase(id)
	if packet.size() <= HEADER_SIZE or packet.size() > PACKET_SIZE or packet.decode_u32(0) != MAGIC:
		return {}
	var serial := packet.decode_u64(4)
	var raw_size := packet.decode_u32(12)
	var compressed_size := packet.decode_u32(16)
	var index := packet.decode_u16(20)
	var count := packet.decode_u16(22)
	if not _valid_serial(serial) or serial <= _last_complete or raw_size < 1 or raw_size > MAX_RAW or compressed_size < 1 or compressed_size > MAX_COMPRESSED:
		return {}
	if count != ceili(float(compressed_size) / CHUNK_SIZE) or index >= count:
		return {}
	var expected_size := mini(CHUNK_SIZE, compressed_size - index * CHUNK_SIZE)
	if packet.size() != HEADER_SIZE + expected_size:
		return {}
	var digest := packet.slice(24, HEADER_SIZE)
	if _pending.has(serial):
		var existing: Dictionary = _pending[serial]
		if existing.raw_size != raw_size or existing.compressed_size != compressed_size or existing.digest != digest:
			_erase(serial)
			return {}
	else:
		while _pending.size() >= MAX_PENDING:
			var oldest := int(_pending.keys().min())
			if serial <= oldest:
				return {}
			_erase(oldest)
		_pending[serial] = {"created": now, "raw_size": raw_size, "compressed_size": compressed_size, "digest": digest, "parts": {}, "bytes": 0}
	var entry: Dictionary = _pending[serial]
	if entry.parts.has(index):
		return {}
	while _pending_bytes + expected_size > MAX_PENDING_BYTES:
		var oldest := int(_pending.keys().min())
		_erase(oldest)
		if oldest == serial:
			return {}
	entry.parts[index] = packet.slice(HEADER_SIZE)
	entry.bytes = int(entry.bytes) + expected_size
	_pending_bytes += expected_size
	if entry.parts.size() != count:
		return {}
	var compressed := PackedByteArray()
	for part in count:
		compressed.append_array(entry.parts[part])
	_erase(serial)
	# Reject damaged streams before asking the decompressor to allocate or decode.
	if _digest(compressed) != digest:
		return {}
	var raw := compressed.decompress(raw_size, FileAccess.COMPRESSION_DEFLATE)
	if raw.size() != raw_size:
		return {}
	var snapshot := Protocol.unpack(raw)
	if snapshot.get("type") != "snapshot" or not _valid_serial(snapshot.get("snapshot_id")) or int(snapshot.snapshot_id) != serial:
		return {}
	_last_complete = serial
	for id: int in _pending.keys():
		if id <= serial:
			_erase(id)
	return snapshot

func _erase(serial: int) -> void:
	_pending_bytes -= int(_pending[serial].bytes)
	_pending.erase(serial)

static func _valid_serial(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0 and float(value) <= 9007199254740991.0 and floor(float(value)) == float(value)

static func _digest(bytes: PackedByteArray) -> PackedByteArray:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish()
