// Sparks
// Ballistic spark fountain cools from yellow to red under gravity.
// Target: GPUParticles3D.process_material (adapt world units to pixels for GPUParticles2D). Use a unit draw mesh, vertex-color draw material and billboard_keep_scale=true. Not a particle draw-pass material.
shader_type particles;
render_mode disable_velocity;
uniform float speed : hint_range(0.1,5)=1.2;
uniform float gravity : hint_range(0,20)=6;
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
    VELOCITY=vec3(cos(h*TAU),1.5+particle_hash(h+3.0)*2.0,sin(h*TAU))*speed;
    TRANSFORM[0].xyz*=0.04;
    TRANSFORM[1].xyz*=0.04;
    TRANSFORM[2].xyz*=0.04;
    COLOR=vec4(1,0.65,0.12,1);
}
void process() {
    CUSTOM.y+=DELTA;
    float age=clamp(CUSTOM.y/max(LIFETIME,0.001),0.0,1.0);
    VELOCITY.y-=gravity*DELTA;
    COLOR.rgb=mix(vec3(1,0.85,0.3),vec3(0.8,0.1,0.01),age);
    COLOR.a=1.0-age;
    TRANSFORM[3].xyz+=VELOCITY*DELTA;
    if(age>=1.0) {
        ACTIVE=false;
    }
}
