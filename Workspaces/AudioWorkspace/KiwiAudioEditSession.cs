using Godot;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;
[GlobalClass]
public partial class KiwiAudioEditSession : RefCounted
{
    [Signal] public delegate void changedEventHandler();
    [Signal] public delegate void selection_changedEventHandler();
    public KiwiAudioDocument document {get;set;}=new();
    public UndoRedo history {get;set;}=new();
    public int history_limit {get;set;}=64;
    public long history_byte_budget {get;set;}=256L*1024*1024;
    public const int MAX_METADATA_ESTIMATE_VISITS=250000, MAX_METADATA_ESTIMATE_DEPTH=24;
    public long history_pruned_actions {get;set;}
    public Godot.Collections.Array<Settings> _history_footprints {get;set;}=new();
    public Godot.Collections.Array<Settings> _history_actions {get;set;}=new();
    public Godot.Collections.Array<string> selected_ids {get;set;}=new();
    public string selected_track {get;set;}="";
    public long revision {get;set;}
    public bool dirty {get;set;}
    public KiwiAudioDocument? _before {get;set;}
    public string _label {get;set;}="";
    public bool _pending_preview {get;set;}
    public Godot.Collections.Array<Settings> _clipboard {get;set;}=new();
    public GArray _effect_clipboard {get;set;}=new();
    public Variant last_action {get;set;}
    private readonly AudioEditSessionOperations _operations=new();
    public void open(KiwiAudioDocument value) => _operations.open(this, value);
    public void begin(string label) => _operations.begin(this, label);
    public void preview() => _operations.preview(this);
    public void commit() => _operations.commit(this);
    public static Settings _source_footprint(KiwiAudioDocument value, long metadata_limit)
    {using var _native_operations=new AudioEditSessionOperations();return _native_operations.source_footprint(value, metadata_limit);}
    public static long _metadata_estimate(KiwiAudioDocument value, long limit)
    {using var _native_operations=new AudioEditSessionOperations();return _native_operations.metadata_estimate(value, limit);}
    public static void _estimate_metadata_value(Variant value, GArray state, long depth)
    {using var _native_operations=new AudioEditSessionOperations();_native_operations.estimate_metadata_value(value, state, (int)depth);}
    public void cancel() => _operations.cancel(this);
    public void _restore(KiwiAudioDocument value) => _operations.restore(this, value);
    public void undo() => _operations.undo(this);
    public void redo() => _operations.redo(this);
    public void select(string id, bool additive) => _operations.select(this, id, additive);
    public void select(string id) => select(id, false);
    public void select_all() => _operations.select_all(this);
    public ActorClip? primary_clip() => _operations.primary(this, false).As<ActorClip>();
    public ActorData? primary_actor() => _operations.primary(this, true).As<ActorData>();
    public bool can_edit(string id) => _operations.can_edit(this, id);
    public void add_track(string kind, string label) => _operations.add_track(this, kind, label);
    public void add_track() => add_track("audio", "");
    public void add_track(string kind) => add_track(kind, "");
    public void delete_track(string id) => _operations.delete_track(this, id);
    public ActorClip? insert_source(Variant value, double at, string track_id, string label) => _operations.insert_source(this, value, at, track_id, label).As<ActorClip>();
    public ActorClip? insert_source(Variant value, double at) => insert_source(value, at, "", "");
    public ActorClip? insert_source(Variant value, double at, string track_id) => insert_source(value, at, track_id, "");
    public void delete_selected(bool ripple) => _operations.delete_selected(this, ripple);
    public void delete_selected() => delete_selected(false);
    public void copy() => _operations.copy(this);
    public void paste(double at, string target_track) => _operations.paste(this, at, target_track);
    public void paste(double at) => paste(at, "");
    public void duplicate_selected() => _operations.duplicate_selected(this);
    public void split_selected(double at) => _operations.split_selected(this, at);
    public static GArray shifted_curve(GArray points, double offset, double fallback)
    {using var _native_operations=new AudioEditSessionOperations();return _native_operations.shifted_curve(points, offset, fallback);}
    public static void shift_owner_automation(Settings owner, double offset)
    {using var _native_operations=new AudioEditSessionOperations();_native_operations.shift_owner_automation(owner, offset);}
    public bool edit_clip(string id, Settings changes) => _operations.edit_clip(this, id, changes);
    public void set_clip_value(StringName key, Variant value) => _operations.set_clip_value(this, key, value);
    public void move_selected(double delta, long track_delta) => _operations.move_selected(this, delta, (int)track_delta);
    public void move_selected(double delta) => move_selected(delta, 0);
    public void crossfade_selected(double seconds) => _operations.crossfade_selected(this, seconds);
    public void crossfade_selected() => crossfade_selected(0.04);
    public bool set_track_value(string id, string key, Variant value) => _operations.set_track_value(this, id, key, value);
    public void add_automation(Settings owner, string parameter, double at, double value) => _operations.add_automation(owner, parameter, at, value);
    public void change_tempo(double bpm) => _operations.change_tempo(this, bpm);
    public void change_meter(Vector2I signature) => _operations.change_meter(this, signature);
    public string set_conductor(double bpm, Vector2I signature, GArray tempos, GArray meters) => _operations.set_conductor(this, bpm, signature, tempos, meters);
    public string retime_note_sources(double bpm) => _operations.retime_note_sources(this, bpm);
    public static double note_source_tempo(ActorData actor, KiwiAudioDocument document)
    {using var _native_operations=new AudioEditSessionOperations();return _native_operations.note_source_tempo(actor, document);}
    public static Vector2I note_source_meter(ActorData actor, KiwiAudioDocument document)
    {using var _native_operations=new AudioEditSessionOperations();return _native_operations.note_source_meter(actor, document);}
    public static bool is_note_source(ActorData actor)
    {using var _native_operations=new AudioEditSessionOperations();return _native_operations.is_note_source(actor);}
    public static void apply_note_render(ActorClip clip, ActorData actor, AudioStreamWav stream, string signature)
    {using var _native_operations=new AudioEditSessionOperations();_native_operations.apply_note_render(clip, actor, stream, signature);}
    public void copy_effects(GArray effects) => _operations.copy_effects(this, effects);
    public GArray pasted_effects() => _operations.pasted_effects(this);
    public static string note_signature(ActorData actor, KiwiAudioDocument document)
    {using var _native_operations=new AudioEditSessionOperations();return _native_operations.note_signature(actor, document);}
    public static AudioStreamWav? render_note_source(GArray notes, Settings instrument, double bpm, Settings step_settings, double pattern_beats, GArray tempos, double tempo_scale, RefCounted? job, GArray sustain_events)
    {using var _native_operations=new AudioEditSessionOperations();return _native_operations.render_note_source(notes, instrument, bpm, step_settings, pattern_beats, tempos, tempo_scale, job, sustain_events) as AudioStreamWav;}
    public static string render_current_notes(KiwiAudioDocument document, RefCounted? job, GArray clip_ids)
    {using var _native_operations=new AudioEditSessionOperations();return _native_operations.render_current_notes(document, job, clip_ids);}
    public string replace_rendered_clips(GArray selection, string track_id, AudioStream stream) => _operations.replace_rendered_clips(this, selection, track_id, stream);
    public static string audio_source_key(Variant value)
    {using var _native_operations=new AudioEditSessionOperations();return _native_operations.audio_source_key(value);}
    public Godot.Collections.Array<string> audio_source_clips(string id) => new Godot.Collections.Array<string>(_operations.audio_source_clips(this, id));
    public static Settings _relink_file_signature(string path)
    {using var _native_operations=new AudioEditSessionOperations();return _native_operations.relink_file_signature(path);}
    public static Settings probe_audio_relink(string path, RefCounted? job)
    {using var _native_operations=new AudioEditSessionOperations();return _native_operations.probe_audio_relink(path, job);}
    public string audio_relink_problem(GArray ids, string expected_source, Settings replacement) => _operations.audio_relink_problem(this, ids, expected_source, replacement);
    public string relink_audio_sources(GArray ids, string expected_source, Settings replacement) => _operations.relink_audio_sources(this, ids, expected_source, replacement);
    public static string silence_source_identity(ActorData actor)
    {using var _native_operations=new AudioEditSessionOperations();return _native_operations.silence_source_identity(actor);}
    public static GArray _silence_geometry(ActorClip clip, ActorData actor)
    {using var _native_operations=new AudioEditSessionOperations();return _native_operations.silence_geometry(clip, actor);}
    public string _silence_reason(string id) => _operations.silence_reason(this, id);
    public Settings create_silence_plan(string id, GArray silences, double source_duration, double keep, string identity) => _operations.create_silence_plan(this, id, silences, source_duration, keep, identity);
    public Settings preview_silence_plan(KiwiAudioSilencePlan plan, GArray remove, string scope) => _operations.preview_silence_plan(this, plan, remove, scope);
    public Settings preview_silence_plan(KiwiAudioSilencePlan plan, GArray remove) => preview_silence_plan(plan, remove, "clip");
    public Settings apply_silence_plan(KiwiAudioSilencePlan plan, GArray remove, string scope) => _operations.apply_silence_plan(this, plan, remove, scope);
    public Settings apply_silence_plan(KiwiAudioSilencePlan plan, GArray remove) => apply_silence_plan(plan, remove, "clip");
    public Settings silence_boundary(KiwiAudioSilencePlan plan, GArray remove, long region) => _operations.silence_boundary(this, plan, remove, (int)region);
    public void action(string label,Variant callback)
    {
        if (!EngineVariantDispatch.CallableValid(callback)) throw new System.ArgumentException("The audio edit action callback is invalid.",nameof(callback));
        bool nested=_before!=null;begin(label);
        using var args=new GArray();EngineVariantDispatch.InvokeCallable(callback,args);
        if (!nested) commit();
    }
    public static void restore_weak(Variant owner,KiwiAudioDocument value)
    {
        using var args=new GArray();var session=EngineVariantDispatch.Call(owner,"get_ref",args);
        if (session.VariantType!=Variant.Type.Object) return;
        using var values=new GArray{value};EngineVariantDispatch.Call(session,"_restore",values);
    }
    public static double automation_value(GArray points,double time,double fallback)
    {using var operations=new AudioEffectsOperations();return operations.automation_value(points,time,fallback);}
    public static RefCounted _native_edit()=>Engine.GetSingleton("KiwiNativeServices").Call("service","audio_edit_session").As<RefCounted>();
    public KiwiAudioSilencePlan _new_silence_plan()=>new();
    public override void _Notification(int what)
    {
        if (what==NotificationPredelete && GodotObject.IsInstanceValid(history)) {history.ClearHistory();history.Free();}
    }
}
