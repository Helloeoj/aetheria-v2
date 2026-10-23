extends RefCounted
## Set DTLS up before ENet connects. Only then attach to high-level multiplayer.
var connection: ENetConnection
var multiplayer_peer: ENetMultiplayerPeer
var _id := 0
var _deadline := 0

func start(address: String, port: int, tls_name: String, certificate: X509Certificate) -> Error:
	if certificate == null or tls_name.is_empty() or port < 1 or port > 65535:
		return ERR_INVALID_PARAMETER
	connection = ENetConnection.new()
	var error := connection.create_host(1, 5)
	if error != OK:
		return error
	error = connection.dtls_client_setup(tls_name, TLSOptions.client(certificate))
	if error != OK:
		close()
		return error
	_id = maxi(2, int(Crypto.new().generate_random_bytes(4).decode_u32(0) & 0x7fffffff))
	if connection.connect_to_host(address, port, 5, _id) == null:
		close()
		return ERR_CANT_CONNECT
	_deadline = Time.get_ticks_msec() + 15000
	return OK

func poll() -> Error:
	if connection == null:
		return ERR_UNCONFIGURED
	if Time.get_ticks_msec() >= _deadline:
		close()
		return ERR_TIMEOUT
	var event := connection.service(0)
	if event[0] == ENetConnection.EVENT_CONNECT:
		multiplayer_peer = ENetMultiplayerPeer.new()
		var error := multiplayer_peer.create_mesh(_id)
		if error != OK:
			close()
		return error
	if event[0] in [ENetConnection.EVENT_ERROR, ENetConnection.EVENT_DISCONNECT]:
		close()
		return ERR_CANT_CONNECT
	return ERR_BUSY

func attach_server() -> Error:
	# SceneMultiplayer must subscribe before add_mesh_peer emits peer_connected.
	return multiplayer_peer.add_mesh_peer(1, connection)

func close() -> void:
	if multiplayer_peer != null:
		multiplayer_peer.close()
		multiplayer_peer = null
	elif connection != null:
		connection.destroy()
	connection = null
