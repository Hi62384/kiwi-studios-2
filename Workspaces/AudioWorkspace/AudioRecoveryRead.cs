using Godot;
using System;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

public partial class AudioRecoveryOperations
{
    private static Settings ReadError(string message)=>new Settings{["error"]=message};
    public Settings read(RefCounted o,string id)
    {
        if(id.GetFile()!=id||id.Length!=70||id[32]!='-'||!hex(id[..32],32)||!hex(id.Substring(33,32),32)||!id.EndsWith(".krec",StringComparison.Ordinal))return ReadError("Invalid recovery filename.");using var file=Godot.FileAccess.Open(root(o).PathJoin(id),Godot.FileAccess.ModeFlags.Read);if(file==null)return ReadError("Recovery checkpoint is missing or unreadable.");long length=(long)file.GetLength();if(length<72||length>o.Get("metadata_limit").AsInt64()+72)return ReadError("Recovery checkpoint size is invalid.");if(System.Text.Encoding.ASCII.GetString(file.GetBuffer(8))!="KIWIREC1")return ReadError("Unsupported recovery file format.");string expected=System.Text.Encoding.ASCII.GetString(file.GetBuffer(64));var payload=file.GetBuffer(length-72);if(Digest(payload)!=expected)return ReadError("Recovery checksum failed; this checkpoint will not be restored.");
        var raw=GD.BytesToVar(payload);if(raw.VariantType!=Variant.Type.Dictionary)return ReadError("Recovery metadata is invalid or from an unsupported version.");var data=raw.AsGodotDictionary();var format=Get(data,"format");var time=Get(data,"time");if(format.VariantType is not Variant.Type.Int and not Variant.Type.Float||format.AsDouble()!=1||Get(data,"session","").AsString()!=id[..32]||Get(data,"nodes").VariantType!=Variant.Type.Array||Get(data,"blobs").VariantType!=Variant.Type.Dictionary||Get(data,"assets").VariantType!=Variant.Type.Array||Get(data,"title").VariantType!=Variant.Type.String||Get(data,"source_path").VariantType!=Variant.Type.String||time.VariantType is not Variant.Type.Int and not Variant.Type.Float||!double.IsFinite(time.AsDouble())||Get(data,"revision").VariantType!=Variant.Type.Int)return ReadError("Recovery metadata is invalid or from an unsupported version.");
        var blobs=data["blobs"].AsGodotDictionary();foreach(var digest in blobs.Keys)if(digest.VariantType!=Variant.Type.String||!hex(digest.AsString(),64)||blobs[digest].VariantType!=Variant.Type.Int||blobs[digest].AsInt64()<0||blobs[digest].AsInt64()>o.Get("blob_limit").AsInt64())return ReadError("Recovery audio manifest is invalid.");return new Settings{["error"]="",["envelope"]=data,["id"]=id};
    }
    public Godot.Collections.Array<Settings> discover_data(RefCounted o)
    {
        var ordered=new System.Collections.Generic.List<Settings>();using var directory=DirAccess.Open(root(o));if(directory==null)return new Godot.Collections.Array<Settings>();foreach(string id in directory.GetFiles())
        {
            if(!id.EndsWith(".krec",StringComparison.Ordinal))continue;var entry=read(o,id);entry["id"]=id;if(entry["error"].AsString().Length==0){var data=entry["envelope"].AsGodotDictionary();foreach(string key in new[]{"title","time","source_path","revision","session"})entry[key]=data[key];var missing=new System.Collections.Generic.List<string>();foreach(var asset in data["assets"].AsGodotArray())if(asset.VariantType==Variant.Type.String&&!Godot.FileAccess.FileExists(asset.AsString()))missing.Add(asset.AsString());entry["missing_assets"]=missing.ToArray();foreach(var pair in data["blobs"].AsGodotDictionary())if(file_size(root(o).PathJoin("blobs").PathJoin(pair.Key.AsString()+".blob"))!=pair.Value.AsInt64()){entry["error"]="Recovery embedded audio is missing or has the wrong size.";break;}}entry.Remove("envelope");ordered.Add(entry);
        }
        ordered.Sort((a,b)=>Get(b,"time",0).AsDouble().CompareTo(Get(a,"time",0).AsDouble()));var output=new Godot.Collections.Array<Settings>();foreach(var entry in ordered)output.Add(entry);return output;
    }
    public void prune(RefCounted o,string newest)
    {
        var entries=new System.Collections.Generic.List<Settings>();foreach(var entry in discover_data(o))entries.Add(entry);entries.Sort((a,b)=>a["id"].AsString()==newest?(b["id"].AsString()==newest?0:-1):b["id"].AsString()==newest?1:Get(b,"time",0).AsDouble().CompareTo(Get(a,"time",0).AsDouble()));var counts=new System.Collections.Generic.Dictionary<string,int>();int kept=0;
        foreach(var entry in entries){if(entry["error"].AsString().Length>0)continue;string session=entry["session"].AsString();counts[session]=counts.TryGetValue(session,out int count)?count+1:1;++kept;if(counts[session]>Math.Max(1,o.Get("keep_per_session").AsInt32())||kept>Math.Max(1,o.Get("keep_total").AsInt32()))DirAccess.RemoveAbsolute(root(o).PathJoin(entry["id"].AsString()));}
        var referenced=new Settings();foreach(var entry in discover_data(o)){var result=read(o,entry["id"].AsString());if(result["error"].AsString().Length>0)return;referenced.Merge(result["envelope"].AsGodotDictionary()["blobs"].AsGodotDictionary());}using var directory=DirAccess.Open(root(o).PathJoin("blobs"));if(directory==null)return;foreach(string file in directory.GetFiles())if(file.EndsWith(".blob",StringComparison.Ordinal)&&hex(file.GetBaseName(),64)&&!referenced.ContainsKey(file.GetBaseName()))DirAccess.RemoveAbsolute(root(o).PathJoin("blobs").PathJoin(file));
    }
    private bool GraphFailure(RefCounted o,string message){fail(o,message);return false;}
    public bool graph_value(RefCounted o,Variant encoded,GArray nodes,Settings states,int depth)
    {
        long visits=o.Get("_visits").AsInt64()+1;o.Set("_visits",visits);if(depth>32||visits>100000||encoded.VariantType!=Variant.Type.Array||encoded.AsGodotArray().Count!=2)return GraphFailure(o,"Invalid or excessive recovery graph.");var pair=encoded.AsGodotArray();var kind=pair[0];var value=pair[1];string tag=kind.VariantType is Variant.Type.String or Variant.Type.StringName?kind.AsString():"";
        switch(tag)
        {
            case "resource":
                if(value.VariantType!=Variant.Type.Int||value.AsInt64()<0||value.AsInt64()>=nodes.Count)return GraphFailure(o,"Invalid recovery object reference.");int state=states.TryGetValue(value,out var rawState)?rawState.AsInt32():0;if(state==1)return GraphFailure(o,"Cyclic recovery resource metadata is unsupported.");if(state==2)return true;var raw=nodes[value.AsInt32()];if(raw.VariantType!=Variant.Type.Dictionary||Get(raw.AsGodotDictionary(),"fields").VariantType!=Variant.Type.Dictionary)return GraphFailure(o,"Invalid recovery object fields.");states[value]=1;foreach(var field in raw.AsGodotDictionary()["fields"].AsGodotDictionary().Values)if(!graph_value(o,field,nodes,states,depth+1))return false;states[value]=2;break;
            case "array":if(value.VariantType!=Variant.Type.Array)return GraphFailure(o,"Invalid recovery array.");foreach(var item in value.AsGodotArray())if(!graph_value(o,item,nodes,states,depth+1))return false;break;
            case "dictionary":if(value.VariantType!=Variant.Type.Array)return GraphFailure(o,"Invalid recovery dictionary.");foreach(var rawPair in value.AsGodotArray()){if(rawPair.VariantType!=Variant.Type.Array||rawPair.AsGodotArray().Count!=2)return GraphFailure(o,"Invalid recovery dictionary entry.");var entry=rawPair.AsGodotArray();if(!graph_value(o,entry[0],nodes,states,depth+1)||!graph_value(o,entry[1],nodes,states,depth+1))return false;}break;
            case "blob":case "wav_file":if(value.VariantType!=Variant.Type.String||!o.Get("_blobs").AsGodotDictionary().ContainsKey(value))return GraphFailure(o,"Invalid recovery audio reference.");break;
            case "value":if(value.VariantType is Variant.Type.Object or Variant.Type.Array or Variant.Type.Dictionary or Variant.Type.Callable or Variant.Type.Signal or Variant.Type.Rid)return GraphFailure(o,"Unsafe recovery scalar.");break;
            default:return GraphFailure(o,"Unsupported recovery value type.");
        }
        return true;
    }
    public Variant decode(RefCounted o,Variant encoded,GArray resources,int depth)
    {
        long visits=o.Get("_visits").AsInt64()+1;o.Set("_visits",visits);if(depth>32||visits>100000||encoded.VariantType!=Variant.Type.Array||encoded.AsGodotArray().Count!=2)return fail(o,"Invalid or excessive recovery metadata.");var pair=encoded.AsGodotArray();var kind=pair[0];var value=pair[1];string tag=kind.VariantType is Variant.Type.String or Variant.Type.StringName?kind.AsString():"";
        switch(tag)
        {
            case "value":if(value.VariantType is Variant.Type.Object or Variant.Type.Array or Variant.Type.Dictionary or Variant.Type.Callable or Variant.Type.Signal or Variant.Type.Rid)return fail(o,"Unsafe recovery scalar.");return value;
            case "resource":if(value.VariantType!=Variant.Type.Int||value.AsInt64()<0||value.AsInt64()>=resources.Count)return fail(o,"Invalid recovery resource reference.");return resources[value.AsInt32()];
            case "array":if(value.VariantType!=Variant.Type.Array)return fail(o,"Invalid recovery array.");var items=new GArray();foreach(var item in value.AsGodotArray())items.Add(decode(o,item,resources,depth+1));return items;
            case "dictionary":if(value.VariantType!=Variant.Type.Array)return fail(o,"Invalid recovery dictionary.");var output=new Settings();foreach(var rawPair in value.AsGodotArray()){if(rawPair.VariantType!=Variant.Type.Array||rawPair.AsGodotArray().Count!=2)return fail(o,"Invalid recovery dictionary entry.");var entry=rawPair.AsGodotArray();var key=decode(o,entry[0],resources,depth+1);if(key.VariantType is Variant.Type.Object or Variant.Type.Array or Variant.Type.Dictionary)return fail(o,"Unsupported recovery dictionary key.");if(output.ContainsKey(key))return fail(o,"Duplicate recovery dictionary key.");output[key]=decode(o,entry[1],resources,depth+1);}return output;
            case "blob":
                var blobs=o.Get("_blobs").AsGodotDictionary();if(value.VariantType!=Variant.Type.String||!blobs.ContainsKey(value))return fail(o,"Recovery audio reference is missing.");var streams=o.Get("_streams").AsGodotDictionary();if(streams.TryGetValue(value,out var existing))return existing;string path=root(o).PathJoin("blobs").PathJoin(value.AsString()+".blob");if(file_size(path)!=blobs[value].AsInt64()||Godot.FileAccess.GetSha256(path)!=value.AsString())return fail(o,"Recovery audio checksum failed or the source is missing.");using(var file=Godot.FileAccess.Open(path,Godot.FileAccess.ModeFlags.Read)){if(file==null)return fail(o,"Recovery audio could not be read.");var bytes=file.GetBuffer((long)file.GetLength());streams[value]=bytes;return streams[value];}
            default:return fail(o,"Unsupported recovery value type.");
        }
    }
    public Settings restore_data(RefCounted o,string id)
    {
        reset(o,null);var loaded=read(o,id);if(loaded["error"].AsString().Length>0)return loaded;var envelope=loaded["envelope"].AsGodotDictionary();var blobs=envelope["blobs"].AsGodotDictionary();o.Set("_blobs",blobs);long total=0;foreach(var size in blobs.Values){if(size.AsInt64()>512L*1024*1024-total)return ReadError("Recovery audio exceeds the total restore limit.");total+=size.AsInt64();}var nodes=envelope["nodes"].AsGodotArray();var states=new Settings();if(!graph_value(o,Get(envelope,"document"),nodes,states,0))return ReadError(o.Get("_error").AsString());if(states.Count!=nodes.Count)return ReadError("Recovery contains unreachable resource metadata.");o.Set("_visits",0L);var resources=new GArray();if(nodes.Count>100000)return ReadError("Recovery object count exceeds its limit.");
        foreach(var raw in nodes)
        {
            if(raw.VariantType!=Variant.Type.Dictionary)return ReadError("Recovery object metadata is invalid.");var node=raw.AsGodotDictionary();if(Get(node,"kind").VariantType!=Variant.Type.String||Get(node,"fields").VariantType!=Variant.Type.Dictionary)return ReadError("Recovery object metadata is invalid.");string kind=node["kind"].AsString();var resource=KiwiAudioRecovery._new_resource(kind);
            if(kind=="wav"){var audio=Get(node["fields"].AsGodotDictionary(),"data");if(audio.VariantType!=Variant.Type.Array||audio.AsGodotArray().Count!=2||audio.AsGodotArray()[0].AsString()!="wav_file"||audio.AsGodotArray()[1].VariantType!=Variant.Type.String||!blobs.ContainsKey(audio.AsGodotArray()[1]))return ReadError("Recovery WAV reference is invalid.");var digest=audio.AsGodotArray()[1];string path=root(o).PathJoin("blobs").PathJoin(digest.AsString()+".blob");if(file_size(path)!=blobs[digest].AsInt64()||Godot.FileAccess.GetSha256(path)!=digest.AsString())return ReadError("Recovery WAV is missing or its checksum failed.");resource=AudioStreamWav.LoadFromFile(path);}if(resource==null)return ReadError("Unsupported recovery object type.");resources.Add(resource);
        }
        for(int i=0;i<resources.Count;++i)
        {
            var resource=resources[i].As<Resource>();var fields=nodes[i].AsGodotDictionary()["fields"].AsGodotDictionary();var allowed=properties(resource);string kind=KiwiAudioRecovery._kind(resource);int expected=allowed.Count-(kind=="document"&&!fields.ContainsKey("portable_media")?1:0);if(fields.Count!=expected)return ReadError("Recovery fields do not match this version.");
            foreach(var field in fields.Keys){string name=field.AsString();if(resource is AudioStreamWav&&name=="data")continue;if(!allowed.Contains(name))return ReadError("Unsupported recovery field.");var value=decode(o,fields[field],resources,0);if(o.Get("_error").AsString().Length>0)return ReadError(o.Get("_error").AsString());string problem=o.Call("_assign_recovery_field",resource,name,value).AsString();if(problem.Length>0)return ReadError(problem);}
        }
        var document=decode(o,Get(envelope,"document"),resources,0);if(o.Get("_error").AsString().Length>0||document.VariantType!=Variant.Type.Object||document.AsGodotObject() is not Resource rootResource||KiwiAudioRecovery._kind(rootResource)!="document")return ReadError("Recovery document is invalid. "+o.Get("_error").AsString());var issues=rootResource.Call("validate").AsStringArray();if(issues.Length>0)return ReadError("Recovery document validation failed: "+string.Join("; ",issues));var missing=new System.Collections.Generic.List<string>();foreach(var asset in envelope["assets"].AsGodotArray())if(asset.VariantType==Variant.Type.String&&!Godot.FileAccess.FileExists(asset.AsString()))missing.Add(asset.AsString());rootResource.Set("title",rootResource.Get("title").AsString()+" (Recovered)");return new Settings{["error"]="",["document"]=rootResource,["missing_assets"]=missing.ToArray(),["source_path"]=envelope["source_path"],["id"]=id};
    }
}
