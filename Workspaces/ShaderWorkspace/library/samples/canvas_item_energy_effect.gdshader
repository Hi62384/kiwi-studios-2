// Energy Effect
// Oscillating radial plasma filaments for magical energy and charged icons.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
void fragment() {
    vec2 p=UV-0.5;
    float r=length(p);
    float a=atan(p.y,p.x);
    float wave=abs(sin(r*35.0-TIME*5.0+sin(a*6.0+TIME)*2.0));
    float energy=pow(1.0-wave,8.0)*(1.0-smoothstep(0.25,0.5,r));
    COLOR=vec4(vec3(0.1,0.5,1)*energy*3.0,energy);
}
