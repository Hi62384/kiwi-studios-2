// Basic Fog
// Uniform participating medium inside a bounded FogVolume; requires Forward+ volumetric fog.
// Target: FogVolume.material with volumetric fog enabled (Forward+ renderer). Not a mesh material.
shader_type fog;
uniform float density : hint_range(0,5)=1;
uniform vec4 fog_color : source_color=vec4(0.6,0.72,0.85,1);
void fog() {
    DENSITY=density;
    ALBEDO=fog_color.rgb;
}
