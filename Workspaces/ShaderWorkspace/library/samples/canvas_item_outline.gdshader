// Outline
// Eight-neighbor outer alpha outline; leave transparent padding around the sprite.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
uniform vec4 outline : source_color = vec4(0.05,0.03,0.13,1);
uniform float width : hint_range(1,12)=4;
void fragment() {
    vec4 c=texture(TEXTURE,UV);
    float a=0.0;
    for(int y=-1;y<=1;y++) {
        for(int x=-1;x<=1;x++) {
            a=max(a,texture(TEXTURE,UV+vec2(float(x),float(y))*TEXTURE_PIXEL_SIZE*width).a);
        }
    }
    COLOR=mix(outline,c,c.a);
    COLOR.a=max(c.a,a*outline.a);
}
