class_name KiwiGrowthStyle
extends Resource
@export var title: String="Growth style"
@export var asset_id: String=ActorData.new_id()
@export var values: Dictionary={}
const PRESETS:={
	"Straight":{"shape":0,"curvature":0.,"orientation_variation":.03},
	"Wavy":{"shape":2,"curl":.5,"frequency":2.,"curvature":.1},
	"Curly":{"shape":3,"curl":1.2,"frequency":4.,"curvature":.1},
	"Coiled":{"shape":3,"curl":2.,"frequency":8.,"quality":3},
	"Buzzed":{"length":.035,"shape":0,"direction_mode":0,"variation":.15},
	"Swept":{"shape":1,"direction_mode":2,"direction":Vector3(1,.25,0),"direction_blend":.8},
	"Messy":{"shape":2,"curl":.4,"frequency":2.,"variation":.65,"orientation_variation":.7},
	"Stylized locks":{"shape":1,"thickness":.06,"taper":.8,"cross_section":1,"quality":1},
	"Short fur":{"length":.04,"thickness":.003,"variation":.2,"guard_hairs":.05},
	"Medium fur":{"length":.12,"thickness":.006,"variation":.3,"guard_hairs":.15},
	"Long fur":{"length":.3,"thickness":.007,"variation":.35,"guard_hairs":.2},
	"Shaggy fur":{"length":.4,"variation":.65,"orientation_variation":.6,"shape":2},
	"Fluffy fur":{"length":.2,"thickness":.004,"direction_mode":0,"orientation_variation":.6},
	"Coarse fur":{"length":.16,"thickness":.012,"cross_section":2,"guard_hairs":.35},
	"Down":{"feather_type":0,"width":.08,"length":.2,"variation":.4},
	"Contour":{"feather_type":1,"width":.14,"length":.45,"feather_asymmetry":0.},
	"Flight":{"feather_type":2,"width":.16,"length":.6,"feather_asymmetry":.4},
	"Tail":{"feather_type":1,"width":.16,"length":1.,"feather_tip":.4},
	"Stylized feathers":{"feather_type":1,"width":.22,"length":.5,"quality":1,"feather_tip":.7}}
static func preset(name: String) -> KiwiGrowthStyle:
	var result:=KiwiGrowthStyle.new(); result.title=name; result.values=PRESETS.get(name,{}).duplicate(true); return result
func thumbnail() -> Texture2D: return load("res://Workspaces/ModelWorkspace/growth/growth_thumbnail.gd").texture(self)
