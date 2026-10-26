// Color Replacement
// Soft color-key replacement in RGB distance, useful for palette variants.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
uniform vec4 key : source_color=vec4(0.9,0.55,0.4,1);
uniform vec4 replacement : source_color=vec4(0.8,0.2,0.55,1);
uniform float tolerance : hint_range(0,1)=0.3;
void fragment() {
    vec4 c=texture(TEXTURE,UV);
    float m=1.0-smoothstep(tolerance,tolerance+0.08,distance(c.rgb,key.rgb));
    COLOR=vec4(mix(c.rgb,replacement.rgb,m),c.a);
}
