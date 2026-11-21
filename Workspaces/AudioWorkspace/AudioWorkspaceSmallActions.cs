using Godot;
using System;
using GArray=Godot.Collections.Array;
using Settings=Godot.Collections.Dictionary;
public partial class AudioWorkspaceOperations
{
    public void complete_midi_import(Control o,Settings context,string chosen)
    {
        if(Session(o)!=context["session"].AsGodotObject()||Session(o).Get("revision").AsInt64()!=context["revision"].AsInt64()){notice(o,"The composition changed while choosing a file. Repeat this action in the intended document.");return;}if(chosen.Length==0||chosen=="::empty-resource::")return;using var midi=new AudioMidiOperations();var result=midi.read(chosen);string error=Get(result,"error","").AsString();if(error.Length>0){notice(o,error);return;}apply_midi(o,result);
    }
    public void wave_detail(Control o,double start,double duration)
    {
        var waveform=Field<Control>(o,"waveform");var stream=waveform.Get("stream").As<AudioStream>();if(stream==null)return;int rate=waveform.Get("rate").AsInt32();long id=unchecked((long)stream.GetInstanceId());Work(o,"wave_detail",0,_=>{using var sources=new AudioSourceCacheOperations();var result=sources.decode(stream,rate,start,duration,3);result["start"]=start;result["source_id"]=id;return result;});
    }
    public void spectrogram(Control o)
    {
        var waveform=Field<Control>(o,"waveform");var stream=waveform.Get("stream").As<AudioStream>();if(stream==null)return;if(waveform.Get("spectrogram").AsGodotObject()!=null){waveform.Set("show_spectrogram",!waveform.Get("show_spectrogram").AsBool());waveform.QueueRedraw();return;}double start=waveform.Get("view_start").AsDouble(),duration=waveform.Get("view_duration").AsDouble();Work(o,"spectrogram",unchecked((long)stream.GetInstanceId()),job=>{using var analysis=new AudioAnalysisOperations();return analysis.spectrogram(stream,start,duration,256,128,job);});
    }
    public void context_menu(Control o,Vector2 at)
    {
        var menu=new PopupMenu();o.AddChild(menu);string[] actions={"Copy Clips","Paste Clips","Duplicate Clips","Delete Clips","Ripple Delete","Split At Playhead","Crossfade Clips","Render In Place","Analyze Clip","Relink Source","Add Effect"};foreach(string action in actions)menu.AddItem(action);menu.IdPressed+=index=>run_command(o,actions[(int)index]);menu.PopupHide+=menu.QueueFree;menu.Position=(Vector2I)at;menu.Popup();
    }
    public void set_scene_binding(Control o,bool bound){var button=o.Get("send_scene_button").As<Button>();if(button!=null)button.Text=bound?"Update Scene Actor":"To Scene";}
    public void record_preparation_finished(Control o,long token,Settings data)
    {
        if(token!=o.Get("_record_generation").AsInt64()||o.Get("_record_phase").AsString()!="preparing")return;if(!record_request_current(o,token)){abort_record_preparation(o,token,"The arrangement changed while preparing recording. Start the take again.");return;}string error=Get(data,"error","").AsString();var backing=Get(data,"backing").As<RefCounted>();if(error.Length>0||backing==null||!backing.Call("valid").AsBool()){abort_record_preparation(o,token,error.Length>0?error:"No valid processed timeline backing was prepared.");return;}if(o.Get("_record_cycle_duration").AsDouble()>0){o.Set("_record_loop_preview",backing);o.Set("_record_loop_signature",o.Get("_record_signature"));}begin_record_capture(o,token,backing);
    }
}
