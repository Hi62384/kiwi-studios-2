class_name KiwiAudioConductorControls
extends VBoxContainer
## A bounded draft editor: Apply is one undo action; Cancel leaves no edits.
signal applied
signal seek_requested(seconds: float)
var session: KiwiAudioEditSession
var _owner: KiwiAudioDocument
var _is_current := Callable()
var _revision := -1
var _tempo := 120.0
var _signature := Vector2i(4, 4)
var _tempos: Array = []
var _meters: Array = []
var _tempos_list := ItemList.new()
var _meters_list := ItemList.new()
var _tempo_beat: SpinBox
var _tempo_value: SpinBox
var _meter_beat: SpinBox
var _meter_numerator: SpinBox
var _meter_denominator: OptionButton
var _status := Label.new()

func setup(value: KiwiAudioEditSession, at: float = 0.0, is_current: Callable = Callable()) -> void:
	_is_current = is_current
	session = value; _owner = session.document; _revision = session.revision
	_tempo = _owner.tempo; _signature = _owner.time_signature
	_tempos = _owner.tempo_points.duplicate(true); _meters = _owner.meter_points.duplicate(true)
	_label(self, "Project conductor / grid. Points use quarter-note beats from zero; tempo changes are steps. Every meter point starts a new bar, closing any partial bar.")
	_label(self, "Conductor edits preserve all clip positions, source windows, audio and MIDI source timing. Piano roll and generated sections retain source-relative beats. This does not warp audio or make patterns follow tempo changes.")
	var initial := HFlowContainer.new(); add_child(initial)
	var bpm := _spin(initial, "Initial BPM", _tempo, 20, 400, 0.01)
	bpm.value_changed.connect(func(number: float): _tempo = number; _refresh_lists())
	var numerator := _spin(initial, "Initial meter", _signature.x, 1, 32, 1)
	numerator.value_changed.connect(func(number: float): _signature.x = int(number); _refresh_lists())
	var denominator := _denominator(initial, _signature.y)
	denominator.item_selected.connect(func(index: int): _signature.y = int(denominator.get_item_metadata(index)); _refresh_lists())
	var tabs := TabContainer.new(); tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL; add_child(tabs)
	var tempos := VBoxContainer.new(); tempos.name = "Tempo points"; tabs.add_child(tempos)
	_tempos_list.custom_minimum_size.y = 145; _tempos_list.size_flags_vertical = Control.SIZE_EXPAND_FILL; tempos.add_child(_tempos_list)
	var tempo_row := HFlowContainer.new(); tempos.add_child(tempo_row)
	var beat := _owner.conductor().seconds_to_beat(at)
	_tempo_beat = _spin(tempo_row, "Quarter beat", maxf(0.001, beat), 0.001, KiwiAudioConductor.MAX_BEAT, 0.001)
	_tempo_value = _spin(tempo_row, "BPM", _owner.conductor().tempo_at(at), 20, 400, 0.01)
	_button(tempo_row, "Add / replace at beat", _put_tempo); _button(tempo_row, "Move selected", _move_tempo); _button(tempo_row, "Remove selected", _remove_tempo)
	_tempos_list.item_selected.connect(func(index: int): _tempo_beat.value = float(_tempos[index].beat); _tempo_value.value = float(_tempos[index].bpm))
	_tempos_list.item_activated.connect(func(index: int): _seek(float(_tempos[index].beat)))
	var meters := VBoxContainer.new(); meters.name = "Meter points"; tabs.add_child(meters)
	_meters_list.custom_minimum_size.y = 145; _meters_list.size_flags_vertical = Control.SIZE_EXPAND_FILL; meters.add_child(_meters_list)
	var meter_row := HFlowContainer.new(); meters.add_child(meter_row)
	_meter_beat = _spin(meter_row, "Quarter beat", maxf(0.001, beat), 0.001, KiwiAudioConductor.MAX_BEAT, 0.001)
	_meter_numerator = _spin(meter_row, "Meter", 4, 1, 32, 1); _meter_denominator = _denominator(meter_row, 4)
	_button(meter_row, "Add / replace at beat", _put_meter); _button(meter_row, "Move selected", _move_meter); _button(meter_row, "Remove selected", _remove_meter)
	_meters_list.item_selected.connect(func(index: int):
		_meter_beat.value = float(_meters[index].beat); _meter_numerator.value = int(_meters[index].numerator)
		for item in _meter_denominator.item_count:
			if int(_meter_denominator.get_item_metadata(item)) == int(_meters[index].denominator): _meter_denominator.select(item))
	_meters_list.item_activated.connect(func(index: int): _seek(float(_meters[index].beat)))
	_label(self, "Double-click a point to seek its draft time. Apply replaces the conductor in one undo step; closing this window discards the draft. Reopen after any other document edit.")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(_status)
	_button(self, "Apply conductor (preserve source timing)", _apply)
	_refresh_lists()

