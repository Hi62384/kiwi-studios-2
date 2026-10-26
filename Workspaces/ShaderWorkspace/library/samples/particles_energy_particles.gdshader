// Energy Particles
// Accelerating spiral attraction draws energy sparks inward toward an emitter.
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
    float a=h*TAU;
    TRANSFORM[3].xyz+=vec3(cos(a),sin(a),0)*1.2;
    VELOCITY=vec3(-cos(a),-sin(a),0)*0.5;
    TRANSFORM[0].xyz*=0.04;
    TRANSFORM[1].xyz*=0.04;
    TRANSFORM[2].xyz*=0.04;
}
void process() {
    CUSTOM.y+=DELTA;
    float age=clamp(CUSTOM.y/max(LIFETIME,0.001),0.0,1.0);
    vec3 p=TRANSFORM[3].xyz-EMISSION_TRANSFORM[3].xyz;
    VELOCITY+=(-p*1.4+vec3(-p.y,p.x,0)*1.2)*DELTA;
    COLOR=vec4(0.05,0.6,1,1.0-age);
    TRANSFORM[3].xyz+=VELOCITY*DELTA;
    if(age>=1.0) {
        ACTIVE=false;
    }
}
