## The enemies and bosses of the 3D view that have a rigged model
## (ActorModels): each sprite the game lists for an enemy (View.Sprite
## `who`) is drawn as that enemy's scene instead (ActorView,
## scenes/actors/<kind>.tscn), which poses itself from the sprite.
class_name ActorLayer3D
extends Node3D

var models: ActorModels
## enemy instance id -> ActorView
var _shown: Dictionary = {}


func _init(p_models: ActorModels) -> void:
	models = p_models


## The model kind an enemy is drawn with ("" when none).
func kind_of(e: Enemy) -> String:
	if models.has(e.kind):
		return e.kind
	var stem := Variants.stem(e.kind)
	return stem if models.has(stem) else ""


## Whether enemy `e`'s sprite `s` is drawn as its model. A kind whose body at
## rest is a build of its own that the model's parts cannot make (fit.json
## "down_cel": the derby champ's burnt-out wreck, the swamp king's sunk boat)
## keeps its cel for that.
func takes(s: View.Sprite, e: Enemy) -> bool:
	var kind := kind_of(e)
	if kind == "":
		return false
	var info: Dictionary = models.kinds[kind]
	var own_cel: bool = info.get("down_cel", false)
	if own_cel and ActorView.pose_of(s.image, Variants.stem(e.kind))[0] == "down":
		return false
	return true


## Show these sprites (each an enemy's, with a model) and no others. Returns
## the materials first used this frame (the view hands them its numbers).
func show_actors(
	sprites: Array, level: LevelData, clock: float, lost: Dictionary
) -> Array[ShaderMaterial]:
	var fresh: Array[ShaderMaterial] = []
	var seen := {}
	for s: View.Sprite in sprites:
		var e := s.who as Enemy
		var kind := kind_of(e)
		var id := e.get_instance_id()
		seen[id] = true
		var view: ActorView = _shown.get(id)
		if view == null or view.kind != kind:
			if view != null:
				view.queue_free()
			_shown.erase(id)
			view = _make(kind, fresh)
			if view == null:
				continue
			_shown[id] = view
		view.show_as(s, e, level, clock)
		var gone: Array = lost.get(e, [])
		view.lose(gone)
	for id: int in _shown.keys():
		if not seen.has(id):
			var old: ActorView = _shown[id]
			old.queue_free()
			_shown.erase(id)
	return fresh


func _make(kind: String, fresh: Array[ShaderMaterial]) -> ActorView:
	var packed := models.scene(kind)
	if packed == null:
		return null
	var had := models.materials().size()
	var view := packed.instantiate() as ActorView
	if view == null:
		return null
	if not view.setup(models):
		view.free()
		return null
	if models.materials().size() > had:
		fresh.append(models.material(kind))
	add_child(view)
	return view
