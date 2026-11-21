using Godot;
using Settings=Godot.Collections.Dictionary;
[GlobalClass]
public partial class KiwiAudioPortableStage : RefCounted
{
    public string final_folder {get;set;}="";
    public string path {get;set;}="";
    public int asset_count {get;set;}
    public long total_bytes {get;set;}
    public string _directory {get;set;}="";
    public string _id {get;set;}="";
    public Godot.Collections.Array<string> _files {get;set;}=new();
    public Godot.Collections.Array<Settings> _sources {get;set;}=new();
    public Settings _staged_signatures {get;set;}=new();
    public bool _ready {get;set;}
    public bool _owned {get;set;}
    public void release()
    {using var operations=new AudioPortableOperations();operations.release_stage(this);}
    public override void _Notification(int what)
    {
        if (what!=NotificationPredelete || !_owned) return;
        _owned=false;_ready=false;
        using var operations=new AudioPortableOperations();
        using var files=Variant.From(_files);
        operations.cleanup_stage(_directory,_id,final_folder,files.AsGodotArray());
    }
}
