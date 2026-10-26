// Localized Fog
// Soft ellipsoidal density region fades to zero before the volume boundary.
// Target: FogVolume.material with volumetric fog enabled (Forward+ renderer). Not a mesh material.
shader_type fog;
uniform float density : hint_range(0,5)=1;
uniform vec4 fog_color : source_color=vec4(0.6,0.72,0.85,1);
void fog() {
    vec3 p=(UVW-0.5)*2.0;
    float sphere=1.0-smoothstep(0.3,1.0,length(p));
    DENSITY=density*sphere;
    ALBEDO=fog_color.rgb;
}
