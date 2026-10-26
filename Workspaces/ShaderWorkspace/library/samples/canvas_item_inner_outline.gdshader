// Inner Outline
// An inward alpha-edge stroke that does not enlarge a silhouette.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
uniform vec4 outline : source_color = vec4(1,0.75,0.1,1);
uniform float width : hint_range(1,12)=5;
void fragment() {
    vec4 c=texture(TEXTURE,UV);
    float a=1.0;
    for(int y=-1;y<=1;y++) {
        for(int x=-1;x<=1;x++) {
            a=min(a,texture(TEXTURE,UV+vec2(float(x),float(y))*TEXTURE_PIXEL_SIZE*width).a);
        }
    }
    COLOR=vec4(mix(outline.rgb,c.rgb,a),c.a);
}
