// Multicolor Gradient
// A continuous three-channel cosine palette, useful for spectrum bars and ramps.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
void fragment() {
    vec3 c=0.5+0.5*cos(TAU*(UV.x+vec3(0.0,0.33,0.67)));
    COLOR=vec4(mix(c,vec3(1),UV.y*0.35),1);
}
