// Animated Fog
// Crossing traveling density waves create broad moving mist.
// Target: FogVolume.material with volumetric fog enabled (Forward+ renderer). Not a mesh material.
shader_type fog;
uniform float density : hint_range(0,5)=1;
uniform vec4 fog_color : source_color=vec4(0.6,0.72,0.85,1);
void fog() {
    vec3 p=WORLD_POSITION;
    float w=0.5+0.5*sin(p.x*3.0+TIME)*sin(p.z*2.0-TIME*0.7);
    DENSITY=density*w;
    ALBEDO=fog_color.rgb;
}
