// Vignette
// Soft elliptical edge darkening with configurable color, radius and falloff.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
// Place on a full-screen ColorRect AFTER the scene; enable a BackBufferCopy when stacking screen effects.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float radius : hint_range(0,1)=0.3;
uniform float softness : hint_range(0.01,1)=0.35;
uniform float strength : hint_range(0,1)=0.8;
uniform vec4 color : source_color=vec4(0.025,0.01,0.06,1);
void fragment() {
    vec3 c=texture(screen_texture,SCREEN_UV).rgb;
    float d=length((UV-0.5)*vec2(1.2,1));
    float v=smoothstep(radius,radius+softness,d);
    COLOR=vec4(mix(c,color.rgb,v*strength),1);
}
