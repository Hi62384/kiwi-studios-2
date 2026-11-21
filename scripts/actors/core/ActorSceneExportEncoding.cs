using Godot;
using System;
using System.Linq;
using System.Text;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
public partial class ActorSceneExportOperations
{
    public string[] encoding_arguments(Control editor,Settings job)
    {
        int fps=job["fps"].AsInt32(),samples=job["samples"].AsInt32(),frameCount=job["frame_count"].AsInt32();string directory=job["frame_directory"].AsString();var args=new List<string>{"-hide_banner","-loglevel","error","-nostdin","-y","-framerate",Number(fps*samples),"-i",directory.PathJoin("frame_%06d.png")};var filters=new List<string>();int audioCount=0;var actors=Actors(editor);var clips=Clips(editor);double duration=editor.Get("video_duration").AsDouble();for(int i=0;i<actors.Count;i++){var actor=actors[i].As<Resource>();if(actor.Get("type_id").AsString()!="audio"||_data.get_value(actor,new StringName("muted"),false).AsBool())continue;var clip=clips[i].As<Resource>();double start=clip.Get("start_time").AsDouble(),length=clip.Get("duration").AsDouble();if(start>=duration||start+length<=0)continue;string source=audio_source(actor.Get("values").AsGodotDictionary().GetValueOrDefault("audio",""),directory,audioCount);if(source.Length==0)continue;double active=Math.Min(length,duration-start);if(active<=0)continue;args.AddRange(new[]{"-i",source});filters.Add(audio_filter(actor,clip,audioCount,active));audioCount++;}if(audioCount>0){string labels=string.Concat(Enumerable.Range(0,audioCount).Select(i=>"[a"+i+"]"));filters.Add(audioCount==1?"[a0]atrim=duration="+Number(duration)+",asetpts=PTS-STARTPTS[aout]":labels+"amix=inputs="+audioCount+":duration=longest:dropout_transition=0,atrim=duration="+Number(duration)+",asetpts=PTS-STARTPTS[aout]");args.AddRange(new[]{"-filter_complex",string.Join(';',filters),"-map","0:v:0","-map","[aout]"});}else args.AddRange(new[]{"-map","0:v:0"});if(samples>1)args.AddRange(new[]{"-vf","tmix=frames="+samples+":weights='"+string.Join(' ',Enumerable.Repeat("1",samples))+"',select='not(mod(n+1,"+samples+"))',setpts=N/("+fps+"*TB)"});args.AddRange(new[]{"-frames:v",Number(frameCount),"-r",Number(fps),"-c:v","libx264","-preset","medium","-crf","18","-pix_fmt","yuv420p","-movflags","+faststart"});if(audioCount>0)args.AddRange(new[]{"-c:a","aac","-b:a","192k"});args.Add(job["output"].AsString());return args.ToArray();
    }
    public string start_encoding(Control editor,Settings job){var process=OS.ExecuteWithPipe(job["encoder"].AsString(),encoding_arguments(editor,job),false);if(process.Count==0){cleanup_frames(job["frame_directory"].AsString(),job["input_count"].AsInt32());return "FFmpeg could not start.";}job["process"]=process;job["stderr"]="";return "";}
    private static int ReadError(Settings job){var process=job["process"].AsGodotDictionary();var bytes=process["stderr"].As<Godot.FileAccess>().GetBuffer(4096);if(bytes.Length==0)return 0;string value=job["stderr"].AsString()+Encoding.UTF8.GetString(bytes);job["stderr"]=value.Length>16384?value[^16384..]:value;return bytes.Length;}
    public bool encoding_running(Settings job){bool running=OS.IsProcessRunning(job["process"].AsGodotDictionary()["pid"].AsInt32());if(running)ReadError(job);return running;}
    public string finish_encoding(Settings job)
    {
        var process=job["process"].AsGodotDictionary();for(int i=0;i<32;i++)if(ReadError(job)==0)break;int code=OS.GetProcessExitCode(process["pid"].AsInt32());foreach(string key in new[]{"stderr","stdio"})if(process.TryGetValue(key,out var value)&&value.VariantType==Variant.Type.Object&&value.AsGodotObject() is Godot.FileAccess file)file.Close();cleanup_frames(job["frame_directory"].AsString(),job["input_count"].AsInt32());if(code==0&&Godot.FileAccess.FileExists(job["output"].AsString()))return "";string error=job["stderr"].AsString();return "Video encoding failed. "+(error.Length>500?error[^500..]:error);
    }
}
