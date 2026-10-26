// Saturation
// Luminance-based desaturation or oversaturation; grayscale by default.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
uniform float saturation : hint_range(0,3)=0.0;
void fragment() {
    vec4 c=texture(TEXTURE,UV);
    float y=dot(c.rgb,vec3(0.2126,0.7152,0.0722));
    COLOR=vec4(mix(vec3(y),c.rgb,saturation),c.a);
}
