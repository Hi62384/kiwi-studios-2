using Godot;
using System;
using System.Threading.Tasks;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class ShaderWorkspaceFileJob : Node
{
    [Signal] public delegate void completedEventHandler();
    public bool finished {get;private set;}
    private bool _running;
    private void Done(){if(finished)return;finished=true;if(GodotObject.IsInstanceValid(this))EmitSignal("completed");}
    public override void _ExitTree()=>Done();
    private static bool Current(Control owner,Shader original)=>GodotObject.IsInstanceValid(owner)&&owner.IsInsideTree()&&!owner.IsQueuedForDeletion()&&owner.Get("preview_shader").As<Shader>()==original;
    public void start(Control owner,string kind,StringName parameter,bool fromClipboard){if(_running)return;_running=true;_ = Run(owner,kind,parameter,fromClipboard);}
    private async Task Run(Control owner,string kind,StringName parameter,bool fromClipboard)
    {
        var original=owner.Get("preview_shader").As<Shader>();try
        {
            var operations=new ShaderWorkspaceOperations();var bridge=GD.Load<GDScript>("res://Workspaces/ModelWorkspace/model_workspace_await_bridge.gd").New().As<Node>();AddChild(bridge);var waiting=ToSignal(bridge,"completed");
            if(kind=="save_as")
            {
                var editor=owner.Get("editor").As<Control>();var code=editor.Get("code").As<CodeEdit>();var clipboard=new Shader {Code=code.Text};bridge.Call("run","resource_save",owner,new GArray {"Save shader to project",operations.document_title(owner).GetBaseName(),"gdshader",Array.Empty<string>(),clipboard});var returned=await waiting;if(!Current(owner,original)||returned.Length==0||returned[0].VariantType!=Variant.Type.Dictionary)return;var result=returned[0].AsGodotDictionary();if(!result.TryGetValue("cancelled",out var cancelled)||cancelled.AsBool())return;var source=owner.Get("current_source");if(source.VariantType==Variant.Type.Object&&source.AsGodotObject() is Shader shader){shader.Code=code.Text;shader.EmitChanged();}string path=result.TryGetValue("path",out var destination)?destination.AsString():"";owner.Set("current_path",path);if(path.Length==0)return;owner.Set("current_source",path);owner.Set("requires_path",false);owner.Get("load_shader_button").As<Button>().Hide();editor.Set("current_shader",default);editor.Set("current_path",path);editor.Get("title").As<Label>().Text=path.GetFile();operations.save(owner);return;
            }
            var property=new ActorProperty();Settings options;string id,label,title;
            switch(kind)
            {
                case "mesh":id="preview_mesh";label="Preview Mesh";title="Choose preview mesh";options=new Settings {["extensions"]=new[]{"glb","gltf","fbx","obj","mesh","tres","res"},["native_resource_types"]=new[]{"Mesh","PackedScene"},["file_picker"]=true};break;
                case "shader":id="shader_file";label="Shader";title="Load shader from project";options=new Settings {["extensions"]=new[]{"gdshader"},["file_picker"]=true};break;
                case "environment":id="preview_environment";label="Environment";title="Choose preview environment";options=new Settings {["extensions"]=new[]{"tres","res"},["native_resource_types"]=new[]{"Environment"},["file_picker"]=true};break;
                default:id=kind=="parameter"?parameter.ToString():"canvas_preview_image";label=kind=="parameter"?parameter.ToString():"Canvas Preview Image";title=kind=="parameter"?"Choose preview texture":"Choose canvas preview image";options=new Settings {["extensions"]=new[]{"png","jpg","jpeg","webp","bmp","svg","tga","hdr","exr","tres","res"},["native_resource_types"]=new[]{"Texture2D"},["file_picker"]=true};if(kind=="parameter"){property.Set("object_type",new StringName("image"));options["raw_extensions"]=new[]{"png","jpg","jpeg","webp","svg","bmp","tga","hdr","exr"};options["accepted_object_types"]=new[]{"image","noise_image"};}break;
            }
            property.Set("id",new StringName(id));property.Set("label",label);property.Set("options",options);bridge.Call("run","pick_file",owner,new GArray {property,title,fromClipboard});var values=await waiting;if(!Current(owner,original)||values.Length==0||values[0].VariantType!=Variant.Type.String)return;string selected=values[0].AsString();bool empty=selected=="::empty-resource::";if(selected.Length==0)return;
            if(kind=="shader"){if(!empty)owner.GetTree().GetFirstNodeInGroup("actor_scene_tabs")?.Call("load_shader_into_current_tab",selected);return;}if(kind=="parameter"){if(empty)operations.set_preview_parameter(owner,parameter,default,"edit",default);else owner.Call("_set_parameter_image_path",parameter,selected);return;}
            if(kind=="mesh"){owner.Set("_mesh_mode",empty?"shape":"file");owner.Set("_mesh_path",empty?"":selected);operations.rebuild_mesh(owner);}else if(kind=="environment"){owner.Set("_environment_path",empty?"":selected);operations.apply_environment(owner);}else{owner.Set("_canvas_image_path",empty?"":selected);operations.update_canvas_texture(owner);}owner.EmitSignal("document_changed");
        }
        catch(Exception error){GD.PushError(error.ToString());}
        finally{Done();if(GodotObject.IsInstanceValid(this)&&IsInsideTree())QueueFree();}
    }
}
