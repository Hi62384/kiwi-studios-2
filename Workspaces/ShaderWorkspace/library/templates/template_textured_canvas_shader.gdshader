// Textured Canvas Shader
// Source texture, UV transform and correct node modulation ready for custom 2D processing.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
uniform vec4 tint : source_color=vec4(1);
uniform vec2 uv_scale=vec2(1);
uniform vec2 uv_offset=vec2(0);
varying vec4 vertex_tint;
void vertex() {
    vertex_tint=COLOR;
}
void fragment() {
    // Sample TEXTURE once and multiply the vertex color captured before texture sampling.
    vec4 source=texture(TEXTURE,UV*uv_scale+uv_offset);
    COLOR=source*tint*vertex_tint;
}
