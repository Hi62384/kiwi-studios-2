// Chromatic Aberration
// Lens-like radial separation of red and blue channels increases toward screen edges.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
// Place on a full-screen ColorRect AFTER the scene; enable a BackBufferCopy when stacking screen effects.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float strength : hint_range(0,0.1)=0.02;
void fragment() {
    vec2 direction=SCREEN_UV-0.5;
    vec2 shift=direction*strength;
    vec3 c;
    c.r=texture(screen_texture,SCREEN_UV+shift).r;
    c.g=texture(screen_texture,SCREEN_UV).g;
    c.b=texture(screen_texture,SCREEN_UV-shift).b;
    COLOR=vec4(c,1);
}
