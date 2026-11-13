## Asks the router to open the host's port (UPnP), on a thread of its own:
## discovery takes a second or two and must never stall a frame. Most home
## routers answer; when one does not (UPnP off, or the provider shares one
## address among many homes: CGNAT) the port has to be forwarded by hand or
## the players join over a VPN such as Tailscale or ZeroTier (docs/online.md).
##
##   var up := NetUpnp.new()
##   up.open(47197)        # then read `state` each frame
##   up.close()            # takes the mapping down again (also on a thread)
class_name NetUpnp
extends RefCounted

## "idle", "asking", "open" (the router mapped the port), "failed"
var state := "idle"
## The router's outside address once it answered ("" if it would not say).
var external := ""
## Why it failed, for the lobby to show.
var why := ""
var port := 0
var _thread: Thread = null
var _mutex := Mutex.new()
var _upnp: UPNP = null


func open(at_port: int) -> void:
	if _thread != null:
		return
	port = at_port
	state = "asking"
	_thread = Thread.new()
	_thread.start(_open_worker)


func _open_worker() -> void:
	var upnp := UPNP.new()
	var err := upnp.discover(2000, 2, "InternetGatewayDevice")
	var gateway := upnp.get_gateway() if err == UPNP.UPNP_RESULT_SUCCESS else null
	var result_state := "failed"
	var result_why := ""
	var result_external := ""
	if gateway == null or not gateway.is_valid_gateway():
		result_why = "NO ROUTER ANSWERED (UPNP OFF?)"
	else:
		var mapped := upnp.add_port_mapping(port, port, "Crazy Legs Mundell", "UDP", 0)
		if mapped != UPNP.UPNP_RESULT_SUCCESS:
			result_why = "THE ROUTER SAID NO (%d)" % mapped
		else:
			result_state = "open"
			result_external = upnp.query_external_address()
	_mutex.lock()
	_upnp = upnp if result_state == "open" else null
	state = result_state
	why = result_why
	external = result_external
	_mutex.unlock()


## True when the router's outside address is one a provider shares (CGNAT,
## 100.64.0.0/10) or a private one: friends outside cannot reach it.
func shared_address() -> bool:
	return external != "" and NetPlay.private_address(external)


## Takes the mapping down (waits for a discovery still under way).
func close() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	_mutex.lock()
	var upnp := _upnp
	_upnp = null
	_mutex.unlock()
	if upnp != null:
		upnp.delete_port_mapping(port, "UDP")
	state = "idle"


## Has the thread finished (so close() will not wait)?
func settled() -> bool:
	return state != "asking"
