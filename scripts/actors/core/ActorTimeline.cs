using Godot;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

[GlobalClass]
public partial class ActorTimeline : RefCounted
{
    [Signal] public delegate void changedEventHandler();
    [Signal] public delegate void selection_requestedEventHandler();
    public const double MIN_DURATION = .1;
    public Godot.Collections.Array<ActorData> actors { get; set; } = new();
    public Godot.Collections.Array<ActorClip> clips { get; set; } = new();
    public Godot.Collections.Array<string> selected_ids { get; set; } = new();
    public string selected_id { get; set; } = "";
    public int selected_layer { get; set; }
    public UndoRedo history { get; set; } = new();
    public Godot.Collections.Array<ActorSection> sections { get; set; } = new() { new ActorSection() };
    public string selected_section_id { get; set; } = "default";
    public string focused_actor_id { get; set; } = "";
    public double playhead_time { get; set; }
    public string overlay_actor_id { get; set; } = "";
    public string[] overlay_path { get; set; } = System.Array.Empty<string>();
    public bool property_batch_active { get; set; }
    public Settings _audio_preview_before { get; set; } = new();
    public Settings _section_navigation { get; set; } = new();
    private readonly ActorTimelineOperations _operations = new();
    public Settings audio_snapshot(ActorData actor)
    {
        return _operations.audio_snapshot(this,actor);
    }
    public void restore_audio(Settings state)
    {
        _operations.restore_audio(this,state);
    }
    public double minimum_duration(ActorClip clip)
    {
        return _operations.minimum_duration(this,clip);
    }
    public Godot.Collections.Array<string> linked_clip_ids(Godot.Collections.Array<string> ids)
    {
        using var argument_ids = Variant.From(ids);
        return _operations.linked_clip_ids(this,argument_ids.AsGodotArray());
    }
    public void set_timeline_children_linked(string actor_id, bool linked)
    {
        _operations.set_timeline_children_linked(this,actor_id,linked);
    }
    public void _set_children_link(ActorData actor, bool linked)
    {
        _operations.set_children_link(this,actor,linked);
    }
    public Settings media_snapshot()
    {
        return _operations.media_snapshot(this);
    }
    public void restore_media(Settings state)
    {
        _operations.restore_media(this,state);
    }
    public void commit_media(Settings before, string label)
    {
        _operations.commit_media(this,before,label);
    }
    public void configure_video_audio(ActorData actor)
    {
        _operations.configure_video_audio(this,actor);
    }
    public void create_video_audio(ActorData actor)
    {
        _operations.create_video_audio(this,actor);
    }
    public void edit_video_property(ActorData actor, StringName key, Variant value)
    {
        _operations.edit_video_property(this,actor,key,value);
    }
    public string[] object_animation_path(ActorData actor, ActorObjectData @object, StringName key)
    {
        return _operations.object_animation_path(actor,@object,key);
    }
    public void preview_animation_value(ActorData actor, string[] path, Variant value)
    {
        _operations.preview_animation_value(this,actor,path,value);
    }
    public void commit_animation_value(ActorData actor, string[] path, Variant value)
    {
        _operations.commit_animation_value(this,actor,path,value);
    }
    public bool _animated_object_edit(ActorData actor, ActorObjectData @object, StringName key, Variant value, bool preview)
    {
        return _operations.animated_object_edit(this,actor,@object,key,value,preview);
    }
    public void edit_shader_uniform(ActorData actor, ActorObjectData @object, ActorObjectDefinition definition, StringName uniform_name, Variant value, string mode, Variant original)
    {
        _operations.edit_shader_uniform(this,actor,@object,definition,uniform_name,value,mode,original);
    }
    public void edit_shader_uniform(ActorData actor, ActorObjectData @object, ActorObjectDefinition definition, StringName uniform_name, Variant value) => edit_shader_uniform(actor, @object, definition, uniform_name, value, "edit", default);
    public void edit_shader_uniform(ActorData actor, ActorObjectData @object, ActorObjectDefinition definition, StringName uniform_name, Variant value, string mode) => edit_shader_uniform(actor, @object, definition, uniform_name, value, mode, default);
    public Godot.Collections.Array<ActorAnimationTrack> animation_snapshot(ActorData actor)
    {
        return new Godot.Collections.Array<ActorAnimationTrack>(_operations.animation_snapshot(actor));
    }
    public void add_keyframe(ActorData actor, string[] path, string label, Variant value, bool stepped, bool changed_only)
    {
        _operations.add_keyframe(this,actor,path,label,value,stepped,changed_only);
    }
    public void add_keyframe(ActorData actor, string[] path, string label, Variant value) => add_keyframe(actor, path, label, value, false, false);
    public void add_keyframe(ActorData actor, string[] path, string label, Variant value, bool stepped) => add_keyframe(actor, path, label, value, stepped, false);
    public ActorKeyframe? keyframe_for_id(ActorData actor, string key_id)
    {
        return _operations.keyframe_for_id(actor,key_id) as ActorKeyframe;
    }
    public ActorAnimationTrack? track_for_key(ActorData actor, string key_id)
    {
        return _operations.track_for_key(actor,key_id) as ActorAnimationTrack;
    }
    public void separate_track(ActorData actor, string[] path)
    {
        _operations.separate_track(this,actor,path);
    }
    public void unseparate_track(ActorData actor, string[] path)
    {
        _operations.unseparate_track(this,actor,path);
    }
    public static int component_count(Variant value)
    {
        return new ActorTimelineOperations().component_count(value);
    }
    public static Variant value_component(Variant value, int axis)
    {
        return new ActorTimelineOperations().value_component(value,axis);
    }
    public bool preview_keyframe(ActorData actor, string key_id, Settings changes)
    {
        return _operations.preview_keyframe(this,actor,key_id,changes);
    }
    public void edit_keyframe(ActorData actor, string key_id, Settings changes)
    {
        _operations.edit_keyframe(this,actor,key_id,changes);
    }
    public void delete_keyframes(ActorData actor, Godot.Collections.Array<string> ids)
    {
        using var argument_ids = Variant.From(ids);
        _operations.delete_keyframes(this,actor,argument_ids.AsGodotArray());
    }
    public void commit_animation_edit(ActorData actor, Godot.Collections.Array<ActorAnimationTrack> before, Godot.Collections.Array<ActorAnimationTrack> after, string action)
    {
        using var argument_before = Variant.From(before);
        using var argument_after = Variant.From(after);
        _operations.commit_animation_edit(this,actor,argument_before.AsGodotArray(),argument_after.AsGodotArray(),action);
    }
    public void restore_animation(ActorData actor, Godot.Collections.Array<ActorAnimationTrack> tracks)
    {
        using var argument_tracks = Variant.From(tracks);
        _operations.restore_animation(this,actor,argument_tracks.AsGodotArray());
    }
    public Settings navigation_state()
    {
        return _operations.navigation_state(this);
    }
    public void restore_navigation_state(Settings value)
    {
        _operations.restore_navigation_state(this,value);
    }
    public void validate_focus()
    {
        _operations.validate_focus(this);
    }
    public void focus_actor(string actor_id)
    {
        _operations.focus_actor(this,actor_id);
    }
    public void leave_actor_focus()
    {
        _operations.leave_actor_focus(this);
    }
    public void focus_parent()
    {
        _operations.focus_parent(this);
    }
    public Godot.Collections.Array<ActorData> focus_path()
    {
        return new Godot.Collections.Array<ActorData>(_operations.focus_path(this));
    }
    public ActorSection? section_for_id(string id)
    {
        return _operations.section_for_id(this,id) as ActorSection;
    }
    public void select_section(string id)
    {
        _operations.select_section(this,id);
    }
    public ActorSection? create_section()
    {
        return _operations.create_section(this) as ActorSection;
    }
    public void _insert_section(ActorSection section)
    {
        _operations.insert_section(this,section);
    }
    public void _remove_section(ActorSection section, string previous)
    {
        _operations.remove_section(this,section,previous);
    }
    public void rename_section(string id, string name)
    {
        _operations.rename_section(this,id,name);
    }
    public void _set_section_name(ActorSection section, string name)
    {
        _operations.set_section_name(this,section,name);
    }
    public bool clip_is_visible(int index)
    {
        return _operations.clip_is_visible(this,index);
    }
    public Godot.Collections.Array<ActorClip> section_clips()
    {
        return new Godot.Collections.Array<ActorClip>(_operations.section_clips(this));
    }
    public string _visibility_domain(ActorData actor)
    {
        return _operations.visibility_domain(this,actor);
    }
    public bool _actor_in_focus(ActorData actor)
    {
        return _operations.actor_in_focus(this,actor);
    }
    public bool _visible_in_focused_branch(ActorData actor)
    {
        return _operations.visible_in_focused_branch(this,actor);
    }
    public bool _is_focus_ancestor(ActorData actor)
    {
        return _operations.is_focus_ancestor(this,actor);
    }
    public bool _is_actor_ancestor(string ancestor_id, ActorData actor)
    {
        return _operations.is_actor_ancestor(this,ancestor_id,actor);
    }
    public bool _unbroken_relative_path(string ancestor_id, ActorData actor)
    {
        return _operations.unbroken_relative_path(this,ancestor_id,actor);
    }
    public bool actors_obstruct(ActorData a, ActorData b)
    {
        return _operations.actors_obstruct(this,a,b);
    }
    public bool hidden_clip_obstructs_view(int index)
    {
        return _operations.hidden_clip_obstructs_view(this,index);
    }
    public void set_timeline_children_visible(string actor_id, bool visible)
    {
        _operations.set_timeline_children_visible(this,actor_id,visible);
    }
    public bool _revealed_layer_fits(ActorData actor, ActorClip clip, int layer, Godot.Collections.Array<Settings> reserved)
    {
        using var argument_reserved = Variant.From(reserved);
        return _operations.revealed_layer_fits(this,actor,clip,layer,argument_reserved.AsGodotArray());
    }
    public void _set_timeline_children_visible(ActorData actor, bool visible, Settings layers)
    {
        _operations.apply_timeline_children_visible(this,actor,visible,layers);
    }
    public void _set_timeline_children_visible(ActorData actor, bool visible) => _set_timeline_children_visible(actor, visible, new Settings());
    public void delete_section(string id)
    {
        _operations.delete_section(this,id);
    }
    public void _delete_section_state(ActorSection section, Godot.Collections.Array<Settings> entries, ActorSection replacement)
    {
        using var argument_entries = Variant.From(entries);
        _operations.delete_section_state(this,section,argument_entries.AsGodotArray(),replacement);
    }
    public void _restore_section_state(ActorSection section, int index, Godot.Collections.Array<Settings> entries, ActorSection replacement, string previous_section, Godot.Collections.Array<string> selection)
    {
        using var argument_entries = Variant.From(entries);
        using var argument_selection = Variant.From(selection);
        _operations.restore_section_state(this,section,index,argument_entries.AsGodotArray(),replacement,previous_section,argument_selection.AsGodotArray());
    }
    public Godot.Collections.Array<ActorClip> visible_clips()
    {
        return new Godot.Collections.Array<ActorClip>(_operations.visible_clips(this));
    }
    public void move_to_section(Godot.Collections.Array<string> actor_ids, string section_id)
    {
        using var argument_actor_ids = Variant.From(actor_ids);
        _operations.move_to_section(this,argument_actor_ids.AsGodotArray(),section_id);
    }
    public void _apply_section_move(Settings states, string section_id, bool forward)
    {
        _operations.apply_section_move(this,states,section_id,forward);
    }
    public override void _Notification(int what)
    {
        if (what == NotificationPredelete && GodotObject.IsInstanceValid(history)) history.Free();
    }
    public ActorClip? create_actor(ActorDefinition definition, double time, Settings initial_values)
    {
        return _operations.create_actor(this,definition,time,initial_values) as ActorClip;
    }
    public ActorClip? create_actor(ActorDefinition definition, double time) => create_actor(definition, time, new Settings());
    public ActorClip? instantiate_model(KiwiModelDocument document, string source_path, double start)
    {
        return _operations.instantiate_model(this,document,source_path,start) as ActorClip;
    }
    public ActorClip? instantiate_scene(ActorSceneData scene, ActorDefinition point_definition, double start, int layer, string name, string action_label)
    {
        return _operations.instantiate_scene(this,scene,point_definition,start,layer,name,action_label) as ActorClip;
    }
    public ActorClip? instantiate_scene(ActorSceneData scene, ActorDefinition point_definition, double start, int layer) => instantiate_scene(scene, point_definition, start, layer, "Scene", "Instantiate Scene");
    public ActorClip? instantiate_scene(ActorSceneData scene, ActorDefinition point_definition, double start, int layer, string name) => instantiate_scene(scene, point_definition, start, layer, name, "Instantiate Scene");
    public void delete_selected()
    {
        _operations.delete_selected(this);
    }
    public void _delete_selected_group()
    {
        _operations.delete_selected_group(this);
    }
    public void move_clip(string id, double time, int layer)
    {
        _operations.move_clip(this,id,time,layer);
    }
    public void move_clip(string id, double time) => move_clip(id, time, -1);
    public void select(string id, bool additive)
    {
        _operations.select(this,id,additive);
    }
    public void select(string id) => select(id, false);
    public void select_all()
    {
        _operations.select_all(this);
    }
    public void set_selection(Godot.Collections.Array<string> ids, string primary_id)
    {
        using var argument_ids = Variant.From(ids);
        _operations.set_selection(this,argument_ids.AsGodotArray(),primary_id);
    }
    public void set_selection(Godot.Collections.Array<string> ids) => set_selection(ids, "");
    public void toggle_selection(string id)
    {
        _operations.toggle_selection(this,id);
    }
    public bool is_selected(string id)
    {
        return _operations.is_selected(this,id);
    }
    public Godot.Collections.Array<ActorData> selected_actors()
    {
        return new Godot.Collections.Array<ActorData>(_operations.selected_actors(this));
    }
    public ActorClip? split_clip(string id, double time)
    {
        return _operations.split_clip(this,id,time) as ActorClip;
    }
    public void _apply_split(ActorClip left, double length, ActorData actor, ActorClip right, string focus)
    {
        _operations.apply_split(this,left,length,actor,right,focus);
    }
    public void _undo_split(ActorClip left, double duration, string right_id, Godot.Collections.Array<string> selection, string focus)
    {
        using var argument_selection = Variant.From(selection);
        _operations.undo_split(this,left,duration,right_id,argument_selection.AsGodotArray(),focus);
    }
    public Godot.Collections.Array<ActorClip> paste_snapshots(Godot.Collections.Array<Settings> snapshots, double time, int preferred_layer, Godot.Collections.Array<string> target_parent_ids, string action_name, bool preserve_external_parents)
    {
        using var argument_snapshots = Variant.From(snapshots);
        using var argument_target_parent_ids = Variant.From(target_parent_ids);
        return new Godot.Collections.Array<ActorClip>(_operations.paste_snapshots(this,argument_snapshots.AsGodotArray(),time,preferred_layer,argument_target_parent_ids.AsGodotArray(),action_name,preserve_external_parents));
    }
    public Godot.Collections.Array<ActorClip> paste_snapshots(Godot.Collections.Array<Settings> snapshots, double time, int preferred_layer) => paste_snapshots(snapshots, time, preferred_layer, new Godot.Collections.Array<string>(), "Paste Actors", false);
    public Godot.Collections.Array<ActorClip> paste_snapshots(Godot.Collections.Array<Settings> snapshots, double time, int preferred_layer, Godot.Collections.Array<string> target_parent_ids) => paste_snapshots(snapshots, time, preferred_layer, target_parent_ids, "Paste Actors", false);
    public Godot.Collections.Array<ActorClip> paste_snapshots(Godot.Collections.Array<Settings> snapshots, double time, int preferred_layer, Godot.Collections.Array<string> target_parent_ids, string action_name) => paste_snapshots(snapshots, time, preferred_layer, target_parent_ids, action_name, false);
    public string _copy_name(string original)
    {
        return _operations.copy_name(original);
    }
    public int _find_free_paste_layer(Godot.Collections.Array<Settings> group, Godot.Collections.Array<Settings> pending, int preferred)
    {
        using var argument_group = Variant.From(group);
        using var argument_pending = Variant.From(pending);
        return _operations.find_free_paste_layer(this,argument_group.AsGodotArray(),argument_pending.AsGodotArray(),preferred);
    }
    public bool _paste_group_fits(Godot.Collections.Array<Settings> group, Godot.Collections.Array<Settings> pending, int @base)
    {
        using var argument_group = Variant.From(group);
        using var argument_pending = Variant.From(pending);
        return _operations.paste_group_fits(this,argument_group.AsGodotArray(),argument_pending.AsGodotArray(),@base);
    }
    public int layer_count()
    {
        return _operations.layer_count(this);
    }
    public bool can_place(string id, double start, double duration, int layer)
    {
        return _operations.can_place(this,id,start,duration,layer);
    }
    public double nearest_free_start(string id, double desired, double duration, int layer)
    {
        return _operations.nearest_free_start(this,id,desired,duration,layer);
    }
    public bool can_place_group(Settings states)
    {
        return _operations.can_place_group(this,states);
    }
    public double nearest_free_group_delta(Godot.Collections.Array<string> ids, double desired_delta, int layer_delta)
    {
        using var argument_ids = Variant.From(ids);
        return _operations.nearest_free_group_delta(this,argument_ids.AsGodotArray(),desired_delta,layer_delta);
    }
    public void commit_clip_states(Settings states, string action_name, string primary_id)
    {
        _operations.commit_clip_states(this,states,action_name,primary_id);
    }
    public bool preview_clip_states(Settings states, string primary_id)
    {
        return _operations.preview_clip_states(this,states,primary_id);
    }
    public void commit_clip_state_preview(Settings original, Settings final_states, string action_name, string primary_id)
    {
        _operations.commit_clip_state_preview(this,original,final_states,action_name,primary_id);
    }
    public void _set_clip_states(Settings states, string primary_id)
    {
        _operations.set_clip_states(this,states,primary_id);
    }
    public ActorData? selected_actor()
    {
        return _operations.selected_actor(this) as ActorData;
    }
    public void rename_actor(ActorData actor, string name)
    {
        _operations.rename_actor(this,actor,name);
    }
    public void set_parent(string child_id, string parent_id, bool preserve_world)
    {
        _operations.set_parent(this,child_id,parent_id,preserve_world);
    }
    public void set_parent(string child_id, string parent_id) => set_parent(child_id, parent_id, true);
    public void unparent(string child_id)
    {
        _operations.set_parent(this,child_id,"",true);
    }
    public void parent_many(Godot.Collections.Array<string> child_actor_ids, string parent_id)
    {
        using var argument_child_actor_ids = Variant.From(child_actor_ids);
        _operations.parent_many(this,argument_child_actor_ids.AsGodotArray(),parent_id);
    }
    public void unparent_many(Godot.Collections.Array<string> actor_ids)
    {
        using var argument_actor_ids = Variant.From(actor_ids);
        _operations.unparent_many(this,argument_actor_ids.AsGodotArray());
    }
    public void _commit_parent_states(Settings states, string action_name)
    {
        _operations.commit_parent_states(this,states,action_name);
    }
    public void _apply_parent_states(Settings states, bool use_new_state)
    {
        _operations.apply_parent_states(this,states,use_new_state);
    }
    public bool can_set_parent(string child_id, string parent_id)
    {
        return _operations.can_set_parent(this,child_id,parent_id);
    }
    public ActorData? actor_for_id(string id)
    {
        return _operations.actor_for_id(this,id) as ActorData;
    }
    public ActorClip? clip_for_actor_id(string actor_id)
    {
        return _operations.clip_for_actor_id(this,actor_id) as ActorClip;
    }
    public string actor_path(string actor_id)
    {
        return _operations.actor_path(this,actor_id);
    }
    public void _set_parent_state(ActorData actor, string parent_id, Settings transform_values)
    {
        _operations.set_parent_state(this,actor,parent_id,transform_values);
    }
    public void _apply_parent_state_silent(ActorData actor, string parent_id, Settings transform_values)
    {
        _operations.apply_parent_state_silent(actor,parent_id,transform_values);
    }
    public Settings _transform_values(ActorData actor)
    {
        return _operations.transform_values(actor);
    }
    public Transform3D _local_transform(ActorData actor)
    {
        return _operations.local_transform(actor);
    }
    public Transform3D world_transform_for(string actor_id)
    {
        return _operations.world_transform_for(this,actor_id);
    }
    public Transform3D _world_transform_for(string actor_id, Settings visited)
    {
        return _operations.world_transform_visited(this,actor_id,visited);
    }
    public Transform2D world_transform_2d_for(string actor_id)
    {
        return _operations.world_transform_2d_for(this,actor_id);
    }
    public Transform2D _world_transform_2d_for(string actor_id, Settings visited)
    {
        return _operations.world_transform_2d_visited(this,actor_id,visited);
    }
    public Settings _values_for_preserved_world(ActorData actor, string new_parent_id)
    {
        return _operations.values_for_preserved_world(this,actor,new_parent_id);
    }
    public void _set_name(ActorData actor, string name)
    {
        _operations.set_name(this,actor,name);
    }
    public void trim_clip(string id, double start, double duration)
    {
        _operations.trim_clip(this,id,start,duration);
    }
    public void _set_timing(ActorClip clip, double start, double duration, double offset)
    {
        _operations.set_timing(this,clip,start,duration,offset);
    }
    public void edit_property(ActorData actor, ActorDefinition definition, StringName key, Variant value)
    {
        _operations.edit_property(this,actor,definition,key,value);
    }
    public void preview_property(ActorData actor, ActorDefinition definition, StringName key, Variant value)
    {
        _operations.preview_property(this,actor,definition,key,value);
    }
    public void commit_property_preview(ActorData actor, ActorDefinition definition, StringName key, Variant original, Variant final_value)
    {
        _operations.commit_property_preview(this,actor,definition,key,original,final_value);
    }
    public void _set_property(ActorData actor, StringName key, Variant value)
    {
        _operations.set_property(this,actor,key,value);
    }
    public void edit_object_property(ActorData actor, ActorObjectData @object, ActorObjectDefinition definition, StringName key, Variant value)
    {
        _operations.edit_object_property(this,actor,@object,definition,key,value);
    }
    public bool _values_equal(Variant left, Variant right)
    {
        return _operations.values_equal(left,right);
    }
    public void preview_object_property(ActorData actor, ActorObjectData @object, ActorObjectDefinition definition, StringName key, Variant value)
    {
        _operations.preview_object_property(this,actor,@object,definition,key,value);
    }
    public void commit_object_property_preview(ActorData actor, ActorObjectData @object, ActorObjectDefinition definition, StringName key, Variant original, Variant final_value)
    {
        _operations.commit_object_property_preview(this,actor,@object,definition,key,original,final_value);
    }
    public void _set_object_property(ActorObjectData @object, StringName key, Variant value)
    {
        _operations.set_object_property(this,@object,key,value);
    }
    public ActorClip? selected_clip()
    {
        return _operations.selected_clip(this) as ActorClip;
    }
    public void undo()
    {
        _operations.undo(this);
    }
    public void redo()
    {
        _operations.redo(this);
    }
    public int _index_of(string id)
    {
        return _operations.index_of(this,id);
    }
    public void _insert(ActorData actor, ActorClip clip, int index, string selection)
    {
        _operations.insert(this,actor,clip,index,selection);
    }
    public void _remove(string id, string selection)
    {
        _operations.remove(this,id,selection);
    }
    public void _remove_many(Godot.Collections.Array<string> ids, Settings child_states)
    {
        using var argument_ids = Variant.From(ids);
        _operations.remove_many(this,argument_ids.AsGodotArray(),child_states);
    }
    public void _insert_many(Godot.Collections.Array<Settings> removed, Godot.Collections.Array<string> selection, Settings child_states)
    {
        using var argument_removed = Variant.From(removed);
        using var argument_selection = Variant.From(selection);
        _operations.insert_many(this,argument_removed.AsGodotArray(),argument_selection.AsGodotArray(),child_states);
    }
    public void _insert_copies(Godot.Collections.Array<Settings> entries, Godot.Collections.Array<string> selection)
    {
        using var argument_entries = Variant.From(entries);
        using var argument_selection = Variant.From(selection);
        _operations.insert_copies(this,argument_entries.AsGodotArray(),argument_selection.AsGodotArray());
    }
    public void _remove_copies(Godot.Collections.Array<string> ids, Godot.Collections.Array<string> previous_selection)
    {
        using var argument_ids = Variant.From(ids);
        using var argument_previous_selection = Variant.From(previous_selection);
        _operations.remove_copies(this,argument_ids.AsGodotArray(),argument_previous_selection.AsGodotArray());
    }
    public void _remove_with_child_states(string id, string selection, Settings child_states, bool use_new_state)
    {
        _operations.remove_with_child_states(this,id,selection,child_states,use_new_state);
    }
    public void _insert_with_child_states(ActorData actor, ActorClip clip, int index, string selection, Settings child_states)
    {
        _operations.insert_with_child_states(this,actor,clip,index,selection,child_states);
    }
    public void _set_start(ActorClip clip, double time, int layer)
    {
        _operations.set_start(this,clip,time,layer);
    }
    public void _set_single_selection(string id)
    {
        _operations.set_single_selection(this,id);
    }
    public void _make_primary(string id)
    {
        _operations.make_primary(this,id);
    }
}
