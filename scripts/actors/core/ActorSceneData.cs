using Godot;
using Settings = Godot.Collections.Dictionary;

/// <summary>Complete editable scene state, with embedded actor resources.</summary>
[GlobalClass]
public partial class ActorSceneData : Resource
{
    [Export] public Godot.Collections.Array<ActorData> actors { get; set; } = new();
    [Export] public Godot.Collections.Array<ActorClip> clips { get; set; } = new();
    [Export] public Godot.Collections.Array<ActorSection> sections { get; set; } = new();
    [Export] public Godot.Collections.Array<string> selected_ids { get; set; } = new();
    [Export] public string selected_id { get; set; } = "";
    [Export] public int selected_layer { get; set; } = 0;
    [Export] public string selected_section_id { get; set; } = "default";
    [Export] public string focused_actor_id { get; set; } = "";
    [Export] public double playhead_time { get; set; } = 0.0;
    [Export] public string overlay_actor_id { get; set; } = "";
    [Export] public string[] overlay_path { get; set; } = System.Array.Empty<string>();
    [Export] public Settings section_navigation { get; set; } = new();
    [Export] public Settings timeline_section_states { get; set; } = new();
    [Export] public ActorInspectorState? inspector_state { get; set; } = null;
    [Export] public bool keyframe_view_enabled { get; set; } = false;
    [Export] public Godot.Collections.Array<string> selected_key_ids { get; set; } = new();
    [Export] public int keyframe_track_scroll { get; set; } = 0;
    [Export] public int keyframe_detail_scroll { get; set; } = 0;
    [Export] public int timeline_split_offset { get; set; } = 560;
    [Export] public Transform3D editor_camera_transform { get; set; } = Transform3D.Identity;
    [Export] public Vector3 editor_camera_head_rotation { get; set; } = Vector3.Zero;
    [Export] public Vector3 editor_camera_lens_rotation { get; set; } = Vector3.Zero;
    [Export] public double editor_camera_speed { get; set; } = 5.0;
    [Export] public double video_duration { get; set; } = 10.0;
    [Export] public bool video_duration_custom { get; set; } = false;
}
