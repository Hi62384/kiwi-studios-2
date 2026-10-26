// Wind Deformed Grass
// Bottom-anchored grass cards sway with a quadratic tip weight.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
uniform float strength : hint_range(0,1)=0.25;
void vertex() {
    float anchor=pow(clamp(1.0-UV.y,0.0,1.0),2.0);
    VERTEX.x+=sin(TIME*2.0+VERTEX.x*4.0)*strength*anchor;
}
void fragment() {
    float blade=1.0-smoothstep(0.08,0.45,abs(UV.x-0.5)/(max(UV.y,0.05)));
    ALBEDO=mix(vec3(0.13,0.25,0.02),vec3(0.4,0.65,0.08),1.0-UV.y);
    ALPHA=blade;
    ALPHA_SCISSOR_THRESHOLD=0.5;
    ROUGHNESS=0.9;
}
