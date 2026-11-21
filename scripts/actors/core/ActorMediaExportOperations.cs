using Godot;
using System;
using System.Collections.Generic;
using System.Buffers.Binary;
using GArray=Godot.Collections.Array;
using Settings=Godot.Collections.Dictionary;
public partial class ActorMediaExportOperations:RefCounted
{
    private readonly ActorAnimationOperations _animation=new();private readonly ActorImageGeneratorOperations _images=new();private readonly ActorDataOperations _data=new();private readonly ActorVideoOperations _video=new();
    private static string[] Extensions(Resource property){var options=property.Get("options").AsGodotDictionary();if(!options.TryGetValue("extensions",out var value))return Array.Empty<string>();if(value.VariantType==Variant.Type.PackedStringArray)return value.AsStringArray();var items=value.AsGodotArray();var result=new string[items.Count];for(int i=0;i<result.Length;i++)result[i]=items[i].AsString();return result;}
    private static bool Script(Resource? value,string path)=>ActorDataOperations.ScriptIs(value,"res://scripts/actors/core/"+path+".gd");
    public string[] formats(Resource property,Variant value)
    {
        var extensions=Extensions(property);var resource=value.VariantType==Variant.Type.Object?value.AsGodotObject() as Resource:null;if(Array.IndexOf(extensions,"mp4")>=0)return new[]{"mp4","mov","mkv","webm"};if(Array.IndexOf(extensions,"mp3")>=0||resource is AudioStream)return new[]{"wav","mp3","ogg","flac"};if(Script(resource,"actor_object_reference")||Script(resource,"actor_object_data")){string type=resource!.Get(Script(resource,"actor_object_reference")?"object_type":"type_id").AsString();if(type is "image" or "noise_image")return new[]{"tres","png","jpg","webp"};}if(resource is Texture2D or Image||Array.IndexOf(extensions,"png")>=0)return new[]{"png","jpg","webp","tres"};return Array.IndexOf(extensions,"gdshader")>=0?new[]{"gdshader"}:new[]{"tres"};
    }
    public bool write(Variant value,string path,Resource property)
    {
        if(Godot.FileAccess.FileExists(path))return false;string extension=path.GetExtension().ToLowerInvariant();if(value.VariantType==Variant.Type.String&&value.AsString().GetExtension().ToLowerInvariant()==extension)return DirAccess.CopyAbsolute(ProjectSettings.GlobalizePath(value.AsString()),ProjectSettings.GlobalizePath(path))==Error.Ok;Resource? resource=value.VariantType==Variant.Type.Object?value.AsGodotObject() as Resource:null;var originalResource=resource;if(Script(resource,"actor_object_reference"))resource=_animation.resolve_reference(resource!);
        if(Script(resource,"actor_object_data")&&resource!.Get("type_id").AsString()=="image"){var original=resource.Get("values").AsGodotDictionary().TryGetValue(new StringName("source"),out var source)?source:Variant.From("");if(original.VariantType==Variant.Type.String&&original.AsString().GetExtension().ToLowerInvariant()==extension)return DirAccess.CopyAbsolute(ProjectSettings.GlobalizePath(original.AsString()),ProjectSettings.GlobalizePath(path))==Error.Ok;}
        if(originalResource is AudioStreamWav wavSource&&extension=="wav")return wavSource.SaveToWav(ProjectSettings.GlobalizePath(path))==Error.Ok;if((extension is "tres" or "res")&&resource!=null)return ResourceSaver.Save(resource,path)==Error.Ok;
        Image? image=null;bool owned=false;var extensions=Extensions(property);if(Script(resource,"actor_object_data")&&resource!.Get("type_id").AsString() is "image" or "noise_image"){image=_images.image_for_object(resource);}else if(originalResource is Texture2D texture){image=texture.GetImage();owned=true;}else if(originalResource is Image bitmap)image=bitmap;else if(value.VariantType==Variant.Type.String&&Array.IndexOf(extensions,"png")>=0){image=Image.LoadFromFile(value.AsString());owned=true;}
        if(image!=null){try{switch(extension){case "png":return image.SavePng(path)==Error.Ok;case "jpg":case "jpeg":return image.SaveJpg(path,.95f)==Error.Ok;case "webp":return image.SaveWebp(path)==Error.Ok;case "tres":using(var texture=ImageTexture.CreateFromImage(image))return ResourceSaver.Save(texture,path)==Error.Ok;}}finally{if(owned)image.Dispose();}}
        string input=value.VariantType==Variant.Type.String?value.AsString():"",temporary="";try
        {
            if(originalResource is AudioStream audio){temporary=ProjectSettings.GlobalizePath("user://export_"+_data.new_id()+".wav");if(audio is AudioStreamWav wav){if(wav.SaveToWav(temporary)!=Error.Ok)return false;}else{using var converted=Decode(audio);if(converted.SaveToWav(temporary)!=Error.Ok)return false;}input=temporary;}
            if(input.Length==0||!Godot.FileAccess.FileExists(input))return false;string encoder=_video.executable("ffmpeg");if(encoder.Length==0)return false;var arguments=new List<string>{"-nostdin","-v","error","-n","-i",ProjectSettings.GlobalizePath(input)};
            if(Array.IndexOf(extensions,"mp4")>=0){if((input.GetExtension().ToLowerInvariant() is "mp4" or "m4v" or "mov")&&(extension is "mp4" or "mov" or "mkv")){var remux=new List<string>(arguments);remux.AddRange(new[]{"-map","0:v:0","-map","0:a?","-c","copy",ProjectSettings.GlobalizePath(path)});if(OS.Execute(encoder,remux.ToArray(),new GArray(),true)==0)return true;if(Godot.FileAccess.FileExists(path))DirAccess.RemoveAbsolute(ProjectSettings.GlobalizePath(path));}arguments.AddRange(extension=="webm"?new[]{"-c:v","libvpx-vp9","-deadline","realtime","-cpu-used","6","-c:a","libopus"}:new[]{"-c:v","libx264","-preset","veryfast","-crf","18","-pix_fmt","yuv420p","-c:a","aac"});}else arguments.AddRange(new[]{"-vn","-c:a",extension switch{"mp3"=>"libmp3lame","ogg"=>"libvorbis","flac"=>"flac",_=>"pcm_s16le"}});arguments.Add(ProjectSettings.GlobalizePath(path));var output=new GArray();bool success=OS.Execute(encoder,arguments.ToArray(),output,true)==0;if(!success){var log=new System.Text.StringBuilder("Media export failed: ");foreach(var line in output)log.Append(line.AsString());GD.PushWarning(log.ToString());}return success;
        }
        finally{if(temporary.Length>0&&Godot.FileAccess.FileExists(temporary))DirAccess.RemoveAbsolute(temporary);}
    }
    private static AudioStreamWav Decode(AudioStream audio)
    {
        using var playback=audio.InstantiatePlayback();playback.Start();int frames=checked((int)(audio.GetLength()*48000));var bytes=new byte[checked(frames*4)];int cursor=0;try{while(cursor<frames){var samples=playback.MixAudio(AudioServer.GetMixRate()/48000f,Math.Min(4096,frames-cursor));if(samples.Length==0)break;foreach(var sample in samples){BinaryPrimitives.WriteInt16LittleEndian(bytes.AsSpan(cursor*4,2),(short)Math.Clamp((int)(sample.X*32767),-32768,32767));BinaryPrimitives.WriteInt16LittleEndian(bytes.AsSpan(cursor*4+2,2),(short)Math.Clamp((int)(sample.Y*32767),-32768,32767));cursor++;}}}finally{playback.Stop();}return new AudioStreamWav{Format=AudioStreamWav.FormatEnum.Format16Bits,MixRate=48000,Stereo=true,Data=bytes};
    }
}
