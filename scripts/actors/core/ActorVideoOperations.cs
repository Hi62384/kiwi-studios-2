using Godot;
using System;
using System.Globalization;
using System.Linq;
using GArray=Godot.Collections.Array;
using Settings=Godot.Collections.Dictionary;
public partial class ActorVideoOperations:RefCounted
{
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private static string Number(double value)=>value.ToString("R",CultureInfo.InvariantCulture);
    public string executable(string tool)
    {
        string configured=ProjectSettings.GetSetting("kiwi/media/"+tool+"_path","").AsString();if(configured.Length>0)return configured;foreach(string directory in OS.GetEnvironment("PATH").Split(OS.GetName()=="Windows"?';':':')){string path=directory.PathJoin(tool+(OS.GetName()=="Windows"?".exe":""));if(Godot.FileAccess.FileExists(path))return path;}return "";
    }
    public Settings info(Settings metadata,string path)
    {
        if(path.Length==0||!Godot.FileAccess.FileExists(path))return new Settings();string key=path+":"+Godot.FileAccess.GetModifiedTime(path).ToString(CultureInfo.InvariantCulture);if(metadata.TryGetValue(key,out var cached))return cached.AsGodotDictionary();string probe=executable("ffprobe");if(probe.Length==0)return new Settings();var output=new GArray();string absolute=ProjectSettings.GlobalizePath(path);if(OS.Execute(probe,new[]{"-v","error","-show_format","-show_streams","-of","json",absolute},output)!=0)return new Settings();string text="";foreach(var value in output)text+=value.AsString();var json=Json.ParseString(text);if(json.VariantType!=Variant.Type.Dictionary)return new Settings();var parsed=json.AsGodotDictionary();var video=new Settings();bool audio=false;foreach(var value in Get(parsed,"streams",new GArray()).AsGodotArray()){var stream=value.AsGodotDictionary();string type=Get(stream,"codec_type","").AsString();if(type=="video"&&video.Count==0)video=stream;if(type=="audio")audio=true;}if(video.Count==0)return new Settings();var format=Get(parsed,"format",new Settings()).AsGodotDictionary();double duration=ParseNumber(Get(video,"duration",Get(format,"duration",0.0)));if(duration<=0)duration=ParseNumber(Get(format,"duration",0.0));if(!double.IsFinite(duration)||duration<=0)return new Settings();string directory=ProjectSettings.GlobalizePath("user://video_cache/"+key.Sha256Text());DirAccess.MakeDirRecursiveAbsolute(directory);var result=new Settings{["path"]=absolute,["duration"]=duration,["width"]=Get(video,"width",1).AsInt32(),["height"]=Get(video,"height",1).AsInt32(),["audio"]=audio,["directory"]=directory};metadata[key]=result;return result;
    }
    private static double ParseNumber(Variant value)=>value.VariantType==Variant.Type.String?double.TryParse(value.AsString(),NumberStyles.Float,CultureInfo.InvariantCulture,out double number)?number:0:value.AsDouble();
    public double length(Settings metadata,Resource actor)=>Get(info(metadata,Get(actor.Get("values").AsGodotDictionary(),"video","").AsString()),"duration",0.0).AsDouble();
    public AudioStreamWav? audio(Settings metadata,string path)
    {
        var source=info(metadata,path);if(source.Count==0||!source["audio"].AsBool())return null;string encoder=executable("ffmpeg");if(encoder.Length==0)return null;string target=source["directory"].AsString().PathJoin("audio.wav");if(!Godot.FileAccess.FileExists(target)){var output=new GArray();if(OS.Execute(encoder,new[]{"-nostdin","-v","error","-y","-i",source["path"].AsString(),"-map","0:a:0","-vn","-af","apad,atrim=duration="+Number(source["duration"].AsDouble()),"-ar","48000","-ac","2","-c:a","pcm_s16le",target},output)!=0)return null;}var stream=AudioStreamWav.LoadFromFile(target);if(stream!=null)stream.ResourcePath="";return stream;
    }
    public Texture2D? frame(Settings source,Settings textures,Node worker,double time,bool priority)
    {
        if(source.Count==0)return null;time=Math.Clamp(time,0,Math.Max(0,source["duration"].AsDouble()-1.0/24));int window=(int)(time/10);int number=(int)((time-window*10)*24)+1;string directory=source["directory"].AsString().PathJoin("window_"+window),filename=directory.PathJoin(number.ToString("D6",CultureInfo.InvariantCulture)+".jpg");if(textures.TryGetValue(filename,out var cached))return cached.As<Texture2D>();if(Godot.FileAccess.FileExists(filename)){using var image=Image.LoadFromFile(filename);if(image!=null&&!image.IsEmpty()){if(textures.Count>=192)textures.Remove(textures.Keys.First());var texture=ImageTexture.CreateFromImage(image);textures[filename]=texture;return texture;}}
        var completed=worker.Get("_completed").AsGodotDictionary();var running=worker.Get("_running").AsGodotDictionary();var pending=worker.Get("_pending").AsGodotDictionary();if(!completed.ContainsKey(directory)&&!running.ContainsKey(directory)){priority|=Get(Get(pending,directory,new Settings()).AsGodotDictionary(),"priority",false).AsBool();if(pending.Count>=32&&!pending.ContainsKey(directory))pending.Remove(pending.Keys.First());pending[directory]=new Settings{["source"]=source,["window"]=window,["priority"]=priority};}return null;
    }
    public void process(Node worker)
    {
        var running=worker.Get("_running").AsGodotDictionary();var completed=worker.Get("_completed").AsGodotDictionary();var pending=worker.Get("_pending").AsGodotDictionary();foreach(var directory in running.Keys.ToArray()){if(OS.IsProcessRunning(running[directory].AsInt32()))continue;running.Remove(directory);completed[directory]=true;}if(running.Count>=2||pending.Count==0)return;string encoder=executable("ffmpeg");if(encoder.Length==0){pending.Clear();return;}var selected=pending.Keys.First();foreach(var key in pending.Keys)if(pending[key].AsGodotDictionary()["priority"].AsBool()){selected=key;break;}string target=selected.AsString();var request=pending[selected].AsGodotDictionary();pending.Remove(selected);DirAccess.MakeDirRecursiveAbsolute(target);var source=request["source"].AsGodotDictionary();int pid=OS.CreateProcess(encoder,new[]{"-nostdin","-v","error","-y","-ss",Number(request["window"].AsDouble()*10),"-i",source["path"].AsString(),"-t","10","-an","-vf","fps=24,scale=720:-2","-q:v","4","-atomic_writing","1",target.PathJoin("%06d.jpg")},false);if(pid>0)running[target]=pid;
    }
    public void exit_tree(Node worker,Settings textures){var running=worker.Get("_running").AsGodotDictionary();foreach(var value in running.Values){int pid=value.AsInt32();if(OS.IsProcessRunning(pid))OS.Kill(pid);}running.Clear();worker.Get("_pending").AsGodotDictionary().Clear();textures.Clear();}
}
