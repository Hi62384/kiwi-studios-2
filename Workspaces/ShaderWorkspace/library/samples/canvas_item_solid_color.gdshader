// Solid Color
// Flat configurable RGBA fill for UI panels and silhouettes.
// Target: Sprite2D, TextureRect, Polygon2D, or another CanvasItem. Uses its source texture and alpha.
shader_type canvas_item;
uniform vec4 color : source_color = vec4(0.18,0.75,0.58,1);
void fragment() {
    COLOR = color;
}
