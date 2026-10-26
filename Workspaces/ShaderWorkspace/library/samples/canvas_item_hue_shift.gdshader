// Hue Shift
// Continuous hue-axis rotation preserves neutral grays while shifting chroma.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
uniform float hue : hint_range(0,1)=0.2;
void fragment() {
    vec4 c=texture(TEXTURE,UV);
    vec3 axis=normalize(vec3(1));
    float a=hue*TAU;
    vec3 shifted=c.rgb*cos(a)+cross(axis,c.rgb)*sin(a)+axis*dot(axis,c.rgb)*(1.0-cos(a));
    COLOR=vec4(clamp(shifted,vec3(0),vec3(1)),c.a);
}
