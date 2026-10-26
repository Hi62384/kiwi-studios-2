// Wobble
// Rocking UV rotation around the center for lively icons and jelly-like sprites.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
uniform float speed : hint_range(0,12)=3;
uniform float amount : hint_range(0,0.5)=0.16;
void fragment() {
    vec2 p=UV-0.5;
    float a=sin(TIME*speed)*amount;
    vec2 uv=mat2(vec2(cos(a),sin(a)),vec2(-sin(a),cos(a)))*p+0.5;
    COLOR=texture(TEXTURE,uv);
}
