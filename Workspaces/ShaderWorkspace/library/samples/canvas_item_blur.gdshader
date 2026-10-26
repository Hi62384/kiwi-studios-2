// Blur
// Premultiplied-alpha Gaussian blur avoids dark fringes at transparent edges.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
uniform float radius : hint_range(0.1,8)=2;
void fragment() {
    vec4 c=vec4(0);
    float w=0.0;
    for(int y=-2;y<=2;y++) {
        for(int x=-2;x<=2;x++) {
            float k=exp(-float(x*x+y*y)/4.0);
            vec4 s=texture(TEXTURE,UV+vec2(float(x),float(y))*TEXTURE_PIXEL_SIZE*radius);
            c+=vec4(s.rgb*s.a,s.a)*k;
            w+=k;
        }
    }
    c/=w;
    COLOR=vec4(c.rgb/max(c.a,0.0001),c.a);
}
