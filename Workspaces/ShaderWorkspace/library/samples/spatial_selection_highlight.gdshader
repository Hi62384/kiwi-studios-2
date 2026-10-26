// Selection Highlight
// Pulsed rim-and-fill highlight communicates a selected mesh without changing its shape.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
uniform vec4 base_color : source_color=vec4(0.12,0.25,0.2,1);
uniform vec4 highlight : source_color=vec4(0.2,1,0.5,1);
uniform float energy : hint_range(0,4)=1.8;
void fragment() {
    float rim=pow(1.0-max(dot(NORMAL,VIEW),0.0),2.0);
    float pulse=0.6+0.4*sin(TIME*3.0);
    ALBEDO=base_color.rgb;
    EMISSION=highlight.rgb*(rim+pulse*0.12)*energy;
    ROUGHNESS=0.5;
}
