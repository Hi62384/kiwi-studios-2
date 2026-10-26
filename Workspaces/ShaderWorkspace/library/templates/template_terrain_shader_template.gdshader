// Terrain Shader Template
// Separated slope and altitude masks provide a structured terrain starting point.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
uniform float snow_height : hint_range(-2,10)=0.4;
varying vec3 world_pos;
varying vec3 world_normal;
void vertex() {
    world_pos=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;
    world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);
}
void fragment() {
    // Replace colors with texture samples while retaining slope/height masks.
    float slope=1.0-abs(world_normal.y);
    float summit=smoothstep(snow_height-0.3,snow_height+0.3,world_pos.y);
    vec3 ground=mix(vec3(0.12,0.3,0.05),vec3(0.3,0.26,0.22),smoothstep(0.2,0.6,slope));
    ALBEDO=mix(ground,vec3(0.95),summit*(1.0-slope));
    ROUGHNESS=0.9;
}
