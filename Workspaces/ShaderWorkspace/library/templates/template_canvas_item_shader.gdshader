// Canvas Item Shader
// Minimal 2D material preserving node modulation and source alpha.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
uniform vec4 fill_color : source_color=vec4(0.3,0.8,0.55,1);
void fragment() {
    // COLOR initially includes vertex and modulate colors.
    COLOR*=fill_color;
}
