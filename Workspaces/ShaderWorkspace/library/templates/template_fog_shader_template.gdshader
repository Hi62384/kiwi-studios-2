// Fog Shader Template
// Forward+ bounded fog with explicit density, scattering and emission outputs.
// Target: FogVolume.material with volumetric fog enabled (Forward+ renderer). Not a mesh material.
shader_type fog;
uniform float density : hint_range(0,5)=1;
uniform vec4 fog_color : source_color=vec4(0.6,0.72,0.85,1);
void fog() {
    // UVW covers the FogVolume. A soft boundary prevents hard cuboid edges.
    vec3 centered=abs(UVW*2.0-1.0);
    float edge=1.0-smoothstep(0.6,1.0,max(centered.x,max(centered.y,centered.z)));
    DENSITY=density*edge;
    ALBEDO=fog_color.rgb;
    EMISSION=vec3(0);
}