func _put_tempo() -> void:
	_put(_tempos, {"beat": _tempo_beat.value, "bpm": _tempo_value.value})

func _put_meter() -> void:
	_put(_meters, {"beat": _meter_beat.value, "numerator": int(_meter_numerator.value), "denominator": int(_meter_denominator.get_item_metadata(_meter_denominator.selected))})

func _move_tempo() -> void:
	_move(_tempos, _tempos_list, {"beat": _tempo_beat.value, "bpm": _tempo_value.value})

func _move_meter() -> void:
	_move(_meters, _meters_list, {"beat": _meter_beat.value, "numerator": int(_meter_numerator.value), "denominator": int(_meter_denominator.get_item_metadata(_meter_denominator.selected))})

func _move(points: Array, list: ItemList, point: Dictionary) -> void:
	var selected := list.get_selected_items()
	if selected.is_empty(): _status.text = "Select a point to move first."; return
	for i in points.size():
		if i != selected[0] and absf(float(points[i].beat) - float(point.beat)) < KiwiAudioConductor.MIN_GAP: _status.text = "That beat already has a point. Use Add / replace at beat to replace it."; return
	points[selected[0]] = point; points.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.beat) < float(b.beat)); _refresh_lists()

func _put(points: Array, point: Dictionary) -> void:
	for i in points.size():
		if absf(float(points[i].beat) - float(point.beat)) < KiwiAudioConductor.MIN_GAP: points[i] = point; _refresh_lists(); return
	if points.size() >= KiwiAudioConductor.MAX_POINTS: _status.text = "This conductor lane already has 1024 points."; return
	points.append(point); points.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.beat) < float(b.beat)); _refresh_lists()

func _remove_tempo() -> void:
	var selected := _tempos_list.get_selected_items()
	if not selected.is_empty(): _tempos.remove_at(selected[0]); _refresh_lists()

func _remove_meter() -> void:
	var selected := _meters_list.get_selected_items()
	if not selected.is_empty(): _meters.remove_at(selected[0]); _refresh_lists()

func _refresh_lists() -> void:
	var conductor := KiwiAudioConductor.new(_tempo, _signature, _tempos, _meters)
	_status.text = conductor.error
	_tempos_list.clear(); _meters_list.clear()
	for point in _tempos: _tempos_list.add_item("Q %.3f  ·  %.2f BPM  ·  %.3f s" % [float(point.beat), float(point.bpm), conductor.beat_to_seconds(float(point.beat))])
	for point in _meters: _meters_list.add_item("Q %.3f  ·  %d/%d  ·  %.3f s" % [float(point.beat), int(point.numerator), int(point.denominator), conductor.beat_to_seconds(float(point.beat))])

func _seek(beat: float) -> void:
	if (_is_current.is_valid() and not bool(_is_current.call())) or session.document != _owner or session.revision != _revision: _status.text = "The composition changed. Close and reopen this editor."; return
	var conductor := KiwiAudioConductor.new(_tempo, _signature, _tempos, _meters)
	if conductor.error.is_empty(): seek_requested.emit(conductor.beat_to_seconds(beat))

func _apply() -> void:
	if (_is_current.is_valid() and not bool(_is_current.call())) or session.document != _owner or session.revision != _revision or session._before != null: _status.text = "The composition changed. Close and reopen this editor before applying."; return
	var problem := session.set_conductor(_tempo, _signature, _tempos, _meters)
	if not problem.is_empty(): _status.text = problem; return
	applied.emit()

func _label(parent: Node, text: String) -> void:
	var label := Label.new(); label.text = text; label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; parent.add_child(label)

func _button(parent: Node, text: String, callback: Callable) -> void:
	var button := Button.new(); button.text = text; parent.add_child(button); button.pressed.connect(callback)

func _spin(parent: Node, text: String, value: float, low: float, high: float, step: float) -> SpinBox:
	_label(parent, text)
	var spin := SpinBox.new(); spin.min_value = low; spin.max_value = high; spin.step = step; spin.value = value; parent.add_child(spin); return spin

func _denominator(parent: Node, selected: int) -> OptionButton:
	var choice := OptionButton.new(); parent.add_child(choice)
	for number in [1, 2, 4, 8, 16, 32]:
		choice.add_item("/ " + str(number)); choice.set_item_metadata(choice.item_count - 1, number)
		if number == selected: choice.select(choice.item_count - 1)
	return choice
