// Animated Glow
// Pulsing source emission for charge-up indicators and enchanted sprites.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
uniform float speed : hint_range(0,12)=3;
uniform float strength : hint_range(0,3)=0.8;
uniform vec4 glow : source_color=vec4(0.3,0.7,1,1);
void fragment() {
    vec4 c=texture(TEXTURE,UV);
    float pulse=0.5+0.5*sin(TIME*speed);
    COLOR=vec4(c.rgb+glow.rgb*pulse*strength,c.a);
}
