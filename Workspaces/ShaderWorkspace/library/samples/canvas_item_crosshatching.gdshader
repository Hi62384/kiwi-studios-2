// Crosshatching
// Three directional hatch layers accumulate as source luminance becomes darker.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
uniform float lines : hint_range(10,150)=65;
void fragment() {
    vec4 c=texture(TEXTURE,UV);
    float l=dot(c.rgb,vec3(0.3,0.59,0.11));
    vec2 p=UV*lines;
    float a=step(0.82,fract(p.x+p.y));
    float b=step(0.84,fract(p.x-p.y));
    float d=step(0.86,fract(p.x*1.4));
    float ink=max(a*step(l,0.8),max(b*step(l,0.5),d*step(l,0.25)));
    COLOR=vec4(mix(vec3(0.95,0.92,0.8),vec3(0.09,0.07,0.05),ink),c.a);
}
