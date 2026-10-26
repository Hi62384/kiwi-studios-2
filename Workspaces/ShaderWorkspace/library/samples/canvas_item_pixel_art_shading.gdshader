// Pixel Art Shading
// Coarse sampling, checker dithering and four shaded palette bands create pixel-art tonality.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
uniform float resolution : hint_range(16,256,1)=64;
void fragment() {
    vec2 uv=(floor(UV*resolution)+0.5)/resolution;
    vec4 c=texture(TEXTURE,uv);
    float l=dot(c.rgb,vec3(0.3,0.59,0.11));
    float d=mod(floor(UV.x*resolution)+floor(UV.y*resolution),2.0)*0.12;
    float band=floor(clamp(l+d,0.0,1.0)*3.0)/3.0;
    COLOR=vec4(mix(vec3(0.08,0.12,0.24),vec3(1,0.8,0.45),band),c.a);
}
