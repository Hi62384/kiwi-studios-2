// Animated Light Sweep
// Diagonal specular sweep over the source image, useful for polished UI cards.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
uniform float speed : hint_range(0.01,2)=0.4;
uniform float width : hint_range(0.01,0.3)=0.07;
uniform float intensity : hint_range(0,3)=0.8;
void fragment() {
    vec4 c=texture(TEXTURE,UV);
    float t=fract(TIME*speed)*2.0-0.5;
    float stripe=exp(-pow((UV.x+UV.y*0.35-t)/width,2.0));
    COLOR=vec4(c.rgb+stripe*intensity,c.a);
}
