// Glow
// Halo sampled around the source silhouette, suitable for magic icons and highlights.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
uniform float radius : hint_range(1,32)=9;
uniform vec4 glow : source_color=vec4(0.2,0.9,1,1);
void fragment() {
    vec4 c=texture(TEXTURE,UV);
    float a=0.0;
    for(int i=0;i<16;i++) {
        float t=float(i)*TAU/16.0;
        a+=texture(TEXTURE,UV+vec2(cos(t),sin(t))*TEXTURE_PIXEL_SIZE*radius).a/16.0;
    }
    float g=a*(1.0-c.a);
    COLOR=vec4(c.rgb+glow.rgb*g, max(c.a,g*glow.a));
}
