extends RefCounted
## Shared styled menus and vector icons for warp controls.
static var icons: Dictionary={}
const PATHS={
	"0":"<path d='M4 17h16M4 21h16'/>",
	"1":"<path d='M4 10h16M4 15h16M4 20h16'/>",
	"2":"<path d='M4 3h16M4 7h16M4 11h16M4 15h16M4 19h16'/>",
	"spot":"<path d='m3 13 10-10 8 8-10 10zM8 8l8 8'/><circle cx='10' cy='12' r='1'/><circle cx='13' cy='9' r='1'/><path d='M19 2v4M17 4h4'/>",
	"heal":"<path d='m3 17 10-10 4 4-10 10zM14 3h8M18 1v8M9 11l4 4'/>",
	"clone":"<path d='M5 16h14v5H5zM8 16v-3h8v3M10 13V9C6 4 9 2 12 2s6 2 2 7v4'/>",
	"pattern_heal":"<path d='M3 3h8v8H3zm10 0h8v8h-8zM3 13h8v8H3zM14 17h8m-4-4v8'/>",
	"pattern_fill":"<path d='M3 3h18v18H3zM9 3v18M15 3v18M3 9h18M3 15h18'/><path d='m4 5 3 2m9 9 3 3'/>",
	"procedural":"<circle cx='5' cy='5' r='2'/><circle cx='19' cy='5' r='2'/><circle cx='12' cy='13' r='3'/><circle cx='5' cy='21' r='1'/><circle cx='20' cy='20' r='2'/><path d='m6 6 4 5m4 0 4-4m-9 8-3 4m9-4 3 3'/>",
	"patch":"<path d='M3 5h15v15H3zM7 2v5M14 2v5M1 10h5M1 16h5M8 18v4M14 18v4M16 10h6m-3-3 3 3-3 3'/>",
	"current":"<path d='m3 8 9-5 9 5-9 5zM3 15l9 5 9-5'/>",
	"visible":"<path d='M2 12c6-9 14-9 20 0-6 9-14 9-20 0z'/><circle cx='12' cy='12' r='3'/>",
	"group":"<path d='M3 6h7l3 3h8v12H3zM4 3h8l3 3'/>",
	"nearby":"<circle cx='12' cy='12' r='4'/><path d='M2 12h4m12 0h4M12 2v4m0 12v4'/>",
	"manual":"<path d='m6 2 13 10-7 1-3 7zM16 17h6m-3-3v6'/>",
	"rectangle":"<path d='M3 5h18v14H3zM7 2v6m10-6v6M1 10h5m12 0h5'/>",
	"circle":"<circle cx='12' cy='12' r='8'/><path d='M12 1v5m0 12v5M1 12h5m12 0h5'/>",
	"lasso":"<path d='M3 10c0-9 18-9 18 0s-18 9-18 0M5 15c-4 7 10 7 8 1'/>",
	"tiled":"<path d='M3 3h8v8H3zm10 0h8v8h-8zM3 13h8v8H3zm10 0h8v8h-8z'/>",
	"grid":"<path d='M3 3h18v18H3zM11 3v18M3 11h18'/>",
	"offset":"<path d='M2 3h20v18H2M2 9h20M2 15h20M8 3v6M16 3v6M12 9v6M8 15v6M16 15v6'/>",
	"scatter":"<path d='m3 3 5 1-1 5-5-1zm13 1 4 2-2 4-4-2zM6 15l4-2 2 4-4 2zm10 0h5v5h-5z'/>",
	"exact":"<path d='M3 5h7v14H3zm11 0h7v14h-7zM10 12h4'/>",
	"natural":"<path d='M3 20C3 6 16 1 21 3c0 10-6 18-18 17zM5 18 17 6m-9 9v-5m4 2h5'/>",
	"synthesis":"<path d='M3 4h8v7H3zm11 9h7v7h-7zM6 14v6h5M14 4h7v6M10 15l5-5m-5 0h5v5'/>",
	"texture":"<path d='M3 5h18M3 12h18M3 19h18M6 3v5m6 2v5m6 2v5'/>",
	"direct":"<path d='M3 5h6v14H3zM15 5h6v14h-6zM9 12h6m-3-3 3 3-3 3'/>",
	"normal":"<path d='m4 17 12-12 3 3L7 20zM14 7l3 3M3 21h7'/>",
	"stroke_correct":"<path d='M3 16c4-12 10 12 18-8'/><path d='M3 20h18M5 3v4M3 5h4'/>",
	"soften":"<path d='M3 5h18M3 12c5-5 12 5 18 0M3 19h18' stroke-dasharray='2 3'/><path d='M7 8c3-3 7 3 10 0M7 16c3-3 7 3 10 0'/>",
	"brush":"<path d='M4 18 16 6l3 3L7 21zM14 8l3 3M4 18l3 3'/>",
	"mesh":"<path d='M3 3h18v18H3zM9 3v18M15 3v18M3 9h18M3 15h18'/>",
	"pins":"<circle cx='12' cy='8' r='5'/><path d='M12 13v9M8 8h8M12 4v8'/>",
	"push":"<path d='M3 12h18m-6-6 6 6-6 6M3 6v12'/>",
	"pinch":"<path d='m3 3 6 6m-6 0h6V3m12 0-6 6m0-6v6h6M3 21l6-6m-6 0h6v6m12 0-6-6m0 6v-6h6'/>",
	"bulge":"<path d='m9 9-6-6m0 6V3h6m6 6 6-6m-6 0h6v6M9 15l-6 6m0-6v6h6m6-6 6 6m-6 0h6v-6'/>",
	"twirl_cw":"<path d='M20 9a8 8 0 1 0-2 9M20 3v6h-6M16 12a4 4 0 1 1-4-4'/>",
	"twirl_ccw":"<path d='M4 9a8 8 0 1 1 2 9M4 3v6h6M8 12a4 4 0 1 0 4-4'/>",
	"smooth":"<path d='M2 7l4 4 4-6 4 8 4-5 4 3M2 19c5-9 12-9 20 0'/>",
	"restore":"<path d='M4 9a8 8 0 1 1 0 7M4 3v6h6M9 13h6'/>",
	"freeze":"<path d='M12 2v20M3 7l18 10M3 17 21 7M8 4l4 3 4-3M8 20l4-3 4 3'/>",
	"thaw":"<path d='m3 13 9-9 9 9-8 8H9zM7 17l9-9M14 21h8'/>",
	"strength":"<path d='m14 2-10 12h7l-1 8 10-12h-7z'/>",
	"falloff":"<path d='M3 3v18h18M5 5c10 0 3 13 14 13'/><path d='M5 9h1m2 3h1m2 3h1m2 2h1'/>",
}
static func icon(kind: String) -> Texture2D:
	if icons.has(kind): return icons[kind]
	var bitmap:=Image.new()
	bitmap.load_svg_from_string("<svg xmlns='http://www.w3.org/2000/svg' width='24' height='24' viewBox='0 0 24 24'><g fill='none' stroke='#95e4d0' stroke-width='1.8' stroke-linecap='round' stroke-linejoin='round'>"+str(PATHS.get(kind,PATHS.brush))+"</g></svg>")
	icons[kind]=ImageTexture.create_from_image(bitmap); return icons[kind]

