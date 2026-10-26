// Height Based Fog
// Exponential density falloff creates ground-hugging mist within the volume.
// Target: FogVolume.material with volumetric fog enabled (Forward+ renderer). Not a mesh material.
shader_type fog;
uniform float density : hint_range(0,5)=1;
uniform vec4 fog_color : source_color=vec4(0.6,0.72,0.85,1);
uniform float falloff : hint_range(0,12)=4;
void fog() {
    float h=(WORLD_POSITION.y-OBJECT_POSITION.y)/max(SIZE.y,0.01)+0.5;
    DENSITY=density*exp(-max(h,0.0)*falloff);
    ALBEDO=fog_color.rgb;
}
