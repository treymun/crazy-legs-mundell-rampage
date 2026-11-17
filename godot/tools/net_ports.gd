## Free ports on 127.0.0.1 for the net checks, run many at once beside other
## work (check_all runs them side by side; the owner's games and Steam run on
## this PC).
##
##   const NetPorts := preload("res://tools/net_ports.gd")
##   var port := NetPorts.pick("relay_check", [0, 7000], [3000])
##
## Two things made the checks fail now and then (pass 9):
##
## - **Ports past 49152** are where Windows (and most systems) hand out the
##   ports of outgoing sockets: every ENet client of every other check, game
##   or chat program takes one there, bound to all addresses. On Windows a
##   server bound to 127.0.0.1 may take the same port as such a socket without
##   any error, and from then on it gets that socket's packets (or the client
##   gets none). Every port here stays under BELOW.
## - **A taken port** made ENet print "Couldn't create an ENet host", which
##   the checks count as an engine error even when the next port worked. A
##   plain UDP socket (and a TCP listener for a WebSocket port) is tried
##   first, quietly, on all addresses and on 127.0.0.1 (each alone misses one
##   way of clashing on Windows), so the real bind almost always takes the
##   first port it is given.
extends RefCounted

const LOW := 20000
const BELOW := 49152


## A base port whose `udp` offsets (ENet) and `tcp` offsets (WebSocket) are
## all free now, picked from this process and `salt` (each check its own
## start, so checks run at once rarely try the same ports).
static func pick(salt: String, udp: Array = [0], tcp: Array = []) -> int:
	var reach := 0
	for o: int in udp + tcp:
		reach = maxi(reach, o)
	var width := BELOW - LOW - reach - 1
	var start := (OS.get_process_id() * 7919 + salt.hash()) % width
	start = absi(start)
	for k in 400:
		var base := LOW + (start + k * 13) % width
		if _all_free(base, udp, tcp):
			return base
	return LOW + start


static func _all_free(base: int, udp: Array, tcp: Array) -> bool:
	for o: int in udp:
		if not udp_free(base + o):
			return false
	for o: int in tcp:
		if not tcp_free(base + o):
			return false
	return true


## Nothing holds this UDP port, on all addresses or on 127.0.0.1.
static func udp_free(port: int) -> bool:
	for bind: String in ["*", "127.0.0.1"]:
		var u := PacketPeerUDP.new()
		var ok := u.bind(port, bind) == OK
		u.close()
		if not ok:
			return false
	return true


## Nothing listens on this TCP port.
static func tcp_free(port: int) -> bool:
	for bind: String in ["*", "127.0.0.1"]:
		var t := TCPServer.new()
		var ok := t.listen(port, bind) == OK
		t.stop()
		if not ok:
			return false
	return true
