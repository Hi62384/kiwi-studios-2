// Dithered Transparency
// Screen-door opaque dithering fades surfaces while retaining depth writes.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
uniform float opacity : hint_range(0,1)=0.55;
uniform vec4 tint : source_color=vec4(0.35,0.7,0.9,1);
void fragment() {
    float threshold=fract(dot(floor(FRAGCOORD.xy),vec2(0.75487766,0.56984029)));
    if(threshold>opacity) {
        discard;
    }
    ALBEDO=tint.rgb;
    ROUGHNESS=0.5;
}
