// Object Interaction Ripples
// Object-local radial ripples with decaying amplitude and analytic normal response.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
uniform vec2 impact_position=vec2(0);
uniform float frequency : hint_range(1,30)=12;
uniform float speed : hint_range(0,12)=4;
uniform float strength : hint_range(0,0.3)=0.08;
uniform float falloff : hint_range(0.1,5)=1.5;
void vertex() {
    float r=length(VERTEX.xz-impact_position);
    float phase=r*frequency-TIME*speed;
    float h=sin(phase)*exp(-r*falloff)*strength;
    VERTEX.y+=h;
    vec2 dir=(VERTEX.xz-impact_position)/max(r,0.001);
    float derivative=exp(-r*falloff)*strength*(frequency*cos(phase)-falloff*sin(phase));
    NORMAL=normalize(vec3(-dir.x*derivative,1,-dir.y*derivative));
}
void fragment() {
    ALBEDO=vec3(0.025,0.3,0.4);
    ROUGHNESS=0.12;
}
