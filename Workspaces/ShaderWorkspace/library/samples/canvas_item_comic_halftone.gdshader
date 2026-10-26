// Comic Halftone
// Luminance-controlled dot radii reproduce a print halftone screen.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
uniform float dots : hint_range(8,100)=45;
uniform vec4 ink_color : source_color=vec4(0.1,0.06,0.17,1);
uniform vec4 paper : source_color=vec4(1,0.91,0.7,1);
void fragment() {
    vec4 c=texture(TEXTURE,UV);
    float l=dot(c.rgb,vec3(0.299,0.587,0.114));
    vec2 p=UV*dots;
    float d=length(fract(p)-0.5);
    float radius=sqrt(1.0-l)*0.6;
    float ink=1.0-smoothstep(radius-0.015,radius+0.015,d);
    COLOR=vec4(mix(paper.rgb,ink_color.rgb,ink),c.a);
}
