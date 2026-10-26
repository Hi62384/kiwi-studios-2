// Wave Distortion
// Sinusoidal horizontal displacement creates a flag or underwater sprite wobble.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
uniform float frequency : hint_range(1,60)=20;
uniform float speed : hint_range(0,8)=2;
uniform float amplitude : hint_range(0,0.2)=0.035;
void fragment() {
    vec2 uv=UV;
    uv.x+=sin(UV.y*frequency+TIME*speed)*amplitude;
    COLOR=texture(TEXTURE,uv);
}
