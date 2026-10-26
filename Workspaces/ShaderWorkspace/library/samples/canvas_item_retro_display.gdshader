// Retro Display
// Monochrome LCD-like quantization with visible rectangular pixel gaps.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
// Place on a full-screen ColorRect AFTER the scene; enable a BackBufferCopy when stacking screen effects.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
void fragment() {
    vec4 c=texture(screen_texture,SCREEN_UV);
    float l=dot(c.rgb,vec3(0.3,0.59,0.11));
    float grid=step(0.08,fract(UV.x*160.0))*step(0.08,fract(UV.y*100.0));
    vec3 green=mix(vec3(0.04,0.12,0.03),vec3(0.55,0.8,0.25),floor(l*4.0)/4.0);
    COLOR=vec4(green*(0.65+0.35*grid),1);
}
