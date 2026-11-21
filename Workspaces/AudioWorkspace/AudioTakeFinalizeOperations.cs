using Godot;
using System;
using System.Linq;
using GArray=Godot.Collections.Array;
using Settings=Godot.Collections.Dictionary;
public partial class AudioTakeFinalizeOperations:RefCounted
{
    private const string Root="user://audio_workspace/takes";
    private const long MaxBytes=2L*1024*1024*1024-44;
    private static Variant Get(Settings d,string key,Variant fallback=default)=>d.TryGetValue(key,out var v)?v:fallback;
    private static string S(Settings d,string key,string fallback="")=>Get(d,key,fallback).AsString();
    private static string Canonical(string value)=>value.Replace('\\','/').SimplifyPath();
    public Settings finalize(Settings capture,RefCounted? job)
    {
        string directory=Canonical(S(capture,"directory")),root=Canonical(ProjectSettings.GlobalizePath(Root));if(directory.GetBaseDir()!=root)return new Settings{["error"]="Invalid take folder.",["path"]=""};var paths=new Godot.Collections.Array<string>();var warnings=new System.Collections.Generic.List<string>();if(S(capture,"error").Length>0)warnings.Add(S(capture,"error"));double seconds=0;using var pcm=new AudioPcmFileOperations();foreach(var source in Get(capture,"paths",new GArray()).AsGodotArray()){string path=Canonical(source.AsString());if(path.GetBaseDir()!=directory){warnings.Add("A take source was outside its owned folder.");continue;}var info=pcm.inspect(path);if(S(info,"error","invalid").Length>0){warnings.Add(path.GetFile()+": "+S(info,"error","Unreadable take"));continue;}if(info["file_bytes"].AsInt64()>MaxBytes+44){warnings.Add("Take input exceeded 2 GiB. Original retained: "+path);continue;}paths.Add(path);seconds=Math.Max(seconds,info["duration"].AsDouble());}string output=paths.Count==1?paths[0]:"";bool mono=Get(capture,"mono",false).AsBool();
        if(paths.Count>0&&(paths.Count>1||mono&&Get(pcm.inspect(paths[0]),"channels",1).AsInt32()==2))
        {
            string encoder=GD.Load<CSharpScript>("res://scripts/actors/core/ActorVideo.cs").Call("executable","ffmpeg").AsString();if(encoder.Length==0)warnings.Add("FFmpeg is required to combine recording sources. Import the retained source WAVs separately.");else if(seconds*48000*(mono?2:4)>MaxBytes)warnings.Add("Combined take would exceed the 2 GiB output limit; all separate source files were retained.");else
            {
                output=directory.PathJoin("mix.wav");if(Godot.FileAccess.FileExists(output)){warnings.Add("A finalized mix already exists; it was not overwritten.");output="";}else{var args=new System.Collections.Generic.List<string>{"-nostdin","-hide_banner","-v","error","-n","-threads","1","-filter_complex_threads","1"};string inputs="",graph="";for(int i=0;i<paths.Count;i++){args.AddRange(new[]{"-i",paths[i]});string map=Get(pcm.inspect(paths[i]),"channels",2).AsInt32()==1?"pan=stereo|c0=c0|c1=c0,":"";graph+="["+i+":a]"+map+"aresample=48000,aformat=sample_fmts=flt:channel_layouts=stereo[s"+i+"];";inputs+="[s"+i+"]";}graph+=inputs+"amix=inputs="+paths.Count+":normalize=0:dropout_transition=0:duration=longest[out]";args.AddRange(new[]{"-filter_complex",graph,"-map","[out]","-ar","48000","-ac",mono?"1":"2","-c:a","pcm_s16le",output});using var renderer=new AudioRendererOperations();var result=renderer.execute(encoder,args.ToArray(),seconds,job);if(!Get(result,"success",false).AsBool()){warnings.Add(S(result,"error","Take mixing failed."));output="";}}
            }
        }
        if(job!=null&&job.Call("is_cancelled").AsBool()){warnings.Add("Take finalization was cancelled. Separate captures remain recoverable.");output="";}if(output.Length>0&&S(pcm.inspect(output),"error","invalid").Length>0){warnings.Add("The finalized take could not be read.");output="";}var completed=new Settings{["error"]=output.Length>0?"":"No combined take is available. Inputs were preserved in "+directory,["path"]=output,["directory"]=directory,["sources"]=paths,["warning"]=string.Join("; ",warnings)};using var journal=new ConfigFile();journal.Load(directory.PathJoin("take.cfg"));journal.SetValue("take","state",output.Length>0?"ready":"needs_review");journal.SetValue("take","result",completed);var saved=journal.Save(directory.PathJoin("take.cfg"));if(saved!=Error.Ok)completed["warning"]=S(completed,"warning")+" Recovery journal could not be updated: "+saved;return completed;
    }
    public Godot.Collections.Array<Settings> recoverable(Settings activeDirectories)
    {
        var result=new Godot.Collections.Array<Settings>();string root=ProjectSettings.GlobalizePath(Root);using var folder=DirAccess.Open(root);if(folder==null)return result;folder.ListDirBegin();string name=folder.GetNext();int visited=0;using var pcm=new AudioPcmFileOperations();while(name.Length>0&&visited<512){visited++;if(folder.CurrentIsDir()&&name.Length==32&&name.All(Uri.IsHexDigit)){string directory=root.PathJoin(name);if(activeDirectories.ContainsKey(Canonical(directory))){name=folder.GetNext();continue;}using var journal=new ConfigFile();if(journal.Load(directory.PathJoin("take.cfg"))==Error.Ok){var entry=journal.GetValue("take","result",new Settings()).AsGodotDictionary().Duplicate(true);entry["directory"]=directory;entry["state"]=journal.GetValue("take","state","unknown");var paths=new GArray();entry["paths"]=paths;foreach(string file in new[]{"mix.wav","microphone.wav","system.wav","timeline.wav"}){string path=directory.PathJoin(file);if(S(pcm.inspect(path),"error","invalid").Length==0)paths.Add(path);}if(paths.Count>0)result.Add(entry);}}name=folder.GetNext();}folder.ListDirEnd();return result;
    }
}
