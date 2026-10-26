// Particle Shader Template
// Complete initialization, integration, fade and lifetime handling for GPU particle processes.
// Target: GPUParticles3D.process_material (adapt world units to pixels for GPUParticles2D). Use a unit draw mesh, vertex-color draw material and billboard_keep_scale=true. Not a particle draw-pass material.
shader_type particles;
render_mode disable_velocity;
uniform vec3 initial_velocity=vec3(0.3,1,0);
uniform vec3 acceleration=vec3(0,-0.3,0);
uniform vec4 particle_color : source_color=vec4(0.3,0.8,1,1);
uniform float size : hint_range(0.01,0.5)=0.06;
uniform float spread : hint_range(0,2)=0.4;
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
void start() {
    TRANSFORM=EMISSION_TRANSFORM;
    float random_phase=particle_random(INDEX ^ RANDOM_SEED)*TAU;
    VELOCITY=initial_velocity+vec3(cos(random_phase),0,sin(random_phase))*spread;
    COLOR=particle_color;
    CUSTOM=vec4(0);
    TRANSFORM[0].xyz*=size;
    TRANSFORM[1].xyz*=size;
    TRANSFORM[2].xyz*=size;
}
void process() {
    // With disable_velocity, this function owns integration exactly once.
    CUSTOM.y+=DELTA;
    VELOCITY+=acceleration*DELTA;
    TRANSFORM[3].xyz+=VELOCITY*DELTA;
    COLOR.a=particle_color.a*(1.0-clamp(CUSTOM.y/max(LIFETIME,0.001),0.0,1.0));
    if(CUSTOM.y>=LIFETIME) {
        ACTIVE=false;
    }
}
