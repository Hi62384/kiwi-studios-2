// Glass
// Lightweight transparent glass with stronger grazing-angle reflections; no scene refraction.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
render_mode cull_disabled,depth_draw_always;
uniform vec4 tint : source_color=vec4(0.65,0.85,0.95,1);
uniform float opacity : hint_range(0,1)=0.16;
void fragment() {
    float f=pow(1.0-max(dot(NORMAL,VIEW),0.0),4.0);
    ALBEDO=tint.rgb;
    ROUGHNESS=0.04;
    METALLIC=0.1;
    ALPHA=mix(opacity,0.85,f);
}
