## TILT AIM: turning and tipping the phone turns and tips the view, on top of
## the thumb drag. Reads the gyroscope: Godot's own on an Android build (which
## hands its rates over in screen axes), the page's devicemotion events in a
## browser (device axes, so the screen's rotation is taken out here). Nothing
## on the agent side has a phone: how it feels, and its signs on an iPhone,
## are untested.
class_name TiltAim
extends RefCounted

static var _listening := false


## Start listening in a browser. iOS asks the player first, and only from a
## tap, so this is called when the setting is switched on (from the tap that
## did it) and again when play starts.
static func enable() -> void:
	if not OS.has_feature("web") or _listening:
		return
	_listening = true
	(
		JavaScriptBridge
		. eval(
			"""
		(function () {
			window.__clmrTilt = [0, 0, 0];
			var listen = function () {
				window.addEventListener('devicemotion', function (e) {
					var r = e.rotationRate || {};
					window.__clmrTilt = [r.beta || 0, r.gamma || 0, r.alpha || 0];
				});
			};
			if (typeof DeviceMotionEvent !== 'undefined'
				&& typeof DeviceMotionEvent.requestPermission === 'function') {
				DeviceMotionEvent.requestPermission().then(function (answer) {
					if (answer === 'granted') listen();
				}).catch(function () {});
			} else {
				listen();
			}
		})();
		""",
			true
		)
	)


## Radians a second the view should turn right (x) and tip up (y).
static func rates() -> Vector2:
	if OS.has_feature("web"):
		if not _listening:
			return Vector2.ZERO
		var raw = JavaScriptBridge.eval(
			(
				"(window.__clmrTilt || [0,0,0]).join(',') + ',' + "
				+ "((screen.orientation && screen.orientation.angle) || window.orientation || 0)"
			),
			true
		)
		var parts := String(raw).split(",")
		if parts.size() < 4:
			return Vector2.ZERO
		var spin := Vector3(float(parts[0]), float(parts[1]), float(parts[2])) * (PI / 180.0)
		var turned := posmod(int(parts[3]), 360)
		var right := Vector3(1, 0, 0)
		var up := Vector3(0, 1, 0)
		if turned == 90:
			right = Vector3(0, -1, 0)
			up = Vector3(1, 0, 0)
		elif turned == 180:
			right = Vector3(-1, 0, 0)
			up = Vector3(0, -1, 0)
		elif turned == 270:
			right = Vector3(0, 1, 0)
			up = Vector3(-1, 0, 0)
		return Vector2(-spin.dot(up), spin.dot(right))
	var gyro := Input.get_gyroscope()
	return Vector2(-gyro.y, gyro.x)
