using Godot;
using System;
using GArray=Godot.Collections.Array;
using Settings=Godot.Collections.Dictionary;
public partial class AudioWorkspaceOperations
{
    private static CSharpScript RecorderSchema()=>GD.Load<CSharpScript>("res://scripts/actors/core/ActorAudioRecorder.cs");
    public Settings requested_recording_preferences(Control o)
    {
        var preferences=Field<Node>(o,"recorder").Call("requested_preferences").AsGodotDictionary();using var config=new ConfigFile();if(config.Load("user://audio_workspace_recording.cfg")==Error.Ok&&config.GetValue("backing","override",false).AsBool()){preferences["monitor_timeline"]=config.GetValue("backing","monitor",false).AsBool();preferences["record_timeline"]=config.GetValue("backing","include",false).AsBool();}return preferences;
    }
    public bool save_recording_backing(Control o,bool overrideShared,bool monitor,bool include)
    {
        using var config=new ConfigFile();config.SetValue("backing","override",overrideShared);config.SetValue("backing","monitor",monitor);config.SetValue("backing","include",include);var error=config.Save("user://audio_workspace_recording.cfg");if(error==Error.Ok)return true;notice(o,"Could not save backing preferences: "+error);return false;
    }
    public bool record_request_owned(Control o,long token)=>token==o.Get("_record_generation").AsInt64()&&o.Get("_record_session").AsGodotObject()==Session(o)&&o.Get("_record_owner_document").AsGodotObject()==Document(o)&&!o.Get("_record_cancel_requested").AsBool()&&o.IsInsideTree()&&o.IsVisibleInTree();
    public bool record_request_current(Control o,long token){if(!record_request_owned(o,token))return false;using var prepare=new AudioRecordingPrepareOperations();return prepare.signature(Document(o))==o.Get("_record_signature").AsString();}
    public bool record_backing_ready(Control o,long id)
    {
        var prepared=o.Get("_record_prepared").AsGodotObject();if(id==0)return prepared==null;return prepared!=null&&unchecked((long)prepared.GetInstanceId())==id&&prepared.Call("valid").AsBool()&&Field<Node>(o,"playback").Call("recording_file_ready",prepared).AsBool();
    }
    private static void ResetRecordRequest(Control o)
    {
        o.Set("_record_busy",false);o.Set("_record_phase","idle");foreach(string key in new[]{"_record_session","_record_document","_record_owner_document"})o.Set(key,default(Variant));o.Set("_record_preferences",new Settings());o.Set("_record_signature","");Field<Button>(o,"record_button").Text="● Record";
    }
    private static void ClearLoopBacking(Control o){o.Set("_record_loop_preview",default(Variant));o.Set("_record_loop_signature","");}
    public void abort_record_preparation(Control o,long token,string message)
    {
        if(token!=o.Get("_record_generation").AsInt64())return;var playback=Field<Node>(o,"playback");Dict(playback,"_track_effects").Clear();if(o.Get("_record_prepared").AsGodotObject()!=null)playback.Call("stop",false);o.Set("_record_prepared",default(Variant));ClearLoopBacking(o);ResetRecordRequest(o);if(o.IsInsideTree()){playback.Set("exact_required",requires_exact_preview(o));playback.Call("set_document",Document(o));}if(message.Length>0&&!o.Get("_record_cancel_requested").AsBool())notice(o,message);
    }
    public void cancel_record_preparation(Control o)
    {
        o.Set("_record_cancel_requested",true);var playback=Field<Node>(o,"playback");if(o.Get("_record_prepared").AsGodotObject()!=null)playback.Call("stop",false);o.Set("_record_prepared",default(Variant));ClearLoopBacking(o);string phase=o.Get("_record_phase").AsString();if(phase is "preparing" or "priming" or "countdown"){Field<Node>(o,"jobs").Call("cancel_kind","record_prepare");o.Set("_record_generation",o.Get("_record_generation").AsInt64()+1);ResetRecordRequest(o);Field<Label>(o,"status").Text="Recording preparation cancelled.";if(o.IsInsideTree()){playback.Set("exact_required",requires_exact_preview(o));playback.Call("set_document",Document(o));}}else if(phase=="starting")Field<Label>(o,"status").Text="Cancelling recording device startup...";
    }
    public void begin_record_capture(Control o,long token,RefCounted? prepared)
    {
        if(token!=o.Get("_record_generation").AsInt64())return;o.Set("_record_prepared",prepared is null?default(Variant):Variant.From(prepared));o.Call("_begin_record_capture_owned",token,prepared==null?0:unchecked((long)prepared.GetInstanceId()));
    }
    public void restart_record_loop(Control o,WeakRef owner,long generation,WeakRef document)
    {
        using var ownerRef=owner.GetRef();using var documentRef=document.GetRef();if(ownerRef.AsGodotObject()!=Session(o)||documentRef.AsGodotObject()!=Document(o)||generation!=o.Get("_record_generation").AsInt64()||o.Get("_record_cancel_requested").AsBool()||!o.Get("_record_loop").AsBool()||o.Get("_record_phase").AsString()!="idle"||!o.IsVisibleInTree()){if(o.Get("_record_phase").AsString()=="idle")ClearLoopBacking(o);return;}toggle_recording(o,false);
    }
    public void toggle_recording(Control o,bool restartNext)
    {
        o.Call("_close_silence_review");finish_automation_pass(o,"Audio recording requested");if(o.Get("_record_busy").AsBool()){cancel_record_preparation(o);return;}var recorder=Field<Node>(o,"recorder");if(recorder.Get("recording").AsBool()){o.Call("_finish_recorded_take",restartNext);return;}var track=Document(o).Call("track_for_id",Session(o).Get("selected_track")).AsGodotDictionary();if(track.Count==0||Get(track,"locked",false).AsBool()||_frameLanes.is_lane(track)){notice(o,"Select an unlocked audio or instrument track before recording.");return;}var preferences=requested_recording_preferences(o);o.Set("_record_preferences",preferences);string error=RecorderSchema().Call("preference_error",preferences).AsString();if(error.Length>0){notice(o,error);return;}finish_control_edits(o);Session(o).Call("commit");long token=o.Get("_record_generation").AsInt64()+1;o.Set("_record_generation",token);o.Set("_record_cancel_requested",false);o.Set("_record_failure","");o.Set("_record_busy",true);o.Set("_record_phase","countdown");o.Set("_record_session",Session(o));o.Set("_record_track",Session(o).Get("selected_track"));o.Set("_record_elapsed",0.0);o.Set("_record_owner_document",Document(o));var snapshot=Document(o).Call("snapshot").As<RefCounted>();o.Set("_record_document",snapshot);using var prepare=new AudioRecordingPrepareOperations();string signature=prepare.signature(Document(o));o.Set("_record_signature",signature);double start=Position(o),duration=0;if(o.Get("_record_loop").AsBool()&&Document(o).Get("loop_end").AsDouble()>Document(o).Get("loop_start").AsDouble()){start=Document(o).Get("loop_start").AsDouble();duration=Document(o).Get("loop_end").AsDouble()-start;}o.Set("_record_start",start);o.Set("_record_cycle_duration",duration);cancel_exact_playback(o);Field<Node>(o,"playback").Call("stop",false);Field<AudioStreamPlayer>(o,"preview_player").Stop();if(RecorderSchema().Call("backing_requested",preferences).AsBool()&&requires_exact_preview(o)){var previous=o.Get("_record_loop_preview").AsGodotObject();if(duration>0&&previous!=null&&o.Get("_record_loop_signature").AsString()==signature&&previous.Call("valid").AsBool()){begin_record_capture(o,token,previous as RefCounted);return;}ClearLoopBacking(o);o.Set("_record_phase","preparing");Field<Button>(o,"record_button").Text="Cancel preparation";Field<Label>(o,"status").Text="Preparing processed timeline before recording...";double until=duration>0?start+duration:-1;Work(o,"record_prepare",token,job=>{using var worker=new AudioRecordingPrepareOperations();return worker.prepare(snapshot,start,until,job);});}else{ClearLoopBacking(o);begin_record_capture(o,token,null);}
    }
}
