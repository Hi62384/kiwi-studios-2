using Godot;
using System;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

public partial class AudioRecoveryOperations : RefCounted
{
    public Variant fail(RefCounted o,string message){if(o.Get("_error").AsString().Length==0)o.Set("_error",message);return default;}
    public void reset(RefCounted o,RefCounted? work){o.Set("_error","");o.Set("_visits",0L);o.Set("_estimated",0L);o.Set("_pending_bytes",0L);o.Set("_nodes",new GArray());foreach(string key in new[]{"_seen","_active","_blobs","_assets","_streams"})o.Set(key,new Settings());o.Set("_work",work==null?default(Variant):Variant.From(work));}
    public bool cancelled(RefCounted o){var work=o.Get("_work").AsGodotObject();return work!=null&&work.HasMethod("is_cancelled")&&work.Call("is_cancelled").AsBool();}
    public string root(RefCounted o)=>ProjectSettings.GlobalizePath(o.Get("directory").AsString()).SimplifyPath();
    public bool hex(string value,int length){if(value.Length!=length)return false;foreach(char c in value)if(c is not (>= '0' and <= '9') and not (>= 'a' and <= 'f'))return false;return true;}
    public Godot.Collections.Array<string> properties(Resource value){var output=new Godot.Collections.Array<string>();foreach(var property in value.GetPropertyList()){string field=property["name"].AsString();if((property["usage"].AsInt64()&(long)PropertyUsageFlags.Storage)!=0&&field is not "script" and not "resource_path")output.Add(field);}return output;}
    public Settings freeze(Resource? document)
    {
        var codec=new KiwiAudioRecovery();reset(codec,null);var result=freeze_value(codec,document==null?default(Variant):Variant.From(document),0);if(result.VariantType==Variant.Type.Object&&result.AsGodotObject()!=null&&document!=null)result.AsGodotObject().Set("_portable_root",document.Get("_portable_root"));return new Settings{["error"]=codec.Get("_error"),["document"]=result};
    }
    public Variant freeze_value(RefCounted o,Variant value,int depth)
    {
        long visits=o.Get("_visits").AsInt64()+1,estimated=o.Get("_estimated").AsInt64();o.Set("_visits",visits);if(depth>32||visits>100000||estimated>o.Get("metadata_limit").AsInt64())return fail(o,"Recovery metadata exceeds its bounded size/depth limit.");if(o.Get("_error").AsString().Length>0)return default;o.Set("_estimated",estimated+16);
        if(value.VariantType==Variant.Type.Object&&value.AsGodotObject() is AudioStream audio){if(audio is not AudioStreamWav and not AudioStreamMP3||audio.GetScript().AsGodotObject()!=null)return fail(o,"Recovery supports unscripted embedded WAV/MP3 audio only. Save this composition manually.");return value;}
        if(value.VariantType==Variant.Type.Object&&value.AsGodotObject() is Resource resource)
        {
            ulong id=resource.GetInstanceId();var active=o.Get("_active").AsGodotDictionary();var seen=o.Get("_seen").AsGodotDictionary();if(active.ContainsKey(id))return fail(o,"Recovery does not support cyclic resource metadata.");if(seen.TryGetValue(id,out var prior))return prior;
            var copy=KiwiAudioRecovery._new_resource(KiwiAudioRecovery._kind(resource));if(copy==null||resource.GetScript().AsGodotObject()!=copy.GetScript().AsGodotObject())return fail(o,"Recovery encountered unsupported embedded resource metadata; save manually.");seen[id]=copy;active[id]=true;
            foreach(string field in properties(resource)){var item=freeze_value(o,resource.Get(field),depth+1);if(o.Get("_error").AsString().Length>0)return default;copy.Set(field,item);}active.Remove(id);return copy;
        }
        if(value.VariantType is Variant.Type.Object or Variant.Type.Callable or Variant.Type.Signal or Variant.Type.Rid)return fail(o,"Recovery encountered unsupported live object metadata; save manually.");
        if(value.VariantType==Variant.Type.Array){var source=value.AsGodotArray();var copy=source.Duplicate();for(int i=0;i<source.Count;++i){var item=freeze_value(o,source[i],depth+1);if(o.Get("_error").AsString().Length>0)return default;copy[i]=item;}return copy;}
        if(value.VariantType==Variant.Type.Dictionary){var source=value.AsGodotDictionary();var copy=source.Duplicate();foreach(var key in source.Keys){if(key.VariantType is Variant.Type.Object or Variant.Type.Array or Variant.Type.Dictionary)return fail(o,"Recovery encountered an unsupported metadata key.");var item=freeze_value(o,source[key],depth+1);if(o.Get("_error").AsString().Length>0)return default;copy[key]=item;}return copy;}
        if(value.VariantType is Variant.Type.String or Variant.Type.StringName)o.Set("_estimated",o.Get("_estimated").AsInt64()+value.AsString().Length*4L);else if((int)value.VariantType>=(int)Variant.Type.PackedByteArray)o.Set("_estimated",o.Get("_estimated").AsInt64()+o.Call("_packed_size",value).AsInt64()*32);return value;
    }
    public Settings checkpoint(RefCounted o,Godot.Mutex mutex,Resource? document,string sessionId,long revision,string sourcePath,RefCounted? work)
    {
        mutex.Lock();try{return checkpoint_data(o,document,sessionId,revision,sourcePath,work);}finally{reset(o,null);mutex.Unlock();}
    }
    public Godot.Collections.Array<Settings> discover(RefCounted o,Godot.Mutex mutex)
    {
        mutex.Lock();try{return discover_data(o);}finally{mutex.Unlock();}
    }
    public Settings restore(RefCounted o,Godot.Mutex mutex,string id)
    {
        mutex.Lock();try{return restore_data(o,id);}finally{reset(o,null);mutex.Unlock();}
    }
}
