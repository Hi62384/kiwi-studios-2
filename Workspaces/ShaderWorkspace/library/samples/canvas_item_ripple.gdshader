// Ripple
// Concentric radial UV waves expand from an editable center.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
uniform vec2 center=vec2(0.5);
uniform float frequency : hint_range(1,100)=45;
uniform float speed : hint_range(0,20)=6;
uniform float amplitude : hint_range(0,0.1)=0.018;
void fragment() {
    vec2 p=UV-center;
    float r=length(p);
    vec2 dir=p/max(r,0.001);
    COLOR=texture(TEXTURE,UV+dir*sin(r*frequency-TIME*speed)*amplitude*exp(-r*2.0));
}
