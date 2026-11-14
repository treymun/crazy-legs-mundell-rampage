// A sprite of the 3D view (sprite_layer.gd): a picture from an art slot, as
// the old renderer drew it. A billboard stands parallel to the view plane; a
// board (plane sprite) is fixed in the world. Light: light_at(distance, the
// cell's light) stepped in 32nds, bodies no darker than .58 - .021 d, glowing
// sprites at 1.1; the area's tint; a hit washes the lit colour toward hot
// white. Translucent sprites blend by their alpha (sprite_blend material).
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

#include "res://src/view3d/sprite_body.gdshaderinc"
