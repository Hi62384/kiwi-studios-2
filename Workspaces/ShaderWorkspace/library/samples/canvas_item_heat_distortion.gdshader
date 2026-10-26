// Heat Distortion
// Screen-space mirage distortion; place a ColorRect over the heated region.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
// Place on a full-screen ColorRect AFTER the scene; enable a BackBufferCopy when stacking screen effects.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float strength : hint_range(0,0.05)=0.009;
void fragment() {
    float heat=sin(UV.y*70.0-TIME*5.0)*sin(UV.y*23.0+TIME*2.0);
    vec2 uv=SCREEN_UV+vec2(heat*strength*(1.0-UV.y),0);
    COLOR=texture(screen_texture,uv);
}
