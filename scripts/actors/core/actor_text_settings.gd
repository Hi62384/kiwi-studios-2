class_name ActorTextSettings
extends RefCounted
static var fonts: Dictionary = {}
static var families := PackedStringArray()
static func system_fonts() -> PackedStringArray:
	if not families.is_empty(): return families
	families = OS.get_system_fonts()
	if families.is_empty() and OS.get_name() == "Windows":
		var output: Array = []
		OS.execute("powershell.exe", PackedStringArray(["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", ProjectSettings.globalize_path("res://scripts/actors/core/system_fonts.ps1")]), output)
		var installed: Variant = JSON.parse_string("".join(output))
		if installed is Array: families = PackedStringArray(installed)
	families.sort()
	return families
static func values(reference: Variant) -> Dictionary:
	var object: ActorObjectData = ActorAnimation.resolve_reference(reference) if reference is ActorObjectReference else reference as ActorObjectData
	return object.values if object != null else {}
static func font(settings: Dictionary) -> Font:
	var key := "%s:%s:%s" % [settings.get(&"font", "Arial"), settings.get(&"bold", false), settings.get(&"italic", false)]
	if not fonts.has(key):
		var system := SystemFont.new()
		system.font_names = PackedStringArray([str(settings.get(&"font", "Arial"))])
		system.font_weight = 700 if settings.get(&"bold", false) else 400
		system.font_italic = bool(settings.get(&"italic", false))
		fonts[key] = system
	return fonts[key]
static func apply_label(label: Label, settings: Dictionary) -> void:
	var style := LabelSettings.new()
	style.font = font(settings)
	style.font_size = maxi(1, int(settings.get(&"font_size", 48)))
	style.font_color = settings.get(&"color", Color.WHITE)
	style.outline_size = maxi(0, int(settings.get(&"outline_size", 0)))
	style.outline_color = settings.get(&"outline_color", Color.BLACK)
	style.shadow_size = 1 if settings.get(&"shadow", false) else 0
	style.shadow_color = settings.get(&"shadow_color", Color(0, 0, 0, 0.65)) if settings.get(&"shadow", false) else Color.TRANSPARENT
	style.shadow_offset = settings.get(&"shadow_offset", Vector2(2, 2))
	label.label_settings = style
