// Water Shader Template
// Analytic wave displacement and surface shading ready for foam and depth extensions.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
uniform vec4 water_color : source_color=vec4(0.04,0.35,0.45,1);
uniform float amplitude : hint_range(0,0.5)=0.08;
uniform float frequency : hint_range(0.1,15)=5;
uniform float speed : hint_range(0,8)=1.5;
void vertex() {
    // Use a subdivided plane; normals use the derivative of the same height wave.
    float phase=VERTEX.x*frequency+TIME*speed;
    VERTEX.y+=sin(phase)*amplitude;
    NORMAL=normalize(vec3(-cos(phase)*frequency*amplitude,1,0));
}
void fragment() {
    ALBEDO=water_color.rgb;
    ROUGHNESS=0.12;
    METALLIC=0.2;
}
