// Energy Barrier
// Traveling interference bands and a fine lattice animate a translucent barrier.
// Target: MeshInstance3D surface material or material override; UVs required unless stated otherwise.
shader_type spatial;
render_mode cull_disabled;
void fragment() {
    float band=pow(0.5+0.5*sin(UV.y*40.0-TIME*4.0+sin(UV.x*12.0)*2.0),10.0);
    float lattice=step(0.9,sin(UV.x*70.0)*sin(UV.y*70.0));
    ALBEDO=vec3(0.2,0.04,0.5);
    EMISSION=vec3(0.45,0.1,1)*(band*2.0+lattice);
    ALPHA=0.15+band*0.55+lattice*0.2;
}
