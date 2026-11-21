using Godot;
using System;
using System.Threading.Tasks;

/// <summary>Project asset library; shared thumbnail loading is the only await bridge.</summary>
public partial class EnvironmentLibrary : VBoxContainer
{
    [Signal] public delegate void asset_chosenEventHandler(string path);
    [Signal] public delegate void source_requestedEventHandler(string path);
    public LineEdit search {get;set;}=new();
    public OptionButton category {get;set;}=new();
    public ItemList list {get;set;}=new EnvironmentAssetList();
    public TextureRect preview {get;set;}=new();
    public Label info {get;set;}=new();
    public Godot.Collections.Array<string> _files {get;set;}=new();
    public Godot.Collections.Array<string> _directories {get;set;}=new();
    public DirAccess? _directory {get;set;}
    public string _root {get;set;}="";
    public string _selected {get;set;}="";
    public bool _refresh_due {get;set;}
    private readonly EnvironmentLibraryOperations _operations=new();
    public override void _Ready()=>_operations.ready(this);
    public override void _Process(double delta)=>_operations.process(this);
    public override void _ExitTree()=>_operations.release(this);
    public void scan()=>_operations.scan(this);
    public void refresh()=>_operations.refresh(this);
    public static bool compatible(string path){using var operations=new EnvironmentLibraryOperations();return operations.compatible(path);}
    public void _select(int index)=>_ = SelectPreview(index);
    private async Task SelectPreview(int index)
    {
        string path=_operations.select(this,index);var bridge=GD.Load<GDScript>("res://Workspaces/ModelWorkspace/model_workspace_await_bridge.gd").New().As<Node>();AddChild(bridge);
        try{bridge.Call("run","thumbnail",this,new Godot.Collections.Array {path});var result=await ToSignal(bridge,"completed");if(GodotObject.IsInstanceValid(this)&&IsInsideTree()&&result.Length>0)_operations.set_preview(this,path,result[0].As<Texture2D>());}
        catch(Exception error){if(GodotObject.IsInstanceValid(this)&&IsInsideTree())GD.PushError(error.ToString());}
    }
}
