using Godot;
using System;
using System.Linq;
using Settings=Godot.Collections.Dictionary;

public partial class EnvironmentWorkspaceOperations
{
    public EnvironmentWorkspaceFileJob choose_file(Control owner,string kind,string id,int index)
    {var job=new EnvironmentWorkspaceFileJob();owner.AddChild(job);job.start(owner,kind,id,index);return job;}
    private void Placement(Control owner,string path,bool recent)
    {var canvas=Field<Control>(owner,"canvas");canvas.Set("placement_asset",path);canvas.Set("environment_tool","Place");Field<Button>(owner,"_asset_name").Text=path.GetFile();if(recent){var paths=owner.Get("_recent_assets").AsGodotArray();if(!paths.Any(value=>value.AsString()==path))paths.Add(path);}refresh_context(owner);canvas.GrabFocus();}
    public bool choose_asset_path(Control owner,string path)
    {var result=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/environment_assets.gd").Call("load_parts",path).AsGodotDictionary();string error=result["error"].AsString();if(error.Length>0){Status(owner,error);return false;}Placement(owner,path,true);return true;}
    public void add_palette_path(Control owner,string id,string path)
    {var session=Session(owner);var values=Get(Document(session).Get("component_settings").AsGodotDictionary(),id,new Settings()).AsGodotDictionary();var scatter=Get(values,"scatter").As<Resource>();if(scatter==null||path.Length==0)return;var palette=scatter.Get("palette").AsGodotArray();if(palette.Any(value=>value.AsGodotDictionary()["source"].VariantType==Variant.Type.String&&value.AsGodotDictionary()["source"].AsString()==path))return;session.Call("begin");palette.Add(new Settings {["source"]=path,["weight"]=1.0});session.Call("commit","Add scatter palette model");}
    public void library_asset(Control owner,string path)
    {
        string extension=path.GetExtension().ToLowerInvariant();var resource=extension is "tres" or "res"?ResourceLoader.Load(path):null;var session=Session(owner);if(resource!=null&&ScriptType(resource,"res://Workspaces/EnvironmentWorkspace/environment_document.gd")){Status(owner,session.Call("insert_environment",resource).AsString());return;}
        bool material=extension is "png" or "jpg" or "jpeg" or "webp"||resource is Material or Texture2D||(resource!=null&&ScriptType(resource,"res://scripts/actors/core/actor_object_data.gd")&&new[]{"material","natural_material","shader_material","image","noise_image"}.Contains(resource.Get("type_id").AsString()));
        if(material){var item=session.Call("primary").As<Resource>();if(item==null||_documents.terrain(Document(session),item.Get("id").AsString())==null){Status(owner,"Select a terrain to assign this ground material.");return;}session.Call("begin");Document(session).Get("component_settings").AsGodotDictionary()[item.Get("id")].AsGodotDictionary()["material"]=path;session.Call("commit","Assign terrain material");return;}
        var result=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/environment_assets.gd").Call("load_parts",path).AsGodotDictionary();string error=result["error"].AsString();if(error.Length>0){Status(owner,error);return;}Placement(owner,path,false);
    }
    public void add_scatter(Control owner)
    {
        var session=Session(owner);var document=Document(session);var item=session.Call("primary").As<Resource>();string id=item!=null&&_documents.terrain(document,item.Get("id").AsString())!=null?item.Get("id").AsString():"";if(id.Length==0)foreach(var value in document.Get("components").AsGodotArray()){string candidate=value.As<Resource>().Get("id").AsString();if(_documents.terrain(document,candidate)!=null){id=candidate;break;}}if(id.Length==0){Status(owner,"Add or select a terrain first.");return;}string asset=Field<Control>(owner,"canvas").Get("placement_asset").AsString();if(asset.Length==0)choose_file(owner,"scatter",id,0);else Status(owner,session.Call("add_scatter",id,asset).AsString());
    }
    public void command(Control owner,string command)
    {var session=Session(owner);var selected=session.Get("selected").AsGodotArray();var components=Document(session).Get("components").AsGodotArray();if(command=="Select all"){selected.Clear();foreach(var item in components)selected.Add(item.As<Resource>().Get("id"));}else if(command=="Invert selection"){var ids=selected.Duplicate();ids.Clear();foreach(var item in components){string id=item.As<Resource>().Get("id").AsString();if(!selected.Any(value=>value.AsString()==id))ids.Add(id);}Assign(selected,ids);}session.EmitSignal("changed");}
    public void place_tool(Control owner)
    {var canvas=Field<Control>(owner,"canvas");canvas.Set("environment_tool","Place");refresh_context(owner);if(canvas.Get("placement_asset").AsString().Length==0)choose_file(owner,"asset","",0);}
    public void open_model(Control owner,string path)=>owner.GetTree().GetFirstNodeInGroup("actor_scene_tabs")?.Call("open_model",path);
    public void open_library_source(Control owner,string path)
    {
        var tabs=owner.GetTree().GetFirstNodeInGroup("actor_scene_tabs");if(tabs==null)return;string extension=path.GetExtension().ToLowerInvariant();if(extension is "png" or "jpg" or "jpeg" or "webp"){tabs.Call("open_image",path);return;}var resource=extension is "tres" or "res"?ResourceLoader.Load(path):null;if(resource!=null&&ScriptType(resource,"res://Workspaces/EnvironmentWorkspace/environment_document.gd"))tabs.Call("open_environment",path);else if(resource is ShaderMaterial material)tabs.Call("open_shader",material.Shader,material);else if(resource is Material||(resource!=null&&ScriptType(resource,"res://scripts/actors/core/actor_object_data.gd")))Status(owner,"Use this material on a terrain; edit its source through the project resource inspector.");else tabs.Call("open_model",path);
    }
    public void unhandled_key_input(Control owner,InputEvent input)
    {if(!owner.IsVisibleInTree()||input is not InputEventKey key||!key.Pressed||!key.CtrlPressed)return;switch(key.Keycode){case Key.S:owner.Call(key.ShiftPressed?"save_as":"save");break;case Key.Z:Session(owner).Call(key.ShiftPressed?"redo":"undo");break;case Key.Y:Session(owner).Call("redo");break;default:return;}owner.GetViewport().SetInputAsHandled();}
}
