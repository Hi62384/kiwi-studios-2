using Godot;
using System;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;
public partial class ImageWorkspaceOperations
{
    public Resource object_picker_property(string type)
    {
        var property=new ActorProperty();property.Set("object_type",type);property.Set("options",new Settings{["extensions"]=new GArray{"tres","res"},["accepted_object_types"]=new GArray{type},["file_picker"]=true});return property;
    }
    public void object_picker_result(Control owner,Resource layer,string type,string chosen)
    {
        var document=Document(owner);if(_documents.layer_for_id(document,layer.Get("id").AsString())!=layer)return;bool noise=type=="noise_image";string key=noise?"noise_object":"text_settings",pathKey=noise?"noise_path":"text_settings_path";var properties=layer.Get("properties").AsGodotDictionary();if(chosen=="::empty-resource::"){Action(owner,()=>{properties[key]=default(Variant);if(noise)layer.Set("texture",default(Variant));properties.Remove(pathKey);});return;}if(chosen.Length==0)return;var loaded=ResourceLoader.Load(chosen,"",ResourceLoader.CacheMode.Ignore);if(!ScriptIs(loaded,"res://scripts/actors/core/actor_object_data.gd")||loaded!.Get("type_id").AsString()!=type){owner.Get("status").As<Label>().Text=noise?"Choose a Noise Image resource.":"Choose a Text Settings resource.";return;}Action(owner,()=>{properties[key]=loaded.Call("copy_object");properties[pathKey]=chosen;if(noise)refresh_noise_layer(layer);});
    }
    public void save_text_settings_result(Control owner,Resource layer,Resource settings,Settings result)
    {
        if(Get(result,"cancelled",true).AsBool())return;string destination=Get(result,"path","").AsString();if(destination.Length==0)return;if(ResourceSaver.Save(settings.Call("copy_object").As<Resource>(),destination)!=Error.Ok)return;Action(owner,()=>layer.Get("properties").AsGodotDictionary()["text_settings_path"]=destination);owner.Call("_refresh_project_files");owner.Get("status").As<Label>().Text="Saved Text Settings";
    }
    public void choose_image_result(Control owner,string chosen){if(chosen.Length==0||chosen=="::empty-resource::")return;var tabs=owner.GetTree().GetFirstNodeInGroup("actor_scene_tabs");if(tabs!=null)tabs.Call("open_image",chosen);else open_source(owner,chosen,new Settings());}
    public void choose_import_result(Control owner,string chosen){if(chosen=="::empty-resource::")add_layer(owner,"image");else if(chosen.Length>0)import_paths(owner,new[]{chosen},(Vector2)Document(owner).Get("canvas_size").AsVector2I()*.5f);}
    public bool save_project_as_result(Control owner,Settings result){if(Get(result,"cancelled",true).AsBool())return false;owner.Set("document_path",result["path"].AsString());return true;}
    public bool save_as_result(Control owner,Settings result){if(Get(result,"cancelled",true).AsBool())return false;string path=result["path"].AsString();Document(owner).Set("output_path",path);owner.Set("path",path);owner.Set("source",path);return true;}
    public void prepare_wait_for_repair(Control owner){var repair=Canvas(owner).Get("repair_tool").As<RefCounted>();if(repair.Get("active").AsBool())_repair.finish(repair);}
    public bool repair_pending(Control owner){var canvas=Canvas(owner);var repair=canvas.Get("repair_tool").As<RefCounted>();return canvas.Get("_material_busy").AsBool()||repair.Get("active").AsBool()||(_repairEngine.busy(repair.Get("engine").As<Node>())&&repair.Get("_generation_target").AsString().Length>0);}
    private readonly ImageRepairEngineOperations _repairEngine=new();
    public void write_layer_export(Control owner,Image? bitmap,string basePath,string label){if(bitmap==null)return;using var expression=new Expression();expression.Parse("name.validate_filename()",new[]{"name"});string filename=expression.Execute(new GArray{label}).AsString();write_bitmap(bitmap,basePath.PathJoin(filename+".png"));}
}
