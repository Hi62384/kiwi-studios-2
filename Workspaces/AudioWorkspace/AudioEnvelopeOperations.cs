using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class AudioSourceCacheOperations
{
    private static bool Cancelled(RefCounted? token)=>token!=null&&token.Call("is_cancelled").AsBool();
    public Settings build_envelope(AudioStream? stream,RefCounted? token)
    {
        int rate=(int)AudioServer.GetMixRate();double seconds=stream?.GetLength()??0;Settings Empty(long stride,double duration)=>new() {["levels"]=new GArray(),["rate"]=rate,["stride"]=stride,["duration"]=duration,["bytes"]=0};if(seconds<=0||!double.IsFinite(seconds))return Empty(256,0);long stride=Math.Max(256,(long)Math.Ceiling(seconds*rate/262144));var left=new List<Vector2>();var right=new List<Vector2>();using var playback=stream!.InstantiatePlayback();if(playback==null)return Empty(stride,seconds);playback.Start();var low=Vector2.One;var high=-Vector2.One;int frames=0;long cursor=0,total=(long)(seconds*rate);try{while(cursor<total){if(Cancelled(token))return new Settings {["levels"]=new GArray(),["rate"]=rate,["duration"]=seconds,["bytes"]=0,["cancelled"]=true};var samples=playback.MixAudio(1,(int)Math.Min(16384,total-cursor));if(samples.Length==0)break;foreach(var sample in samples){low=low.Min(sample);high=high.Max(sample);frames++;cursor++;if(frames==stride){left.Add(new Vector2(low.X,high.X));right.Add(new Vector2(low.Y,high.Y));frames=0;low=Vector2.One;high=-Vector2.One;}}}if(frames>0){left.Add(new Vector2(low.X,high.X));right.Add(new Vector2(low.Y,high.Y));}}finally{playback.Stop();}return envelope_levels(left.ToArray(),right.ToArray(),stride,rate,seconds);
    }
    public Settings build_file_envelope(string path,Settings info,RefCounted? token)
    {
        using var file=Godot.FileAccess.Open(path,Godot.FileAccess.ModeFlags.Read);if(file==null)return new Settings {["missing"]=true,["levels"]=new GArray(),["bytes"]=0};long total=info["frames"].AsInt64();int rate=info["rate"].AsInt32();long stride=Math.Max(256,(long)Math.Ceiling((double)total/262144));var left=new List<Vector2>();var right=new List<Vector2>();var low=Vector2.One;var high=-Vector2.One;long cursor=0;int frames=0;using var pcm=new AudioPcmFileOperations();while(cursor<total){if(Cancelled(token))return new Settings {["cancelled"]=true};var samples=pcm.read_frames(file,info,cursor,(int)Math.Min(16384,total-cursor));if(samples.Length==0)return new Settings {["missing"]=true,["levels"]=new GArray(),["bytes"]=0};foreach(var sample in samples){low=low.Min(sample);high=high.Max(sample);frames++;cursor++;if(frames==stride){left.Add(new Vector2(low.X,high.X));right.Add(new Vector2(low.Y,high.Y));low=Vector2.One;high=-Vector2.One;frames=0;}}}if(frames>0){left.Add(new Vector2(low.X,high.X));right.Add(new Vector2(low.Y,high.Y));}if((long)Godot.FileAccess.GetModifiedTime(path)!=info["modified"].AsInt64())return new Settings {["cancelled"]=true};return envelope_levels(left.ToArray(),right.ToArray(),stride,rate,info["duration"].AsDouble());
    }
    public Settings envelope_levels(Vector2[] left,Vector2[] right,long stride,int rate,double seconds)
    {
        var levels=new GArray {new Settings {["left"]=left,["right"]=right,["stride"]=stride}};long bytes=(long)(left.Length+right.Length)*8;while(left.Length>1){var nextLeft=new Vector2[(left.Length+1)/2];var nextRight=new Vector2[nextLeft.Length];for(int index=0;index<left.Length;index+=2){int other=Math.Min(index+1,left.Length-1);nextLeft[index/2]=new Vector2(Math.Min(left[index].X,left[other].X),Math.Max(left[index].Y,left[other].Y));nextRight[index/2]=new Vector2(Math.Min(right[index].X,right[other].X),Math.Max(right[index].Y,right[other].Y));}left=nextLeft;right=nextRight;stride*=2;levels.Add(new Settings {["left"]=left,["right"]=right,["stride"]=stride});bytes+=(long)(left.Length+right.Length)*8;}return new Settings {["levels"]=levels,["rate"]=rate,["duration"]=seconds,["bytes"]=bytes};
    }
    public Vector2[] range_peaks(Settings entry,double start,double duration,int pixels,int channel)
    {
        if(!entry.TryGetValue("levels",out var raw)||raw.AsGodotArray().Count==0||pixels<=0)return Array.Empty<Vector2>();var levels=raw.AsGodotArray();int rate=entry["rate"].AsInt32();double perPixel=Math.Max(1,duration*rate/pixels);var level=levels[0].AsGodotDictionary();foreach(var candidateRaw in levels){var candidate=candidateRaw.AsGodotDictionary();if(candidate["stride"].AsDouble()<=perPixel)level=candidate;}var data=level[channel==0?"left":"right"].AsVector2Array();var result=new Vector2[pixels];if(data.Length==0)return result;double stride=level["stride"].AsDouble();for(int pixel=0;pixel<pixels;pixel++){int first=Math.Clamp((int)((start+duration*pixel/pixels)*rate/stride),0,data.Length-1),last=Math.Clamp((int)Math.Ceiling((start+duration*(pixel+1)/pixels)*rate/stride),first+1,data.Length);var extrema=Vector2.Zero;for(int index=first;index<last;index++){extrema.X=Math.Min(extrema.X,data[index].X);extrema.Y=Math.Max(extrema.Y,data[index].Y);}result[pixel]=extrema;}return result;
    }
}
