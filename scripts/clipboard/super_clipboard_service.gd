class_name KiwiSuperClipboardService
extends Node
## App-wide lifetime. Metadata only is read at startup; assets remain lazy.
static var instance: KiwiSuperClipboardService
var store: KiwiClipboardStore
var window: Control
var layer: CanvasLayer
var toast: Label
var toast_panel:=PanelContainer.new()
var toast_timer:=Timer.new()
func _ready() -> void:
	_native_clipboard().ready(self)

func _input(event: InputEvent) -> void:
	_native_clipboard().input(self,event)

func toggle() -> void:
	_native_clipboard().toggle(self)

func notify(message: String,failed: bool=false) -> void:
	_native_clipboard().notify(self,message,failed)

func quick_save(value: Variant,title: String="Resource",folder: String="default") -> String:
	return _native_clipboard().quick_save(self,value,title,folder)

func import_item(id: String) -> String:
	return _native_clipboard().import_item(self,id)

func drag_payload(ids: PackedStringArray) -> Dictionary:
	return _native_clipboard().drag_payload(self,ids)

func save_active_document() -> void:
	_native_clipboard().save_active_document(self)

func _exit_tree() -> void:
	_native_clipboard().exit_tree(self)


static func _native_clipboard() -> Object:
	return Engine.get_singleton("KiwiNativeServices").service("super_clipboard")
