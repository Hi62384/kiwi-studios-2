class_name ActorKeyframe
extends Resource

enum Interpolation { LINEAR, EASE, STEP }

@export var id: String = ""
@export var time: float = 0.0
@export var value: Variant
@export var interpolation: Interpolation = Interpolation.LINEAR
## Godot ease curve exponent; applies to the segment leaving this key.
@export var attenuation: float = 1.0
## Normalized progress curve for the segment leaving this key; null is linear.
@export var value_curve: Curve
@export var curve_template: String = "Linear"
@export var curve_adjustment: float = 0.0

func copy_key() -> ActorKeyframe:
	var result := ActorKeyframe.new()
	result.id = id
	result.time = time
	result.value = ActorData.copy_value(value)
	result.interpolation = interpolation
	result.attenuation = attenuation
	result.value_curve = value_curve.duplicate() as Curve if value_curve != null else null
	result.curve_template = curve_template
	result.curve_adjustment = curve_adjustment
	return result
