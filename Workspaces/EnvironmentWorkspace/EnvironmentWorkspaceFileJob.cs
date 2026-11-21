using Godot;
using System;
using System.Threading.Tasks;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class EnvironmentWorkspaceFileJob : Node
{
    [Signal] public delegate void completedEventHandler();
    public bool finished {get;private set;}
    public string result {get;private set;}="";
    private bool _running;
    public void start(Control owner,string kind,string id,int index){if(_running)return;_running=true;_ = Run(owner,kind,id,index);}
    private static Settings Options(string[] extensions,string[] native,string[]? accepted=null,string[]? raw=null)
    {var options=new Settings {["extensions"]=extensions,["native_resource_types"]=native};if(accepted!=null)options["accepted_object_types"]=accepted;if(raw!=null)options["raw_extensions"]=raw;return options;}
    private async Task Run(Control owner,string kind,string id,int index)
    {
        var session=owner.Get("session").As<RefCounted>();try
        {
            Settings options;string title;
            switch(kind)
            {
                case "biome":options=Options(new[]{"tres","res","png","jpg","jpeg","webp"},new[]{"Material","Texture2D"},new[]{"material","natural_material","image","noise_image"});title="Choose biome surface";break;
                case "ground":case "paint":options=Options(new[]{"tres","res","png","jpg","jpeg","webp"},new[]{"Material","Texture2D"},new[]{"material","natural_material","shader_material","image","noise_image"});title="Choose ground material";break;
                case "stamp":options=Options(new[]{"png","jpg","jpeg","webp"},new[]{"Texture2D"},null,new[]{"png","jpg","jpeg","webp"});title="Choose a terrain height stamp";break;
                case "world":options=Options(new[]{"tres","res"},new[]{"Environment"},new[]{"environment"});title="Choose world / sky environment";break;
                case "open":options=Options(new[]{"tres","res"},new[]{"KiwiEnvironmentDocument"});title="Open environment";break;
                case "asset":case "palette":case "scatter":options=Options(new[]{"tres","res","mesh","glb","gltf","obj"},new[]{"KiwiModelDocument","Mesh","PackedScene"},null,new[]{"glb","gltf","obj"});title="Choose an environment model";break;
                default:options=Options(new[]{"tres","res"},new[]{"Material"},new[]{"material","natural_material","shader_material"});title="Choose water material";break;
            }
            var property=new ActorProperty();property.Set("options",options);var bridge=GD.Load<GDScript>("res://Workspaces/ModelWorkspace/model_workspace_await_bridge.gd").New().As<Node>();AddChild(bridge);bridge.Call("run","pick_file",owner,new GArray {property,title});var returned=await ToSignal(bridge,"completed");if(!GodotObject.IsInstanceValid(owner)||!owner.IsInsideTree()||owner.Get("session").As<RefCounted>()!=session||returned.Length==0||returned[0].VariantType!=Variant.Type.String)return;string path=returned[0].AsString();if(path.Length==0)return;bool empty=path=="::empty-resource::";
            var native=Engine.GetSingleton("KiwiNativeServices").Call("service","environment_workspace").As<EnvironmentWorkspaceOperations>();var document=session.Get("document").As<Resource>();
            switch(kind)
            {
                case "biome":
                    if(empty)return;using(var documents=new EnvironmentDocumentOperations()){var terrain=documents.terrain(document,id);var biomes=terrain?.Get("biomes").As<Resource>();if(biomes==null||index>=biomes.Get("definitions").AsGodotArray().Count)return;}
                    native.EditBiomes(owner,id,next=>{var definition=next.Get("definitions").AsGodotArray()[index].AsGodotDictionary();var values=definition.TryGetValue("materials",out var materials)?materials.AsGodotArray():new GArray();values.Add(path);definition["materials"]=values;});break;
                case "ground":case "paint":
                    var all=document.Get("component_settings").AsGodotDictionary();if(!all.ContainsKey(id))return;session.Call("begin");all[id].AsGodotDictionary()[kind=="paint"?"paint_material":"material"]=empty?default:Variant.From(path);session.Call("commit","Assign terrain material");break;
                case "world":session.Call("begin");document.Set("environment_source",empty?"":path);session.Call("commit","Assign world environment");break;
                case "stamp":
                    var canvas=owner.Get("canvas").As<Control>();canvas.Set("stamp_path",empty?"":path);canvas.Set("stamp_image",empty?default:GD.Load<CSharpScript>("res://scripts/actors/core/ActorImageGenerator.cs").Call("image_from_value",path));native.refresh_context(owner);break;
                case "open":if(!empty)owner.GetTree().GetFirstNodeInGroup("actor_scene_tabs")?.Call("open_environment",path);break;
                case "asset":case "palette":case "scatter":
                    if(empty||!native.choose_asset_path(owner,path))return;result=path;if(kind=="palette")native.add_palette_path(owner,id,path);else if(kind=="scatter")owner.Get("status").As<Label>().Text=session.Call("add_scatter",id,path).AsString();break;
                default:native.EditWater(owner,id,next=>next.Set("material_asset",empty?"":path));break;
            }
        }
        catch(Exception error){GD.PushError(error.ToString());}
        finally{finished=true;if(GodotObject.IsInstanceValid(this)){EmitSignal(SignalName.completed);if(IsInsideTree())QueueFree();}}
    }
}
