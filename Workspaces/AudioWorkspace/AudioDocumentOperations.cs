using Godot;
using System;
using GArray = Godot.Collections.Array;
using Settings = Godot.Collections.Dictionary;

public partial class AudioDocumentOperations : RefCounted
{
    private static Variant Get(Settings d,string key,Variant fallback=default)=>d.TryGetValue(new StringName(key),out var value)?value:fallback;
    private static GArray Actors(GodotObject o)=>o.Get("actors").AsGodotArray();
    private static GArray Clips(GodotObject o)=>o.Get("clips").AsGodotArray();
    private static GArray Tracks(GodotObject o)=>o.Get("tracks").AsGodotArray();
    private static readonly string[] Palette={"63d9bc","80aaff","e4b868","d695ec","ef8588","73cddd"};
    private static string Id(){using var crypto=new Crypto();return Convert.ToHexString(crypto.GenerateRandomBytes(16)).ToLowerInvariant();}
    private static RefCounted NewDocument()=>new KiwiAudioDocument();
    public Settings add_track(GodotObject o,string label,string kind)
    {
        var tracks=Tracks(o);var track=new Settings{["id"]=Id(),["name"]=label,["kind"]=kind,["color"]=Color.FromHtml(Palette[tracks.Count%Palette.Length]),["volume_db"]=0.0,["pan"]=0.0,["mute"]=false,["solo"]=false,["locked"]=false,["group"]="",["output"]="",["sends"]=new GArray(),["effects"]=new GArray(),["automation"]=new Settings(),["instrument"]=new Settings{["id"]="poly"}};tracks.Add(track);return track;
    }
    public Settings track_for_id(GodotObject o,string id){foreach(var raw in Tracks(o)){var track=raw.AsGodotDictionary();if(Get(track,"id","").AsString()==id)return track;}return new Settings();}
    public GodotObject? actor_for_clip(GodotObject o,string id){var clips=Clips(o);var actors=Actors(o);for(int i=0;i<Math.Min(clips.Count,actors.Count);++i){var clip=clips[i].AsGodotObject();if(clip!=null&&clip.Get("id").AsString()==id)return actors[i].AsGodotObject();}return null;}
    public GodotObject? clip_for_id(GodotObject o,string id){foreach(var raw in Clips(o)){var clip=raw.AsGodotObject();if(clip!=null&&clip.Get("id").AsString()==id)return clip;}return null;}
    public Settings track_for_clip(GodotObject o,string id){var actor=actor_for_clip(o,id);return actor==null?new Settings():track_for_id(o,Get(actor.Get("values").AsGodotDictionary(),"track_id","").AsString());}
    public RefCounted conductor(GodotObject o)=>KiwiAudioConductor.create(o.Get("tempo"),o.Get("time_signature"),o.Get("tempo_points"),o.Get("meter_points"));
    public double note_tempo(GodotObject o)=>o.Get("note_base_tempo").AsDouble()>0?o.Get("note_base_tempo").AsDouble():o.Get("tempo").AsDouble();
    public Vector2I note_meter(GodotObject o)=>o.Get("note_base_meter").AsVector2I()!=Vector2I.Zero?o.Get("note_base_meter").AsVector2I():o.Get("time_signature").AsVector2I();
    public double arrangement_tempo(GodotObject o){double fallback=note_tempo(o);var raw=Get(o.Get("composer_settings").AsGodotDictionary(),"tempo",fallback);double value=raw.VariantType is Variant.Type.Int or Variant.Type.Float?raw.AsDouble():fallback;return Math.Clamp(double.IsFinite(value)?value:fallback,20,400);}
    public double duration(GodotObject o){double result=0;foreach(var raw in Clips(o)){var clip=raw.AsGodotObject();if(clip!=null)result=Math.Max(result,clip.Get("start_time").AsDouble()+clip.Get("duration").AsDouble());}double tempo=arrangement_tempo(o);foreach(var raw in o.Get("sections").AsGodotArray()){var section=raw.AsGodotDictionary();result=Math.Max(result,(Get(section,"start",0).AsDouble()+Get(section,"duration",0).AsDouble())*60/tempo);}return result;}
    public RefCounted snapshot(GodotObject o)
    {
        var copy=NewDocument();foreach(string key in new[]{"version","title","tempo","time_signature","note_base_tempo","note_base_meter","key","scale","loop_start","loop_end","loop_enabled","output_path","_portable_root"})copy.Set(key,o.Get(key));
        foreach(string key in new[]{"tempo_points","meter_points","tracks","markers","sections","chords","takes"})copy.Set(key,o.Get(key).AsGodotArray().Duplicate(true));foreach(string key in new[]{"composer_settings","master","presets","workspace_state","scene_binding","portable_media"})copy.Set(key,o.Get(key).AsGodotDictionary().Duplicate(true));
        var actors=Actors(copy);foreach(var raw in Actors(o)){var actor=raw.AsGodotObject();var item=new ActorData();foreach(string key in new[]{"id","type_id","display_name","parent_id","section_id","show_timeline_children","link_timeline_children","schema_version"})item.Set(key,actor.Get(key));item.Set("values",actor.Get("values").AsGodotDictionary().Duplicate(true));var animations=item.Get("animation_tracks").AsGodotArray();foreach(var track in actor.Get("animation_tracks").AsGodotArray())animations.Add(track.AsGodotObject().Call("copy_track"));actors.Add(item);}var clips=Clips(copy);foreach(var raw in Clips(o))clips.Add(raw.As<Resource>().Duplicate(false));return copy;
    }
    public string midi_timing_error(GodotObject o,GArray additional,string replaced,Variant legacyOverride)
    {
        var sources=new GArray();foreach(var raw in Actors(o)){var actor=raw.AsGodotObject();if(actor!=null&&(replaced.Length==0||actor.Get("id").AsString()!=replaced))sources.Add(actor.Get("values"));}foreach(var source in additional)sources.Add(source);var legacy=legacyOverride.VariantType==Variant.Type.Nil?o.Get("composer_settings").AsGodotDictionary():legacyOverride.AsGodotDictionary();using var maps=new AudioTempoMapOperations();return maps.validate_budget(sources,legacy);
    }
    public GodotObject playback_model(GodotObject o){var model=new ActorTimeline();model.Set("actors",o.Get("actors"));model.Set("clips",o.Get("clips"));return model;}
    public RefCounted from_source(Variant value,string label){var document=NewDocument();document.Set("title",label.Length>0?label:"Untitled Audio");var track=add_track(document,"Audio","audio");if(value.VariantType!=Variant.Type.Nil&&GD.Load<CSharpScript>("res://scripts/actors/core/ActorAudio.cs").Call("file_duration",value).AsDouble()>0)insert_source(document,value,track["id"].AsString(),0,label);return document;}
    public GodotObject? insert_source(GodotObject o,Variant value,string trackId,double at,string label)
    {
        var track=track_for_id(o,trackId);if(track.Count==0||Get(track,"kind","").AsString()=="automation")return null;double seconds=GD.Load<CSharpScript>("res://scripts/actors/core/ActorAudio.cs").Call("file_duration",value).AsDouble();if(!double.IsFinite(seconds)||seconds<=0)return null;
        var actor=new ActorData();actor.Set("id",Id());actor.Set("type_id",new StringName("audio"));actor.Set("display_name",label.Length>0?label:value.VariantType==Variant.Type.String?value.AsString().GetFile():"Audio");var values=new Settings();foreach(var pair in new Settings{["audio"]=value,["track_id"]=trackId,["volume_db"]=0.0,["pitch"]=1.0,["muted"]=false,["fade_in"]=Math.Min(.003,seconds*.1),["fade_out"]=Math.Min(.005,seconds*.1),["pan"]=0.0,["effects"]=new GArray(),["automation"]=new Settings(),["notes"]=new GArray(),["generator"]=new Settings(),["reverse"]=false,["loop"]=false,["source_duration"]=seconds})values[new StringName(pair.Key.AsString())]=pair.Value;actor.Set("values",values);
        var clip=new ActorClip();clip.Set("id",Id());clip.Set("actor_id",actor.Get("id"));clip.Set("start_time",Math.Max(0,at));clip.Set("duration",Math.Max(0,seconds));clip.Set("layer",Tracks(o).IndexOf(track));Actors(o).Add(actor);Clips(o).Add(clip);return clip;
    }
}
