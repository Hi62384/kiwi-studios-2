// Screen Distortion Template
// Screen-space UV displacement with bounded sampling and editable motion.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
// Place on a full-screen ColorRect AFTER the scene; enable a BackBufferCopy when stacking screen effects.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float frequency : hint_range(1,100)=35;
uniform float speed : hint_range(0,10)=2;
uniform float strength : hint_range(0,0.1)=0.01;
void fragment() {
    // Distortion is in normalized screen units; clamp to avoid edge wrapping.
    vec2 distortion=vec2(sin(UV.y*frequency+TIME*speed),0)*strength;
    vec2 screen_uv=clamp(SCREEN_UV+distortion,vec2(0),vec2(1));
    COLOR=texture(screen_texture,screen_uv);
}
