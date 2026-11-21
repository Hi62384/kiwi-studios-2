using Godot;
using System;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

public partial class AudioRecoveryOperations
{
    private static Variant Get(Settings d,string key,Variant fallback=default)=>d.TryGetValue(key,out var value)?value:fallback;
    private static string Id(){using var crypto=new Crypto();return Convert.ToHexString(crypto.GenerateRandomBytes(16)).ToLowerInvariant();}
    private static string Digest(byte[] bytes)=>Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(bytes)).ToLowerInvariant();
    public long file_size(string path){using var file=Godot.FileAccess.Open(path,Godot.FileAccess.ModeFlags.Read);return file==null?-1:(long)file.GetLength();}
    public long used_bytes(string root)
    {
        long total=0;foreach(string folder in new[]{root,root.PathJoin("blobs")}){using var directory=DirAccess.Open(folder);if(directory==null)return -1;foreach(string file in directory.GetFiles()){long size=file_size(folder.PathJoin(file));if(size<0||total>long.MaxValue-size)return -1;total+=size;}}return total;
    }
    private static bool Publish(string temporary,string destination)
    {
        try{System.IO.File.Move(ProjectSettings.GlobalizePath(temporary),ProjectSettings.GlobalizePath(destination),false);return true;}catch(System.IO.IOException){return false;}catch(UnauthorizedAccessException){return false;}
    }
    public string wav_blob(RefCounted o,AudioStreamWav stream)
    {
        string Error(string message){fail(o,message);return "";}
        if(stream.Format is not AudioStreamWav.FormatEnum.Format8Bits and not AudioStreamWav.FormatEnum.Format16Bits)return Error("Recovery supports PCM 8/16-bit embedded WAV only; save this source manually.");string rootPath=root(o);ulong id=stream.GetInstanceId();string signature=((int)stream.Format)+":"+stream.MixRate+":"+(stream.Stereo?"true":"false");var cache=o.Get("_audio_cache").AsGodotDictionary();long blobLimit=o.Get("blob_limit").AsInt64();
        if(cache.TryGetValue(id,out var cachedRaw))
        {
            var cached=cachedRaw.AsGodotDictionary();bool same=false;if(cached.Count>0&&cached["owner"].AsGodotObject() is WeakRef weak){using var reference=weak.GetRef();same=reference.AsGodotObject()==stream&&cached["signature"].AsString()==signature;}
            if(same){long bytes=cached["bytes"].AsInt64();if(bytes>blobLimit)return Error("Embedded audio exceeds the recovery per-source limit; save manually.");string digest=cached["digest"].AsString(),location=rootPath.PathJoin("blobs").PathJoin(digest+".blob");if(file_size(location)==bytes&&Godot.FileAccess.GetSha256(location)==digest){o.Get("_blobs").AsGodotDictionary()[digest]=bytes;return digest;}if(Godot.FileAccess.FileExists(location))return Error("Previously preserved recovery audio is corrupt; save manually.");cache.Remove(id);}
        }
        double estimate=Math.Round(stream.GetLength()*stream.MixRate,MidpointRounding.AwayFromZero)*(stream.Stereo?2:1)*(stream.Format==AudioStreamWav.FormatEnum.Format8Bits?1:2)+1024;long used=used_bytes(rootPath);if(!double.IsFinite(estimate)||estimate>blobLimit)return Error("Embedded audio exceeds the recovery per-source limit; save manually.");if(used<0||used+estimate+o.Get("metadata_limit").AsInt64()>o.Get("store_limit").AsInt64())return Error("Recovery storage is full. Prior checkpoints are intact; save manually.");
        string temporary=rootPath.PathJoin("blobs").PathJoin("wav.part-"+Id()+".wav");if(cancelled(o))return Error("Recovery checkpoint was cancelled.");var saved=stream.SaveToWav(temporary);long size=file_size(temporary);if(saved!=Godot.Error.Ok||size<44||size>blobLimit||cancelled(o)){if(Godot.FileAccess.FileExists(temporary))DirAccess.RemoveAbsolute(temporary);return Error("Recovery WAV preservation failed or was cancelled; save manually.");}
        string checksum=Godot.FileAccess.GetSha256(temporary),target=rootPath.PathJoin("blobs").PathJoin(checksum+".blob");if(!hex(checksum,64)||cancelled(o)){DirAccess.RemoveAbsolute(temporary);return Error("Recovery WAV checksum failed or was cancelled.");}
        if(Godot.FileAccess.FileExists(target)){DirAccess.RemoveAbsolute(temporary);if(file_size(target)!=size||Godot.FileAccess.GetSha256(target)!=checksum)return Error("Existing recovery audio is corrupt.");}else if(!Publish(temporary,target)){DirAccess.RemoveAbsolute(temporary);return Error("Recovery WAV could not be published.");}
        cache[id]=new Settings{["owner"]=Variant.From(GodotObject.WeakRef(stream)),["signature"]=signature,["digest"]=checksum,["bytes"]=size};if(cache.Count>1024){foreach(var key in cache.Keys){var weak=cache[key].AsGodotDictionary()["owner"].As<WeakRef>();using var reference=weak.GetRef();if(reference.AsGodotObject()==null)cache.Remove(key);}foreach(var key in cache.Keys){if(cache.Count<=1024)break;if(key.AsUInt64()!=id)cache.Remove(key);}}o.Get("_blobs").AsGodotDictionary()[checksum]=size;return checksum;
    }
    public Variant encode(RefCounted o,Variant value,int depth)
    {
        long visits=o.Get("_visits").AsInt64()+1,estimated=o.Get("_estimated").AsInt64();o.Set("_visits",visits);if(depth>32||visits>100000||estimated>o.Get("metadata_limit").AsInt64())return fail(o,"Recovery metadata exceeds its bounded size/depth limit.");if(o.Get("_error").AsString().Length>0||cancelled(o))return fail(o,"Recovery checkpoint was cancelled.");o.Set("_estimated",estimated+16);
        if(value.VariantType==Variant.Type.Object&&value.AsGodotObject() is Resource resource)
        {
            ulong id=resource.GetInstanceId();var active=o.Get("_active").AsGodotDictionary();var seen=o.Get("_seen").AsGodotDictionary();if(active.ContainsKey(id))return fail(o,"Recovery does not support cyclic resource metadata.");if(seen.TryGetValue(id,out var prior))return new GArray{"resource",prior};string kind=KiwiAudioRecovery._kind(resource);var template=kind.Length>0?KiwiAudioRecovery._new_resource(kind):null;if(template==null||resource.GetScript().AsGodotObject()!=template.GetScript().AsGodotObject())return fail(o,"Recovery cannot safely preserve embedded resource type "+resource.GetClass()+". Save this composition manually.");
            var nodes=o.Get("_nodes").AsGodotArray();int index=nodes.Count;seen[id]=index;active[id]=true;nodes.Add(new Settings());var fields=new Settings();
            foreach(string field in properties(resource))
            {
                if(field=="data"&&kind=="wav"){string digest=wav_blob(o,(AudioStreamWav)resource);if(digest.Length==0)return default;fields[field]=new GArray{"wav_file",digest};}
                else if(field=="data"&&kind=="mp3")
                {
                    var data=resource.Get(field);var bytes=data.AsByteArray();if(bytes.LongLength>o.Get("blob_limit").AsInt64())return fail(o,"Embedded audio exceeds the recovery per-source limit; save manually.");using var hash=System.Security.Cryptography.IncrementalHash.CreateHash(System.Security.Cryptography.HashAlgorithmName.SHA256);for(int offset=0;offset<bytes.Length;offset+=65536){if(cancelled(o))return fail(o,"Recovery checkpoint was cancelled.");hash.AppendData(bytes.AsSpan(offset,Math.Min(65536,bytes.Length-offset)));}string digest=Convert.ToHexString(hash.GetHashAndReset()).ToLowerInvariant();o.Get("_blobs").AsGodotDictionary()[digest]=bytes.LongLength;o.Get("_streams").AsGodotDictionary()[digest]=data;fields[field]=new GArray{"blob",digest};
                }
                else fields[field]=encode(o,resource.Get(field),depth+1);
            }
            nodes[index]=new Settings{["kind"]=kind,["fields"]=fields};active.Remove(id);return new GArray{"resource",index};
        }
        if(value.VariantType is Variant.Type.Object or Variant.Type.Callable or Variant.Type.Signal or Variant.Type.Rid)return fail(o,"Recovery encountered unsupported live object metadata; save manually.");
        if(value.VariantType==Variant.Type.Dictionary)
        {
            var entries=new GArray();var source=value.AsGodotDictionary();foreach(var key in source.Keys){var item=source[key];if(key.AsString() is "audio" or "original_audio" or "sample" or "impulse_path"&&item.VariantType==Variant.Type.String&&item.AsString().GetExtension().ToLowerInvariant() is "wav" or "mp3" or "ogg" or "flac")o.Get("_assets").AsGodotDictionary()[item.AsString()]=true;entries.Add(new GArray{encode(o,key,depth+1),encode(o,item,depth+1)});}return new GArray{"dictionary",entries};
        }
        if(value.VariantType==Variant.Type.Array){var items=new GArray();foreach(var item in value.AsGodotArray())items.Add(encode(o,item,depth+1));return new GArray{"array",items};}
        if(value.VariantType is Variant.Type.String or Variant.Type.StringName){string path=value.AsString();o.Set("_estimated",o.Get("_estimated").AsInt64()+path.Length*4L);if(path.GetExtension().ToLowerInvariant() is "wav" or "mp3" or "ogg" or "flac"&&(path.StartsWith("res://",StringComparison.Ordinal)||path.StartsWith("user://",StringComparison.Ordinal)||path.IsAbsolutePath()))o.Get("_assets").AsGodotDictionary()[path]=true;}
        else if((int)value.VariantType>=(int)Variant.Type.PackedByteArray)o.Set("_estimated",o.Get("_estimated").AsInt64()+o.Call("_packed_size",value).AsInt64()*32);return new GArray{"value",value};
    }
    public string atomic_bytes(RefCounted o,string destination,byte[] bytes)
    {
        string temporary=destination+".part-"+Id();Error error;
        using(var file=Godot.FileAccess.Open(temporary,Godot.FileAccess.ModeFlags.Write)){if(file==null)return "Could not write recovery data; prior checkpoints are intact.";for(int offset=0;offset<bytes.Length;offset+=65536){if(cancelled(o)){file.Close();DirAccess.RemoveAbsolute(temporary);return "Recovery checkpoint was cancelled.";}file.StoreBuffer(bytes.AsSpan(offset,Math.Min(65536,bytes.Length-offset)).ToArray());}file.Flush();error=file.GetError();}
        if(error!=Error.Ok||file_size(temporary)!=bytes.LongLength||cancelled(o)){DirAccess.RemoveAbsolute(temporary);return "Recovery write did not complete; prior checkpoints are intact.";}if(!Publish(temporary,destination)){DirAccess.RemoveAbsolute(temporary);return "Recovery checkpoint could not be published; prior checkpoints are intact.";}return "";
    }
    public Settings checkpoint_data(RefCounted o,Resource? document,string sessionId,long revision,string sourcePath,RefCounted? work)
    {
        Settings Error(string message)=>new Settings{["error"]=message};reset(o,work);if(document==null||!hex(sessionId,32)||revision<0)return Error("Invalid recovery checkpoint identity.");var issues=document.Call("validate").AsStringArray();if(issues.Length>0)return Error("Recovery skipped invalid composition: "+string.Join("; ",issues));string rootPath=root(o);if(DirAccess.MakeDirRecursiveAbsolute(rootPath.PathJoin("blobs"))!=Godot.Error.Ok)return Error("Recovery directory could not be created.");var encoded=encode(o,document,0);if(o.Get("_error").AsString().Length>0)return Error(o.Get("_error").AsString());var nodes=o.Get("_nodes").AsGodotArray();var blobs=o.Get("_blobs").AsGodotDictionary();var assets=o.Get("_assets").AsGodotDictionary();
        var envelope=new Settings{["format"]=1,["session"]=sessionId,["revision"]=revision,["time"]=Time.GetUnixTimeFromSystem(),["title"]=document.Get("title"),["source_path"]=sourcePath,["document"]=encoded,["nodes"]=nodes,["blobs"]=blobs,["assets"]=new GArray(assets.Keys)};var payload=GD.VarToBytes(envelope);if(payload.LongLength>o.Get("metadata_limit").AsInt64())return Error("Recovery metadata exceeds its size limit; save manually.");long used=used_bytes(rootPath),pending=payload.LongLength+72;
        foreach(var digest in blobs.Keys){string path=rootPath.PathJoin("blobs").PathJoin(digest.AsString()+".blob");if(Godot.FileAccess.FileExists(path)){if(file_size(path)!=blobs[digest].AsInt64()||Godot.FileAccess.GetSha256(path)!=digest.AsString())return Error("An existing recovery audio blob is corrupt; prior checkpoints were preserved.");}else pending+=blobs[digest].AsInt64();}o.Set("_pending_bytes",pending);if(used<0||used+pending>o.Get("store_limit").AsInt64())return Error("Recovery storage is full. Prior checkpoints are intact; save manually or review recovery storage.");
        foreach(var digest in blobs.Keys){string path=rootPath.PathJoin("blobs").PathJoin(digest.AsString()+".blob");if(!Godot.FileAccess.FileExists(path)){string error=atomic_bytes(o,path,o.Get("_streams").AsGodotDictionary()[digest].AsByteArray());if(error.Length>0)return Error(error);}}
        if(cancelled(o))return Error("Recovery checkpoint was cancelled.");byte[] header=System.Text.Encoding.ASCII.GetBytes("KIWIREC1"+Digest(payload));var bytes=new byte[checked(header.Length+payload.Length)];header.CopyTo(bytes,0);payload.CopyTo(bytes,header.Length);string id=sessionId+"-"+Id()+".krec",problem=atomic_bytes(o,rootPath.PathJoin(id),bytes);if(problem.Length>0)return Error(problem);o.Call("_prune",id);return new Settings{["error"]="",["id"]=id,["revision"]=revision,["session"]=sessionId,["metadata_bytes"]=bytes.LongLength,["audio_blobs"]=blobs.Count};
    }
}
