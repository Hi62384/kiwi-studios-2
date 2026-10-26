// Falling Leaves
// Broad autumn particles flutter, tumble and drift while falling.
// Target: GPUParticles3D.process_material (adapt world units to pixels for GPUParticles2D). Use a unit draw mesh, vertex-color draw material and billboard_keep_scale=true. Not a particle draw-pass material.
shader_type particles;
render_mode disable_velocity;
// Integer mixing avoids precision loss from large RANDOM_SEED values.
float particle_random(uint value) {
    value=((value >> uint(16)) ^ value)*uint(73244475);
    value=((value >> uint(16)) ^ value)*uint(73244475);
    value=(value >> uint(16)) ^ value;
    return float(value % uint(65536))/65535.0;
}
float particle_hash(float p) {
    return fract(sin(p*127.1)*43758.5453);
}
// Particle age is stored in CUSTOM.y (seconds); CUSTOM.z is a stable random phase.
// disable_velocity prevents Godot from integrating VELOCITY a second time.
void start() {
    float h=particle_random(INDEX ^ RANDOM_SEED);
    CUSTOM=vec4(0,0,h*TAU,0);
    TRANSFORM=EMISSION_TRANSFORM;
    TRANSFORM[3].xyz+=vec3((h-0.5)*2.0,1.8,(particle_hash(h+8.0)-0.5)*2.0);
    VELOCITY=vec3(0,-0.3-h*0.2,0);
    COLOR=vec4(mix(vec3(0.3,0.2,0.03),vec3(0.85,0.4,0.05),h),1);
}
void process() {
    CUSTOM.y+=DELTA;
    float age=clamp(CUSTOM.y/max(LIFETIME,0.001),0.0,1.0);
    VELOCITY.x=sin(CUSTOM.y*2.0+CUSTOM.z)*0.6;
    float a=CUSTOM.y*3.0+CUSTOM.z;
    TRANSFORM[0].xyz=vec3(cos(a),sin(a),0)*0.12;
    TRANSFORM[1].xyz=vec3(-sin(a),cos(a),0)*0.065;
    TRANSFORM[2].xyz=vec3(0,0,0.08);
    COLOR.a=(1.0-smoothstep(0.8,1.0,age));
    TRANSFORM[3].xyz+=VELOCITY*DELTA;
    if(age>=1.0) {
        ACTIVE=false;
    }
}
