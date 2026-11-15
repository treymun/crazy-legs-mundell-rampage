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


## Show these sprites (each an enemy's, with a model) and no others. Returns
## the materials first used this frame (the view hands them its numbers).
func show_actors(
	sprites: Array, level: LevelData, clock: float, lost: Dictionary
) -> Array[ShaderMaterial]:
	var fresh: Array[ShaderMaterial] = []
	var seen := {}
	for item: Variant in sprites:
		var s := item as View.Sprite
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
		view.lose(lost.get(e, []))
	for id: int in _shown.keys():
		if not seen.has(id):
			(_shown[id] as ActorView).queue_free()
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