static func build(workspace: KiwiImageWorkspace,parent: Node,node_name: String,title: String,ids: Array,captions: Array,current: String,changed: Callable) -> MenuButton:
	var button:=MenuButton.new(); button.name=node_name; button.text=str(captions[maxi(0,ids.find(current))])+"  ▾"; button.icon=icon(current)
	button.custom_minimum_size.y=28; button.add_theme_constant_override("icon_max_width",19); parent.add_child(button)
	button.add_theme_font_size_override("font_size",12)
	button.add_theme_stylebox_override("normal",workspace._box(Color("20343d"),Color("446570"),6,5))
	button.add_theme_stylebox_override("hover",workspace._box(Color("28554f"),Color("80e3c7"),6,5))
	button.add_theme_stylebox_override("pressed",workspace._box(Color("23594f"),Color("80e3c7"),6,5))
	var menu:=button.get_popup(); menu.add_separator(title)
	menu.add_theme_stylebox_override("panel",workspace._box(Color("152631"),Color("4a756f"),10,10))
	menu.add_theme_stylebox_override("hover",workspace._box(Color("28594f"),Color.TRANSPARENT,5,5))
	menu.add_theme_color_override("font_color",Color("dfefed")); menu.add_theme_color_override("font_hover_color",Color.WHITE)
	menu.add_theme_color_override("font_separator_color",Color("8ba9af"))
	menu.add_theme_font_size_override("font_size",14); menu.add_theme_constant_override("v_separation",12)
	menu.add_theme_constant_override("h_separation",12); menu.add_theme_constant_override("icon_max_width",22)
	for i in ids.size(): menu.add_icon_item(icon(ids[i]),str(captions[i])+("    ✓" if ids[i]==current else ""),i)
	menu.id_pressed.connect(func(index: int): changed.call(index))
	return button
