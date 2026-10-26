// Water Surface
// Crossing waves and sharp moving caustic ridges generate a complete water texture.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
uniform vec4 deep : source_color=vec4(0.02,0.15,0.3,1);
uniform vec4 shallow : source_color=vec4(0.08,0.65,0.72,1);
void fragment() {
    vec2 p=UV*8.0;
    float h=sin(p.x+TIME)*sin(p.y*1.3-TIME*0.8);
    float caustic=pow(1.0-abs(sin(p.x+p.y+h*2.0)),12.0);
    COLOR=vec4(mix(deep.rgb,shallow.rgb,h*0.5+0.5)+caustic*0.3,1);
}
