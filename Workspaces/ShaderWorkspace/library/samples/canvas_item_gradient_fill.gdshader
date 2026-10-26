// Gradient Fill
// Two-stop directional gradient with independently editable endpoints.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
uniform vec4 color_a : source_color = vec4(0.08,0.18,0.5,1);
uniform vec4 color_b : source_color = vec4(1,0.62,0.22,1);
uniform float angle : hint_range(-3.14,3.14)=1.57;
void fragment() {
    float t=clamp(dot(UV-0.5,vec2(cos(angle),sin(angle)))+0.5,0.0,1.0);
    COLOR=mix(color_a,color_b,t);
}
