class_name KiwiMorphComponentEvents
extends RefCounted
## Explicit visibility/region transfers. Evaluation is a pure function of time;
## no simulation, mutation of source states, or implicit overlap-based merging.
static func evaluate(document: KiwiTransformationImage2D, id: String, time: float) -> Dictionary:
	return Engine.get_singleton("KiwiNativeServices").call("service", "transformation_renderer").call("evaluate_events", document, id, time)
static func _native() -> Object: return Engine.get_singleton("KiwiNativeServices").call("service", "transformation_events")
static func detach(session: KiwiTransformationSession, mask: Image) -> String: return _native().call("detach", session, mask)
static func merge(session: KiwiTransformationSession, ids: PackedStringArray, image: Image, at: float) -> String: return _native().call("merge", session, ids, image, at)
static func check_time(session: KiwiTransformationSession, ids: PackedStringArray, at: float) -> String: return _native().call("check_time", session, ids, at)
