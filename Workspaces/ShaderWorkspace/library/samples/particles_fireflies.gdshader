// Fireflies
// Wandering bioluminescent motes pulse independently with warm green flashes.
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
    TRANSFORM[3].xyz+=vec3(h-0.5,particle_hash(h+4.0)-0.5,particle_hash(h+6.0)-0.5)*2.0;
    TRANSFORM[0].xyz*=0.055;
    TRANSFORM[1].xyz*=0.055;
    TRANSFORM[2].xyz*=0.055;
}
void process() {
    CUSTOM.y+=DELTA;
    float age=clamp(CUSTOM.y/max(LIFETIME,0.001),0.0,1.0);
    VELOCITY=vec3(sin(CUSTOM.y*1.1+CUSTOM.z),cos(CUSTOM.y*1.3-CUSTOM.z),cos(CUSTOM.y*0.8+CUSTOM.z))*0.18;
    float blink=pow(0.5+0.5*sin(CUSTOM.y*3.0+CUSTOM.z),5.0);
    COLOR=vec4(0.6,1,0.08,blink*sin(age*PI));
    TRANSFORM[3].xyz+=VELOCITY*DELTA;
    if(age>=1.0) {
        ACTIVE=false;
    }
}
