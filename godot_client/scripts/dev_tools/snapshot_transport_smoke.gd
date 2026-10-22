extends Node

class PanelGame extends Node:
	var player := PlayerState.new("Status test")

var failures := 0
var checks := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("[Snapshot transport FAIL] ", label)

func _ready() -> void:
	var protocol: Script = load("res://network/world_protocol.gd")
	for invalid_version: Variant in ["1", 1.5, true, {}, [], null, 0, 2]:
		var malformed := JSON.stringify({"v": invalid_version, "type": "snapshot"}).to_utf8_buffer()
		check(protocol.unpack(malformed).is_empty(), "Non-numeric or fractional protocol versions are rejected")
	for valid_version: Variant in [1, 1.0]:
		var valid := JSON.stringify({"v": valid_version, "type": "snapshot"}).to_utf8_buffer()
		check(not protocol.unpack(valid).is_empty(), "Exact protocol version survives JSON numeric decoding")
	var path := "res://network/snapshot_transport.gd"
	check(ResourceLoader.exists(path), "Bounded compressed snapshot transport exists")
	if failures > 0:
		get_tree().quit(1)
		return
	var transport: Script = load(path)
	var tiny := {"v": 1, "type": "snapshot", "snapshot_id": 0, "state": {"gold": 7}}
	var tiny_packets: Array = transport.chunk(tiny)
	check(tiny_packets.size() == 1, "Small compressed snapshots use a single packet")
	var tiny_receiver: RefCounted = transport.new()
	check(int(tiny_receiver.accept(tiny_packets[0], 0).get("state", {}).get("gold", -1)) == 7, "Single-packet snapshots also decode correctly")
	var snapshot := {"v": 1, "type": "snapshot", "snapshot_id": 10, "region_id": "outskirts", "state": {"gold": 42}, "noise": Crypto.new().generate_random_bytes(10000).hex_encode()}
	var packets: Array = transport.chunk(snapshot)
	check(packets.size() > 2, "Large snapshots are split across several packets")
	for packet: PackedByteArray in packets:
		check(packet.size() <= 900, "Every application packet fits below the network MTU")
	var receiver: RefCounted = transport.new()
	check(receiver.accept(packets[0], 0).is_empty(), "An incomplete snapshot is never published")
	check(receiver.accept(packets[0], 1).is_empty(), "Duplicate parts do not complete a snapshot")
	var restored := {}
	for index in range(packets.size() - 1, 0, -1):
		var result: Dictionary = receiver.accept(packets[index], 2)
		if not result.is_empty():
			restored = result
	check(restored.get("noise") == snapshot.noise and int(restored.get("state", {}).get("gold", -1)) == 42, "Reordered compressed chunks restore the complete snapshot")
	check(receiver.accept(packets[0], 3).is_empty(), "Completed snapshots cannot be replayed")

	var newer := snapshot.duplicate(true)
	newer.snapshot_id = 11
	var newer_packets: Array = transport.chunk(newer)
	receiver.reset()
	receiver.accept(packets[0], 0)
	for packet: PackedByteArray in newer_packets:
		restored = receiver.accept(packet, 10)
	check(restored.get("snapshot_id") == 11, "A missing older snapshot cannot block a newer complete one")
	for packet: PackedByteArray in packets:
		check(receiver.accept(packet, 20).is_empty(), "Late older chunks cannot replace a completed newer snapshot")

	receiver.reset()
	receiver.accept(packets[0], 0)
	check(receiver.accept(packets[1], 2000).is_empty(), "Expired missing parts do not assemble across the retention deadline")
	check(receiver._pending.size() <= 1, "Expired assemblies are evicted")
	check(receiver.accept(PackedByteArray([1, 2, 3]), 2001).is_empty(), "Truncated headers are rejected")
	var bad: PackedByteArray = packets[0].duplicate()
	bad.encode_u32(12, 0x7fffffff)
	check(receiver.accept(bad, 2002).is_empty(), "Oversized decompression claims are rejected before allocation")
	bad = packets[0].duplicate()
	bad.encode_u16(20, 65535)
	check(receiver.accept(bad, 2003).is_empty(), "Out-of-range chunk indexes are rejected")
	bad = packets[0].duplicate()
	bad.encode_u16(22, 65535)
	check(receiver.accept(bad, 2004).is_empty(), "Oversized chunk counts are rejected")
	bad = packets[0].duplicate()
	bad.append(0)
	check(receiver.accept(bad, 2005).is_empty(), "Oversized packets are rejected")
	receiver.reset()
	receiver.accept(packets[0], 0)
	bad = packets[1].duplicate()
	bad.encode_u32(12, bad.decode_u32(12) + 1)
	check(receiver.accept(bad, 1).is_empty() and receiver._pending.is_empty(), "Conflicting metadata discards the ambiguous assembly")
	receiver.reset()
	for index in packets.size():
		bad = packets[index].duplicate()
		if index == 0:
			bad[bad.size() - 1] ^= 1
		check(receiver.accept(bad, 0).is_empty(), "Corrupted compressed streams are discarded without publication")
	check(receiver._pending.is_empty() and receiver._pending_bytes == 0, "Rejected complete streams release retained memory")
	receiver.reset()
	for packet: PackedByteArray in packets:
		bad = packet.duplicate()
		bad.encode_u64(4, 12)
		check(receiver.accept(bad, 0).is_empty(), "Envelope IDs must match the decoded snapshot ID")
	newer.v = 2
	for packet: PackedByteArray in transport.chunk(newer):
		check(receiver.accept(packet, 1).is_empty(), "Unsupported decoded protocol versions are rejected")
	newer.v = 1
	for packet: PackedByteArray in packets:
		restored = receiver.accept(packet, 2)
	check(restored.get("snapshot_id") == 10, "Malformed future snapshots cannot advance the completed sequence")

	receiver.reset()
	for serial in range(20, 40):
		newer.snapshot_id = serial
		var fragments: Array = transport.chunk(newer)
		receiver.accept(fragments[0], 0)
	check(receiver._pending.size() <= 4 and receiver._pending_bytes <= 524288, "Missing chunks cannot grow retained assemblies or memory without bound")
	for packet: PackedByteArray in transport.chunk(newer):
		restored = receiver.accept(packet, 1)
	check(restored.get("snapshot_id") == 39, "The newest snapshot survives bounded pending eviction")
	receiver.reset()
	var large := snapshot.duplicate(true)
	large.noise = Crypto.new().generate_random_bytes(120000).hex_encode()
	for serial in range(40, 44):
		large.snapshot_id = serial
		var fragments: Array = transport.chunk(large)
		for index in range(fragments.size() - 1):
			check(receiver.accept(fragments[index], 0).is_empty(), "Incomplete large snapshots never publish")
			check(receiver._pending_bytes <= 524288, "Received compressed bytes stay inside the memory limit")
	check(receiver._pending.size() < 4, "The byte budget evicts incomplete assemblies before allocating more")
	var oversized := snapshot.duplicate(true)
	oversized.noise = "x".repeat(300000)
	check(transport.chunk(oversized).is_empty(), "Oversized snapshots are rejected before compression")
	receiver.reset()
	for packet: PackedByteArray in packets:
		restored = receiver.accept(packet, 0)
	check(restored.get("snapshot_id") == 10, "Reconnect reset accepts a fresh server sequence")
	var panel: Control = load("res://network/online_activity_panel.gd").new()
	var panel_game := PanelGame.new()
	add_child(panel_game)
	add_child(panel)
	panel.configure(panel_game)
	panel.open_station("shore", "fish", "Harbor")
	Network.status = "A server notice"
	Network.status_changed.emit()
	check(panel._network_message == "A server notice" and panel._status.text == "A server notice", "Zero-argument network status signals display Network.status")
	panel.queue_free()
	print("[Snapshot transport] %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
