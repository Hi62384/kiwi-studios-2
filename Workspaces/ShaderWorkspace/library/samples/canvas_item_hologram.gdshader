// Hologram
// Translucent cyan projection with fine scanlines and a traveling exposure band.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
uniform vec4 tint : source_color=vec4(0.05,0.75,1,1);
void fragment() {
    vec4 c=texture(TEXTURE,UV);
    float scan=0.6+0.4*sin(UV.y*180.0+TIME*4.0);
    float sweep=pow(max(0.0,sin(UV.y*7.0-TIME*2.0)),16.0);
    COLOR=vec4(tint.rgb*(0.5+c.rgb)*scan+sweep*0.5,c.a*(0.65+0.2*scan));
}
