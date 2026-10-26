// Smoke
// Expanding gray plumes drift upward, fade in and dissolve near the end of life.
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
    TRANSFORM[3].xz+=vec2(h-0.5,particle_hash(h+7.0)-0.5)*0.5;
    VELOCITY=vec3(0.08,0.4+h*0.2,0);
    TRANSFORM[0].xyz*=0.12;
    TRANSFORM[1].xyz*=0.12;
    TRANSFORM[2].xyz*=0.12;
}
void process() {
    CUSTOM.y+=DELTA;
    float age=clamp(CUSTOM.y/max(LIFETIME,0.001),0.0,1.0);
    VELOCITY.x+=sin(CUSTOM.z+CUSTOM.y)*DELTA*0.08;
    float expansion=1.0+DELTA*0.45;
    TRANSFORM[0].xyz*=expansion;
    TRANSFORM[1].xyz*=expansion;
    TRANSFORM[2].xyz*=expansion;
    COLOR=vec4(vec3(0.22+age*0.4),sin(age*PI)*0.35);
    TRANSFORM[3].xyz+=VELOCITY*DELTA;
    if(age>=1.0) {
        ACTIVE=false;
    }
}
