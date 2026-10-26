// Rounded Corners
// Antialiased signed-distance rounded rectangle clipping for images and panels.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
uniform float radius : hint_range(0,0.5)=0.18;
void fragment() {
    vec2 q=abs(UV-0.5)-(vec2(0.5)-radius);
    float d=length(max(q,vec2(0)))+min(max(q.x,q.y),0.0)-radius;
    vec4 c=texture(TEXTURE,UV);
    COLOR=vec4(c.rgb,c.a*(1.0-smoothstep(-0.005,0.005,d)));
}
