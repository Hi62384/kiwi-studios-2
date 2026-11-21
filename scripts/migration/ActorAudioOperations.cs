using Godot;
using System;
using Settings=Godot.Collections.Dictionary;

public partial class ActorAudioOperations : RefCounted
{
    public const long MaxCacheBytes=64L*1024*1024;
    public string path_key(string path)=>ProjectSettings.GlobalizePath(path).SimplifyPath();
    public Settings signature(string path){using var file=Godot.FileAccess.Open(path,Godot.FileAccess.ModeFlags.Read);return file==null?new Settings {["size"]=-1L,["modified"]=0L}:new Settings {["size"]=(long)file.GetLength(),["modified"]=(long)Godot.FileAccess.GetModifiedTime(path)};}
    public long retention_cost(AudioStream stream,long fileSize,string path)
    {
        long overhead=65536+path.Length*8L;if(stream is AudioStreamWav wav){double frames=Math.Max(0,Math.Ceiling(wav.GetLength()*wav.MixRate)),pcmBytes=frames*(wav.Stereo?2:1)*4;if(!double.IsFinite(pcmBytes)||pcmBytes>MaxCacheBytes)return MaxCacheBytes+1;return overhead+Math.Max(fileSize*2,(long)pcmBytes);}if(stream is AudioStreamMP3)return overhead+fileSize*2;if(stream is AudioStreamOggVorbis)return overhead+262144+fileSize*8;return MaxCacheBytes+1;
    }
    public double fade_gain(Resource actor,Resource clip,double time){var values=actor.Get("values").AsGodotDictionary();double duration=clip.Get("duration").AsDouble(),start=clip.Get("start_time").AsDouble(),fadeIn=Math.Clamp(values.TryGetValue(new StringName("fade_in"),out var inside)?inside.AsDouble():0,0,duration),fadeOut=Math.Clamp(values.TryGetValue(new StringName("fade_out"),out var outside)?outside.AsDouble():0,0,duration),gain=1;if(fadeIn>0)gain=Math.Min(gain,Math.Clamp((time-start)/fadeIn,0,1));if(fadeOut>0)gain=Math.Min(gain,Math.Clamp((start+duration-time)/fadeOut,0,1));if(values.TryGetValue(new StringName("fade_curve"),out var curve)&&curve.AsString()=="equal_power")gain=Math.Sin(gain*Math.PI*.5);return gain;}
    public bool valid(Resource actor,Resource clip,double duration,double offset){string type=actor.Get("type_id").AsString();if(type is not "audio" and not "video" and not "video_2d")return true;double sourceDuration=GD.Load<CSharpScript>("res://scripts/actors/core/ActorAudio.cs").Call("length",actor).AsDouble();return sourceDuration==0||(offset>=-.000001&&offset+duration*clip.Get("playback_speed").AsDouble()<=sourceDuration+.000001);}
}
