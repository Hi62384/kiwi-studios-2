// Moving Gradient
// Traveling color bands for animated UI and rhythmic backdrops.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
uniform vec2 direction=vec2(1,0.4);
uniform float speed : hint_range(0,8)=1.5;
uniform vec4 color_a : source_color=vec4(0.1,0.04,0.4,1);
uniform vec4 color_b : source_color=vec4(0.1,0.95,0.8,1);
void fragment() {
    float t=0.5+0.5*sin(dot(UV,direction)*TAU-TIME*speed);
    COLOR=mix(color_a,color_b,t);
}
