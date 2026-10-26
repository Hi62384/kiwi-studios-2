// Fresnel
// Schlick Fresnel reflectance approximation shifts appearance at grazing angles.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
uniform float base_reflectance : hint_range(0,1)=0.04;
void fragment() {
    float f=base_reflectance+(1.0-base_reflectance)*pow(1.0-max(dot(NORMAL,VIEW),0.0),5.0);
    ALBEDO=mix(vec3(0.03,0.09,0.15),vec3(0.5,0.9,1),f);
    METALLIC=0.6;
    ROUGHNESS=0.15;
}
