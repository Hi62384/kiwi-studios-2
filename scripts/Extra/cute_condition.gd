class_name CuteCondition
extends Resource


enum ConditionType {
	EQUAL,
	GREATER_THAN,
	LESS_THAN,
	EQUAL_GREATER_THAN,
	EQUAL_LESS_THAN,
	NOT_EQUAL,
}

@export var condition: ConditionType = ConditionType.EQUAL
@export var compare_value: Array


func compare(val: Variant) -> bool:
	if condition == ConditionType.EQUAL:
		return val == compare_value[0]
	elif condition == ConditionType.GREATER_THAN:
		return val > compare_value[0]
	elif condition == ConditionType.LESS_THAN:
		return val < compare_value[0]
	elif condition == ConditionType.EQUAL_GREATER_THAN:
		return val >= compare_value[0]
	elif condition == ConditionType.EQUAL_LESS_THAN:
		return val <= compare_value[0]
	elif condition == ConditionType.NOT_EQUAL:
		return val != val
	
	return false
