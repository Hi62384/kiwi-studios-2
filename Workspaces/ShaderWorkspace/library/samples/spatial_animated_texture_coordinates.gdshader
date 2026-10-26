// Animated Texture Coordinates
// Animated UV coordinates move a structured tile pattern over fixed geometry.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
uniform vec2 velocity=vec2(0.08,0.03);
void vertex() {
    UV+=velocity*TIME;
}
void fragment() {
    vec2 q=fract(UV*6.0);
    float grid=step(0.08,q.x)*step(0.08,q.y);
    ALBEDO=mix(vec3(0.03,0.06,0.12),vec3(0.1,0.7,0.8),grid);
    ROUGHNESS=0.45;
}
