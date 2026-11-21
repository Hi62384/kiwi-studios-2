using Godot;
using System;
using Settings=Godot.Collections.Dictionary;
public partial class ImageRepairInteractionOperations
{
    private static Resource? ResourceOrNull(Variant value)=>value.VariantType==Variant.Type.Object?value.AsGodotObject() as Resource:null;
    private static bool ScriptIs(GodotObject? value,string name){var script=value?.GetScript().As<Script>();while(script!=null){if(script.ResourcePath=="res://Workspaces/ImageWorkspace/"+name+".gd")return true;script=script.GetBaseScript();}return false;}
    public void initialize(RefCounted owner,Control studio)
    {
        owner.Set("workspace",studio);var canvas=studio.Get("canvas").As<Control>();owner.Set("canvas",canvas);owner.Set("material",_definitions.create("wood/oak"));Config(owner)["editable_texture"]=true;var engine=Engine(owner);canvas.AddChild(engine);engine.Connect("preview",new Callable(owner,"_on_preview"));engine.Connect("idle",new Callable(owner,"_on_idle"));
    }
    public Settings settings(RefCounted owner)
    {
        var result=new Settings();foreach(string name in new[]{"mode","main_mode","repair_source","repair_method","texture_source","favorites","recent","pattern_path","source_point","source_area"})result[name]=owner.Get(name);
        var material=owner.Get("material").As<Resource>();result["material"]=material!=null?Variant.From(_materials.copy_material(material)):default(Variant);result["instances"]=owner.Get("material_instances").AsGodotDictionary().Duplicate();result["custom_materials"]=owner.Get("custom_materials").AsGodotDictionary().Duplicate();result["mode_settings"]=owner.Get("mode_settings").AsGodotDictionary().Duplicate(true);result["config"]=Config(owner).Duplicate(true);result["recipe"]=_procedural.copy_recipe(owner.Get("recipe").As<Resource>());return result;
    }
    public void restore_settings(RefCounted owner,Settings state)
    {
        string mode=Get(state,"mode","spot").AsString();owner.Set("mode",mode);Config(owner).Merge(Get(state,"config",new Settings()).AsGodotDictionary(),true);
        owner.Set("main_mode",Get(state,"main_mode",mode is "procedural" or "pattern_fill"?"texture":"repair"));owner.Set("repair_source",Get(state,"repair_source",mode is "clone" or "heal" or "pattern_heal"?"sample":"nearby"));owner.Set("repair_method",Get(state,"repair_method",mode=="clone"?"exact":"natural"));owner.Set("texture_source",Get(state,"texture_source","procedural"));
        owner.Set("custom_materials",Get(state,"custom_materials",new Settings()).AsGodotDictionary().Duplicate());owner.Set("mode_settings",Get(state,"mode_settings",new Settings()).AsGodotDictionary().Duplicate(true));
        var material=ResourceOrNull(Get(state,"material"));if(ScriptIs(material,"texture_material"))owner.Set("material",_materials.copy_material(material!));
        var instances=Get(state,"instances",new Settings()).AsGodotDictionary().Duplicate();owner.Set("material_instances",instances);owner.Set("favorites",Get(state,"favorites",Array.Empty<string>()));owner.Set("recent",Get(state,"recent",Array.Empty<string>()));
        var keys=new System.Collections.Generic.List<Variant>(instances.Keys);foreach(var key in keys){var value=ResourceOrNull(instances[key]);if(ScriptIs(value,"texture_material"))instances[key]=_materials.copy_material(value!);}
        var recipe=ResourceOrNull(Get(state,"recipe"));if(ScriptIs(recipe,"image_texture_recipe"))owner.Set("recipe",_procedural.copy_recipe(recipe!));
        string path=Get(state,"pattern_path","").AsString();owner.Set("pattern_path",path);owner.Set("source_point",Get(state,"source_point",Vector2.Zero));owner.Set("source_area",Get(state,"source_area",new Rect2I()));
        if(FileAccess.FileExists(path))
        {
            if(path.GetExtension() is "tres" or "res"){var resource=ResourceLoader.Load(path);if(ScriptIs(resource,"image_pattern_preset")&&resource.Get("texture").AsGodotObject()!=null)owner.Set("source_image",resource.Get("texture").As<Texture2D>().GetImage());else if(resource is Texture2D texture)owner.Set("source_image",texture.GetImage());}
            else owner.Set("source_image",Image.LoadFromFile(path));
        }
    }
    public bool prepare_sample(RefCounted owner,Vector2 point)
    {
        var item=layer(owner);if(item==null)return false;if(Config(owner)["sample_mode"].AsString()!="current")return true;var texture=item.Get("texture").As<Texture2D>();if(texture==null)return false;using var source=texture.GetImage();owner.Set("source_image",source.Duplicate());owner.Set("source_point",to_pixel(owner,point,item));complete_sample(owner,point);return false;
    }
    public void complete_sample(RefCounted owner,Vector2 point)
    {
        var source=owner.Get("source_image").As<Image>();var at=owner.Get("source_point").AsVector2();var canvas=Canvas(owner);if(source==null||!new Rect2(Vector2.Zero,(Vector2)source.GetSize()).HasPoint(at)){owner.Set("source_image",default(Variant));owner.Set("source_area",new Rect2I());owner.Set("sampling",false);canvas.EmitSignal("hint_changed","Choose a source inside the image");return;}
        owner.Set("sample_document_point",point);owner.Set("_has_alignment",false);if(owner.Get("mode").AsString() is "heal" or "clone" or "pattern_heal" or "pattern_fill" or "patch")Config(owner)["source_mode"]="manual";
        int size=Math.Max(2,Config(owner)["sample_size"].AsInt32());owner.Set("source_area",new Rect2I((Vector2I)at-Vector2I.One*size/2,Vector2I.One*size).Intersection(new Rect2I(Vector2I.Zero,source.GetSize())));canvas.EmitSignal("hint_changed","Source sampled · Alt-drag to choose a texture region");canvas.QueueRedraw();owner.Set("sampling",owner.Get("_sample_down"));owner.Set("_sample_region_dragged",false);owner.Set("_sample_start",at);owner.Set("source_points",new[]{at});owner.EmitSignal("settings_changed");
    }
    public void begin_patch_source(RefCounted owner,Vector2 at,Resource item)
    {
        var canvas=Canvas(owner);Image source;if(owner.Get("active").AsBool())source=owner.Get("_original").As<Image>();else{using var image=item.Get("texture").As<Texture2D>().GetImage();source=(Image)image.Duplicate();}owner.Set("source_image",source);
        var used=canvas.Get("selection").As<Image>().GetUsedRect();if(!used.HasArea())return;var corners=new[]{(Vector2)used.Position,new Vector2(used.End.X,used.Position.Y),(Vector2)used.End,new Vector2(used.Position.X,used.End.Y)};var bounds=new Rect2();bool first=true;
        foreach(var corner in corners){var world=owner.Call("_selection_forward_point",corner).AsVector2();var local=to_pixel(owner,world,item);if(first){bounds=new Rect2(local,Vector2.Zero);first=false;}else bounds=bounds.Expand(local);}
        var patch=new Rect2I((Vector2I)bounds.Position.Floor(),(Vector2I)bounds.Size.Ceil());owner.Set("_patch_rect",patch);var area=patch.Intersection(new Rect2I(Vector2I.Zero,source.GetSize()));owner.Set("source_area",area);owner.Set("source_point",((Rect2)area).GetCenter());Config(owner)["sample_shape"]="rectangle";owner.Set("source_points",Array.Empty<Vector2>());owner.Set("sampling",true);owner.Set("_patch_drag",true);owner.Set("_sample_region_dragged",true);owner.Set("_sample_start",to_pixel(owner,at,item));owner.Set("sample_document_point",at);canvas.EmitSignal("hint_changed","Drag the selection onto clean source texture · release to sample");
    }
}
