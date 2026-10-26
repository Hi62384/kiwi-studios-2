// CRT Display
// Curved cathode-ray screen with scanlines, RGB phosphor mask and clipped curved corners.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
// Place on a full-screen ColorRect AFTER the scene; enable a BackBufferCopy when stacking screen effects.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float curvature : hint_range(0,0.3)=0.1;
uniform float lines : hint_range(50,600)=240;
void fragment() {
    vec2 p=UV*2.0-1.0;
    vec2 uv=p*(1.0+dot(p,p)*curvature)*0.5+0.5;
    vec3 c=texture(screen_texture,uv).rgb;
    float scan=0.8+0.2*sin(uv.y*lines*TAU);
    vec3 mask=0.7+0.3*cos(uv.x*900.0+vec3(0,2.094,4.189));
    float edge=step(0.0,uv.x)*step(uv.x,1.0)*step(0.0,uv.y)*step(uv.y,1.0);
    COLOR=vec4(c*scan*mask*edge,1);
}
