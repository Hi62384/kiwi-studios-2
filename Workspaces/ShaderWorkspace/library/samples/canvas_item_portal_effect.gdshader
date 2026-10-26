// Portal Effect
// Rotating spiral aperture enclosed by a bright circular energy rim.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
void fragment() {
    vec2 p=UV-0.5;
    float r=length(p);
    float a=atan(p.y,p.x);
    float ring=exp(-abs(r-0.34)*38.0);
    float spiral=pow(0.5+0.5*sin(a*5.0-r*30.0+TIME*3.0),5.0);
    float mask=1.0-smoothstep(0.34,0.43,r);
    vec3 c=mix(vec3(0.04,0.01,0.18),vec3(0.6,0.12,1),spiral*0.6)+ring*vec3(0.4,0.8,1)*2.0;
    COLOR=vec4(c,mask);
}
