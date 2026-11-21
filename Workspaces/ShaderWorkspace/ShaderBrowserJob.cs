using Godot;
using System;
using System.Threading.Tasks;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class ShaderBrowserJob : Node
{
    private bool _running;
    private static bool Current(Control owner)=>GodotObject.IsInstanceValid(owner)&&owner.IsInsideTree()&&!owner.IsQueuedForDeletion();
    public void start(Control owner,string kind,Settings entry){if(_running)return;_running=true;_ = Run(owner,kind,entry,owner.GetTree());}
    private async Task Run(Control owner,string kind,Settings entry,SceneTree tree)
    {
        bool thumbnail=kind=="thumbnail";try
        {
            var operations=new ShaderBrowserOperations();if(kind=="select")
            {
                long revision=operations.BeginSelection(owner,entry);while(owner.Get("_thumbnail_busy").AsBool()){await ToSignal(tree,SceneTree.SignalName.ProcessFrame);if(!Current(owner)||revision!=owner.Get("_selection_revision").AsInt64())return;}var live=owner.Get("live").As<ShaderSamplePreview>();string error=live.show_entry(owner.Get("selected").AsGodotDictionary());live.set_active(owner.IsVisibleInTree()&&error.Length==0);for(int frame=0;frame<3;frame++){await ToSignal(tree,SceneTree.SignalName.ProcessFrame);if(!Current(owner)||revision!=owner.Get("_selection_revision").AsInt64())return;}operations.FinishSelection(owner);return;
            }
            if(thumbnail)
            {
                owner.Set("_thumbnail_busy",true);string key=operations.cache_key(entry);var rendered=entry.Duplicate();rendered["source"]=new ShaderSampleCatalogOperations().get_code(entry);var preview=owner.Get("thumbnail").As<ShaderSamplePreview>();string error=preview.show_entry(rendered);if(error.Length==0)
                {
                    for(int frame=0;frame<4;frame++){await ToSignal(tree,SceneTree.SignalName.ProcessFrame);if(!Current(owner))return;}await ToSignal(Engine.GetSingleton("RenderingServer"),RenderingServer.SignalName.FramePostDraw);if(!Current(owner))return;error=preview.check_errors();if(error.Length==0){using var image=preview.GetTexture().GetImage();if(image!=null&&!image.IsEmpty()){owner.Get("_textures").AsGodotDictionary()[key]=ImageTexture.CreateFromImage(image);DirAccess.MakeDirRecursiveAbsolute(ShaderBrowserOperations.Cache);image.SavePng(ShaderBrowserOperations.Cache+key+".png");}else error="Renderer returned no image.";}
                }
                preview.set_active(false);if(error.Length>0)owner.Get("_failures").AsGodotDictionary()[key]=error;var cards=owner.Get("_cards").AsGodotDictionary();if(cards.TryGetValue(entry["id"].AsString(),out var value)){var card=value.AsGodotDictionary();var textures=owner.Get("_textures").AsGodotDictionary();if(textures.TryGetValue(key,out var texture))card["image"].As<TextureRect>().Texture=texture.As<Texture2D>();card["message"].As<Label>().Text=error.Length==0?"Rendered preview":"Preview unavailable";card["card"].As<Button>().TooltipText=error.Length==0?entry["description"].AsString():error;}return;
            }
            var bridge=GD.Load<GDScript>("res://Workspaces/ModelWorkspace/model_workspace_await_bridge.gd").New().As<Node>();AddChild(bridge);var waiting=ToSignal(bridge,"completed");bridge.Call("run","resource_save",owner,new GArray {"Create shader copy",entry["id"].AsString(),"gdshader",new[]{"gdshader"},default(Variant)});var values=await waiting;if(!Current(owner)||values.Length==0||values[0].VariantType!=Variant.Type.Dictionary)return;var result=values[0].AsGodotDictionary();if(!result.TryGetValue("cancelled",out var cancelled)||cancelled.AsBool())return;string path=result.TryGetValue("path",out var selected)?selected.AsString():"";if(path.Length==0)return;var saved=operations.write_shader_copy(path,entry["source"].AsString());if(saved!=Error.Ok){owner.Get("status").As<Label>().Text="Could not create shader file: "+saved.ToString();return;}operations.mark_used(owner);owner.Get("status").As<Label>().Text="Created "+path;
        }
        catch(Exception error){GD.PushError(error.ToString());}
        finally{if(thumbnail&&Current(owner))owner.Set("_thumbnail_busy",false);if(GodotObject.IsInstanceValid(this)&&IsInsideTree())QueueFree();}
    }
}
