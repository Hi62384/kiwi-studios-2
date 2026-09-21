class_name ActorSceneData
extends Resource
## Complete editable scene state. Actor resources remain embedded in this file.

@export var actors: Array[ActorData] = []
@export var clips: Array[ActorClip] = []
@export var sections: Array[ActorSection] = []
@export var selected_ids: Array[String] = []
@export var selected_id: String = ""
@export var selected_layer: int = 0
@export var selected_section_id: String = "default"
@export var focused_actor_id: String = ""
@export var playhead_time: float = 0.0
@export var overlay_actor_id: String = ""
@export var overlay_path: PackedStringArray = []
@export var section_navigation: Dictionary = {}
@export var timeline_section_states: Dictionary = {}
@export var inspector_state: ActorInspectorState
@export var keyframe_view_enabled: bool = false
@export var selected_key_ids: Array[String] = []
@export var keyframe_track_scroll: int = 0
@export var keyframe_detail_scroll: int = 0
@export var timeline_split_offset: int = 560
@export var editor_camera_transform: Transform3D = Transform3D.IDENTITY
@export var editor_camera_head_rotation: Vector3 = Vector3.ZERO
@export var editor_camera_lens_rotation: Vector3 = Vector3.ZERO
@export var editor_camera_speed: float = 5.0
@export var video_duration: float = 10.0
@export var video_duration_custom: bool = false
