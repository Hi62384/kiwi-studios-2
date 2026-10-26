// Color Palette Swap
// Four-stop luminance palette for handheld-console and limited-color artwork.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
uniform vec4 ink : source_color=vec4(0.07,0.13,0.17,1);
uniform vec4 shade : source_color=vec4(0.18,0.35,0.36,1);
uniform vec4 mid : source_color=vec4(0.48,0.66,0.5,1);
uniform vec4 paper : source_color=vec4(0.91,0.9,0.68,1);
void fragment() {
    vec4 c=texture(TEXTURE,UV);
    float l=dot(c.rgb,vec3(0.299,0.587,0.114));
    vec3 p=l<0.25?ink.rgb:(l<0.5?shade.rgb:(l<0.75?mid.rgb:paper.rgb));
    COLOR=vec4(p,c.a);
}
