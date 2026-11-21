using Godot;
using System;
using System.Collections.Generic;
using System.Globalization;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class AudioRouteMetersOperations : RefCounted
{
    public bool enabled(RefCounted document,Settings options){double start=options.TryGetValue("start",out var from)?from.AsDouble():0,seconds=options.TryGetValue("duration",out var duration)?duration.AsDouble():document.Call("duration").AsDouble()-start;return options.TryGetValue("route_meters",out var show)&&show.AsBool()&&document.Get("tracks").AsGodotArray().Count<=32&&seconds>0&&seconds<=600;}
    public Settings tap(string[] filterValues,string label,int index,string directory,double start,double duration,int rate)
    {
        var filters=new List<string>(filterValues);string output="meter_audio_"+index,branch="meter_branch_"+index;filters.Add("["+label+"]asplit=2["+output+"]["+branch+"]");string chain="atrim=start="+AudioEffectsOperations.FormatNumber(start)+":duration="+AudioEffectsOperations.FormatNumber(duration)+",asetpts=PTS-STARTPTS,asetnsamples=n="+Math.Max(1,rate/20)+":p=0,astats=metadata=1:reset=1:measure_perchannel=Peak_level:measure_overall=none";var paths=new GArray();for(int channel=0;channel<2;channel++){string path=directory.PathJoin("meter_"+index+"_"+channel+".txt");paths.Add(path);string escaped=path.Replace("\\","/",StringComparison.Ordinal).Replace(":","\\:",StringComparison.Ordinal).Replace("'","'\\''",StringComparison.Ordinal);chain+=",ametadata=mode=print:key=lavfi.astats."+(channel+1)+".Peak_level:file='"+escaped+"':direct=1";}filters.Add("["+branch+"]"+chain+",anullsink");return new Settings {["filters"]=filters.ToArray(),["label"]=output,["paths"]=paths};
    }
    public Settings read(GArray routes,double duration)
    {
        var result=new Settings();int frames=Math.Min(12002,(int)Math.Ceiling(duration*20)+2);foreach(var raw in routes){var route=raw.AsGodotDictionary();var levels=new Vector2[Math.Max(0,frames)];Array.Fill(levels,new Vector2(-80,-80));bool valid=true;for(int channel=0;channel<2;channel++){var paths=route["paths"];string path=paths.VariantType==Variant.Type.PackedStringArray?paths.AsStringArray()[channel]:paths.AsGodotArray()[channel].AsString();using var file=Godot.FileAccess.Open(path,Godot.FileAccess.ModeFlags.Read);if(file==null||file.GetLength()>4*1024*1024){valid=false;break;}int index=0;while(!file.EofReached()){string line=file.GetLine();if(line.StartsWith("frame:",StringComparison.Ordinal)){int marker=line.IndexOf("pts_time:",StringComparison.Ordinal);if(marker>=0){double.TryParse(line[(marker+9)..],NumberStyles.Float,CultureInfo.InvariantCulture,out var time);index=(int)Math.Round(time*20,MidpointRounding.AwayFromZero);}}else if(line.StartsWith("lavfi.astats.",StringComparison.Ordinal)&&index>=0&&index<frames){var pieces=line.Split('=');string text=pieces.Length>1?pieces[1].Trim():"";double db=double.TryParse(text,NumberStyles.Float,CultureInfo.InvariantCulture,out var number)&&double.IsFinite(number)?Math.Clamp(number,-80,24):-80;var value=levels[index];value[channel]=(float)db;levels[index]=value;}}}if(valid)result[route["id"].AsString()]=levels;}return result;
    }
}
