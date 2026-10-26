// Soft Glow
// Gaussian-weighted broad alpha bloom for a softer luminous silhouette.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
uniform float radius : hint_range(1,24)=12;
uniform vec4 glow : source_color=vec4(1,0.4,0.1,1);
void fragment() {
    vec4 c=texture(TEXTURE,UV);
    float a=0.0;
    float w=0.0;
    for(int y=-3;y<=3;y++) {
        for(int x=-3;x<=3;x++) {
            float k=exp(-float(x*x+y*y)/6.0);
            a+=texture(TEXTURE,UV+vec2(float(x),float(y))*TEXTURE_PIXEL_SIZE*radius/3.0).a*k;
            w+=k;
        }
    }
    float g=a/w*(1.0-c.a);
    COLOR=vec4(c.rgb*c.a+glow.rgb*g*2.0,max(c.a,g));
}
