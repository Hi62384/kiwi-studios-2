using Godot;
using System;
using System.Collections.Generic;
using GArray=Godot.Collections.Array;
using Settings=Godot.Collections.Dictionary;
public partial class NaturalMaterialPresetOperations:RefCounted
{
    private const string Directory="user://natural_materials",Index=Directory+"/index.cfg";
    private readonly ImageMaterialResourceOperations _materials=new();
    private static GDScript Bridge=>GD.Load<GDScript>("res://scripts/materials/natural_material_presets.gd");
    public ConfigFile config(){var bridge=Bridge;var config=bridge.Get("_index").As<ConfigFile>();if(config==null){config=new ConfigFile();config.Load(Index);bridge.Set("_index",config);}return config;}
    public Error write(){var error=DirAccess.MakeDirRecursiveAbsolute(Directory);return error!=Error.Ok?error:config().Save(Index);}
    public GArray list_presets()
    {
        var result=new List<Settings>();var settings=config();foreach(string id in settings.GetSections())if(id!="preferences")result.Add(new Settings{["id"]=id,["name"]=settings.GetValue(id,"name",id),["material_id"]=settings.GetValue(id,"material_id","wood/oak")});using var compare=new Expression();compare.Parse("a.naturalnocasecmp_to(b)",new[]{"a","b"});result.Sort((a,b)=>compare.Execute(new GArray{a["name"],b["name"]}).AsInt32());var output=new GArray();foreach(var item in result)output.Add(item);return output;
    }
    private static bool IsMaterial(Resource? value)=>value is KiwiTextureMaterial;
    public Resource? load_material(string id){if(!config().HasSection(id))return null;var material=ResourceLoader.Load(Directory+"/"+id+".tres","",ResourceLoader.CacheMode.Ignore);return IsMaterial(material)?_materials.copy_material(material):null;}
    public string save_material(Resource value,string id)
    {
        if(id.Length==0)id="material_"+Time.GetUnixTimeFromSystem().ToString(System.Globalization.CultureInfo.InvariantCulture).Replace(".","_")+"_"+GD.Randi();
        if(!id.IsValidFileName()||id.Contains('/')||id.Contains('\\')||id=="preferences")return "";
        if(DirAccess.MakeDirRecursiveAbsolute(Directory)!=Error.Ok)return "";using var copy=_materials.copy_material(value);copy.Set("coverage",default(Variant));copy.Set("source",default(Variant));if(ResourceSaver.Save(copy,Directory+"/"+id+".tres")!=Error.Ok)return "";config().SetValue(id,"name",copy.Get("label"));config().SetValue(id,"material_id",copy.Get("material_id"));return write()==Error.Ok?id:"";
    }
    public Error remove(string id){if(!config().HasSection(id))return Error.DoesNotExist;config().EraseSection(id);var error=write();return error!=Error.Ok?error:DirAccess.RemoveAbsolute(Directory+"/"+id+".tres");}
    public string import_file(string path){var value=ResourceLoader.Load(path,"",ResourceLoader.CacheMode.Ignore);return IsMaterial(value)?save_material(value,""):"";}
    public Error export_file(string id,string path){using var value=load_material(id);return value!=null?ResourceSaver.Save(value,path):Error.DoesNotExist;}
    public GArray favorites()=>config().GetValue("preferences","favorites",new GArray()).AsGodotArray();
    public void set_favorite(string id,bool enabled){var values=favorites();if(enabled&&!values.Contains(id))values.Add(id);if(!enabled)values.Remove(id);config().SetValue("preferences","favorites",values);write();}
    public GArray recent()=>config().GetValue("preferences","recent",new GArray()).AsGodotArray();
    public void mark_used(string id){var values=recent();values.Remove(id);values.Insert(0,id);if(values.Count>24)values.Resize(24);config().SetValue("preferences","recent",values);write();}
}
