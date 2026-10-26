// Layered Fog
// Two thin density strata mimic temperature inversion and stacked valley mist.
// Target: FogVolume.material with volumetric fog enabled (Forward+ renderer). Not a mesh material.
shader_type fog;
uniform float density : hint_range(0,5)=1;
uniform vec4 fog_color : source_color=vec4(0.6,0.72,0.85,1);
void fog() {
    float h=UVW.y;
    float layers=exp(-pow((h-0.25)*18.0,2.0))+0.65*exp(-pow((h-0.65)*14.0,2.0));
    DENSITY=density*layers;
    ALBEDO=mix(vec3(0.5,0.65,0.8),vec3(0.9,0.65,0.45),h);
}
