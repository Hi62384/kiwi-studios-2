class_name NodeOperations
extends Node


static func delete_children(node: Node) -> void:
	for child: Node in node.get_children():
		child.queue_free()
