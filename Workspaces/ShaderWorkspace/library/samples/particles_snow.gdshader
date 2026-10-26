// Snow
// Slow falling flakes sway laterally with independently phased wind.
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
    TRANSFORM[3].xyz+=vec3((h-0.5)*3.0,1.7,(particle_hash(h+3.0)-0.5)*2.0);
    VELOCITY=vec3(0,-0.3-h*0.4,0);
    TRANSFORM[0].xyz*=0.045;
    TRANSFORM[1].xyz*=0.045;
    TRANSFORM[2].xyz*=0.045;
}
void process() {
    CUSTOM.y+=DELTA;
    float age=clamp(CUSTOM.y/max(LIFETIME,0.001),0.0,1.0);
    VELOCITY.x=sin(CUSTOM.y*2.0+CUSTOM.z)*0.25;
    VELOCITY.z=cos(CUSTOM.y+CUSTOM.z)*0.08;
    COLOR=vec4(0.9,0.96,1,(1.0-smoothstep(0.75,1.0,age)));
    TRANSFORM[3].xyz+=VELOCITY*DELTA;
    if(age>=1.0) {
        ACTIVE=false;
    }
}
