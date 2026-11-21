using Godot;
using System;
using System.Globalization;
using GArray=Godot.Collections.Array;
using Settings=Godot.Collections.Dictionary;
public partial class AudioWorkspaceOperations
{
    private readonly AudioPlaybackOperations _framePlayback=new();
    private readonly AudioAutomationRecordingOperations _frameAutomation=new();
    private readonly AudioAutomationLaneOperations _frameLanes=new();
    private readonly AudioWorkspaceLayoutOperations _frameLayout=new();
    public void process(Control o,double delta)
    {
        var portable=Dict(o,"_portable_context");if(portable.Count>0&&!o.Call("_portable_current",portable["token"].AsInt64()).AsBool())o.Call("_close_portable_review");o.Call("_recovery_tick");var silence=Dict(o,"_silence_review");if(silence.Count>0&&Time.GetTicksMsec()>=(ulong)o.Get("_silence_check_at").AsInt64()){o.Set("_silence_check_at",Time.GetTicksMsec()+250);if(!o.Call("_silence_review_current",silence["token"].AsInt64()).AsBool())o.Call("_close_silence_review");}if(!o.IsVisibleInTree())return;_frameLayout.sync(Field<Node>(o,"_layout"));var playback=Field<Node>(o,"playback");_frameAutomation.tick(Field<RefCounted>(o,"automation_recording"),playback.Get("position").AsDouble(),playback.Get("playing").AsBool());o.Call("_update_automation_readouts");var meters=Dict(o,"_meter_controls");foreach(var id in meters.Keys){bool supported=_framePlayback.meter_supported(playback,id.AsString());var levels=_framePlayback.meter(playback,id.AsString());var meter=meters[id].As<ProgressBar>();meter.Value=Math.Max(levels.X,levels.Y);meter.Modulate=supported?Colors.White:new Color(1,1,1,.3f);meter.TooltipText=supported?playback.Get("exact_preview_active").AsBool()?"Rendered post-fader route peak · 20 Hz (dBFS)":"Native route peak (dBFS)":"Route meter unavailable for this render. Meter preparation supports up to 32 routes and 10 minutes; master remains live.";}
        var recorder=Field<Node>(o,"recorder");if(!recorder.Get("recording").AsBool())return;string error=recorder.Call("capture_error").AsString();if(error.Length>0&&!o.Get("_record_busy").AsBool()){o.Set("_record_failure",error);o.Call("_finish_recorded_take",false);return;}double elapsed=o.Get("_record_elapsed").AsDouble()+delta;o.Set("_record_elapsed",elapsed);string caption=recorder.Get("monitor_timeline").AsBool()&&!recorder.Get("record_timeline").AsBool()?"Recording dry overdub":"Recording take";bool processed=o.Get("_record_processed_capture").AsBool();Field<Label>(o,"status").Text=caption+(processed?" · streamed backing":"")+" · "+elapsed.ToString("F1",CultureInfo.InvariantCulture)+" s";if(!playback.Get("playing").AsBool()){double position=o.Get("_record_start").AsDouble()+elapsed;playback.Set("position",position);var canvas=Field<Control>(o,"canvas");canvas.Set("playhead",position);canvas.QueueRedraw();}if(o.Get("_record_loop").AsBool()&&o.Get("_record_cycle_duration").AsDouble()>0&&!o.Get("_record_busy").AsBool()&&(processed?!playback.Get("playing").AsBool():elapsed>=o.Get("_record_cycle_duration").AsDouble()))o.Call("toggle_recording",true);
    }
    public bool mixer_target_editable(Control o,Settings target){var info=_frameLanes.resolve(Document(o),target);return info.Count>0&&!info["locked"].AsBool();}
    public bool automation_consumes(Control o,Settings target){var recording=Field<RefCounted>(o,"automation_recording");return recording.Get("mode").AsString()!="Read"&&_frameAutomation.matches(recording,target)&&_frameAutomation.editable(recording);}
    public void toggle_loop_transport(Control o,bool enabled){if(Field<Node>(o,"recorder").Get("recording").AsBool()||o.Get("_record_busy").AsBool()){Field<CheckButton>(o,"loop_button").SetPressedNoSignal(Document(o).Get("loop_enabled").AsBool());notice(o,"Stop or cancel the take before changing its transport loop.");return;}SessionAction(o,"Toggle loop",()=>Document(o).Set("loop_enabled",enabled));Field<Node>(o,"playback").Set("loop_enabled",enabled);}
    public Settings capture_pattern_view(Control pattern)=>new(){["zoom"]=pattern.Get("pixels_per_beat"),["row_height"]=pattern.Get("row_height"),["start_pitch"]=pattern.Get("start_pitch"),["scroll_beat"]=pattern.Get("scroll_beat"),["snap_beat"]=pattern.Get("snap_beat"),["selected"]=Items(pattern,"selected").Duplicate()};
    public void restore_pattern_view(Control o,Control pattern,Settings state)
    {
        pattern.Set("pixels_per_beat",Get(state,"zoom",90).AsDouble());pattern.Set("row_height",Get(state,"row_height",pattern==Field<Control>(o,"steps")?23:16).AsDouble());pattern.Set("start_pitch",Get(state,"start_pitch",84).AsInt32());pattern.Set("scroll_beat",Get(state,"scroll_beat",0).AsDouble());pattern.Set("snap_beat",Get(state,"snap_beat",.25).AsDouble());var selected=Items(pattern,"selected");selected.Clear();foreach(var id in Get(state,"selected",new GArray()).AsGodotArray())selected.Add(id);pattern.QueueRedraw();
    }
}
