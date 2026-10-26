// Colored Fog
// Two-color scattering and mild self-emission for stylized magical atmosphere.
// Target: FogVolume.material with volumetric fog enabled (Forward+ renderer). Not a mesh material.
shader_type fog;
uniform float density : hint_range(0,5)=0.75;
uniform vec4 lower_color : source_color=vec4(0.2,0.08,0.6,1);
uniform vec4 upper_color : source_color=vec4(0.05,0.7,0.85,1);
uniform float emission : hint_range(0,2)=0.12;
void fog() {
    float t=clamp(UVW.y,0.0,1.0);
    DENSITY=density;
    ALBEDO=mix(lower_color.rgb,upper_color.rgb,t);
    EMISSION=ALBEDO*emission;
}
