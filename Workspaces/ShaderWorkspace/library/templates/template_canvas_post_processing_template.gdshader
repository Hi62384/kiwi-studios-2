// Canvas Post Processing Template
// Complete screen-reading desaturation pass with a declared screen texture.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
// Place on a full-screen ColorRect AFTER the scene; enable a BackBufferCopy when stacking screen effects.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float amount : hint_range(0,1)=0.6;
void fragment() {
    // Use SCREEN_UV, not UV, to address the scene back buffer.
    vec4 scene=texture(screen_texture,SCREEN_UV);
    float luminance=dot(scene.rgb,vec3(0.2126,0.7152,0.0722));
    COLOR=vec4(mix(scene.rgb,vec3(luminance),amount),1);
}
