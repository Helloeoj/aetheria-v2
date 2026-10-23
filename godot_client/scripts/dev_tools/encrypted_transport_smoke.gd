extends Node
var config: Dictionary
var elapsed := 0.0

func _ready() -> void:
	Network.auto_scene = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--test-input="):
			config = JSON.parse_string(FileAccess.get_file_as_string(arg.trim_prefix("--test-input=")))
	if config.is_empty():
		get_tree().quit(2)
		return
	match config.mode:
		"certificate":
			var crypto := Crypto.new()
			var key := crypto.generate_rsa(2048)
			var certificate := crypto.generate_self_signed_certificate(key, "CN=aetheria-beta", "20260101000000", "20360101000000")
			if key.save(config.key) != OK or certificate.save(config.certificate) != OK:
				get_tree().quit(3)
			else:
				get_tree().quit()
		"server":
			var key := CryptoKey.new()
			var certificate := X509Certificate.new()
			if key.load(config.key) != OK or certificate.load(config.certificate) != OK:
				get_tree().quit(3)
				return
			if Network.host(int(config.port), 2, "127.0.0.1", TLSOptions.server(key, certificate)) != OK:
				get_tree().quit(4)
				return
			Network.join_requested.connect(func(id: int, ticket: String) -> void:
				if ticket != "encrypted-admission-probe":
					get_tree().quit(5)
				Network.mark_admitted(id)
				Network.send_control(id, {"type": "notice", "message": "encrypted round trip accepted"}))
			FileAccess.open(config.ready, FileAccess.WRITE).store_string("ready")
		"client":
			Network.beta_profile = {"world_host": "127.0.0.1", "world_port": config.port, "tls_name": config.get("tls_name", "aetheria-beta"), "tls_certificate": config.certificate}
			Network.status_changed.connect(func() -> void:
				if Network.status == "encrypted round trip accepted":
					_finish(true)
				elif Network.status.begins_with("The encrypted world connection could not"):
					_finish(false))
			if Network.join_world("encrypted-admission-probe") != OK:
				_finish(false)

func _process(delta: float) -> void:
	elapsed += delta
	if config.get("mode") == "server":
		if FileAccess.file_exists(config.stop) or elapsed > 90:
			if multiplayer.multiplayer_peer != null:
				multiplayer.multiplayer_peer.close()
				multiplayer.multiplayer_peer = null
			get_tree().quit()
	elif config.get("mode") == "client" and elapsed > 20:
		_finish(false)

func _finish(connected: bool) -> void:
	FileAccess.open(config.output, FileAccess.WRITE).store_string(JSON.stringify({"connected": connected}))
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	get_tree().quit(0 if connected == bool(config.get("expected", true)) else 1)
