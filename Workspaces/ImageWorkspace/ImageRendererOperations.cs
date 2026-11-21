using Godot;
using System;
using System.Collections.Generic;
using GArray=Godot.Collections.Array;
using Settings=Godot.Collections.Dictionary;
public partial class ImageRendererOperations:RefCounted
{
    private readonly ImageDocumentOperations _documents=new();private readonly ImageLayerOperations _layers=new();private readonly ImageMaterialResourceOperations _resources=new();private readonly ImageTextureMaterialRendererOperations _materials=new();private readonly ImageValueOperations _values=new();
    private const int Pad=48;
    private static Variant Get(Settings data,string key,Variant fallback=default)=>data.TryGetValue(key,out var value)?value:fallback;
    private static Settings Views(Node owner)=>owner.Get("views").AsGodotDictionary();
    private static Resource Document(Node owner)=>owner.Get("document").As<Resource>();
    private static bool ScriptIs(Resource? value,string path){var script=value?.GetScript().As<Script>();while(script!=null){if(script.ResourcePath==path||script.ResourcePath==LegacyResourceLoader.NativeScriptPath(path))return true;script=script.GetBaseScript();}return false;}
    public void invalidate_layer(Node owner,string id)
    {
        if(owner.Get("document").AsGodotObject()==null||!Views(owner).ContainsKey(id))return;owner.Get("_dirty_layers").AsGodotDictionary()[id]=true;var affected=new Settings{[id]=true};propagate_render_dependencies(owner,affected);var views=Views(owner);foreach(var key in affected.Keys){if(!views.ContainsKey(key))continue;var view=views[key].AsGodotDictionary();view["frames_left"]=owner.Get("_settling_frames");if(owner.Get("_enabled").AsBool())set_layer_update_mode(view,(int)SubViewport.UpdateMode.Always);}
    }
    private static void Watch(Node owner,Resource? resource,string id){if(resource!=null)owner.Call("_watch_source",resource,id);}
    public Variant source_stamp(Node owner,Variant value,string id)
    {
        if(value.VariantType==Variant.Type.Dictionary){var parts=new GArray();foreach(var pair in value.AsGodotDictionary()){parts.Add(pair.Key);parts.Add(source_stamp(owner,pair.Value,id));}return GD.Hash(parts);}
        if(value.VariantType==Variant.Type.Array){var parts=new GArray();foreach(var item in value.AsGodotArray())parts.Add(source_stamp(owner,item,id));return GD.Hash(parts);}
        var resource=value.VariantType==Variant.Type.Object?value.AsGodotObject() as Resource:null;if(resource!=null)
        {
            Watch(owner,resource,id);if(resource is Shader shader)return GD.Hash(shader.Code);if(ScriptIs(resource,"res://scripts/actors/core/actor_object_data.gd"))return source_stamp(owner,resource.Get("values"),id);
            if(ScriptIs(resource,"res://Workspaces/ImageWorkspace/texture_material.gd")){Watch(owner,resource.Get("image").As<Resource>(),id);Watch(owner,resource.Get("mix_mask").As<Resource>(),id);var secondary=resource.Get("secondary").As<Resource>();if(secondary!=null)source_stamp(owner,secondary,id);return live_material_signature(resource);}
            if(resource is Curve curve){var points=new GArray{curve.MinValue,curve.MaxValue};for(int i=0;i<curve.PointCount;i++)points.Add(new GArray{curve.GetPointPosition(i),curve.GetPointLeftTangent(i),curve.GetPointRightTangent(i),(int)curve.GetPointLeftMode(i),(int)curve.GetPointRightMode(i)});return GD.Hash(points);}
        }
        return value;
    }
    public long layer_source_stamp(Node owner,Resource layer)
    {
        string id=layer.Get("id").AsString();var document=Document(owner);var parts=new GArray();foreach(string key in new[]{"kind","dimensions","position","rotation","opacity","blend","visible","isolated","clip_to_below"})parts.Add(layer.Get(key));parts.Add(_documents.isolation_allows(document,layer));parts.Add(_documents.world_transform(document,layer));parts.Add(owner.Get("render_scale"));foreach(string key in new[]{"texture","mask","properties","effects"})parts.Add(source_stamp(owner,layer.Get(key),id));var warp=layer.Get("warp").AsGodotObject();if(warp!=null)parts.Add(new GArray{warp,warp.Get("enabled"),warp.Get("revision")});
        foreach(var value in layer.Get("live_paint").AsGodotArray()){var region=value.As<Resource>();var fields=new GArray();foreach(string key in new[]{"id","template_id","mapping","opacity","coordinate_rect"})fields.Add(region.Get(key));foreach(string key in new[]{"coverage","coordinates","raster"})fields.Add(source_stamp(owner,region.Get(key),id));parts.Add(fields);var template=_documents.live_material_for_id(document,region.Get("template_id").AsString());if(template!=null)parts.Add(new GArray{template.Get("visible"),source_stamp(owner,template.Get("material"),id)});}return GD.Hash(parts);
    }
    public bool animated_source(Variant value)
    {
        if(value.VariantType==Variant.Type.Dictionary){foreach(var entry in value.AsGodotDictionary().Values)if(animated_source(entry))return true;return false;}if(value.VariantType==Variant.Type.Array){foreach(var entry in value.AsGodotArray())if(animated_source(entry))return true;return false;}
        var resource=value.VariantType==Variant.Type.Object?value.AsGodotObject() as Resource:null;if(ScriptIs(resource,"res://Workspaces/ImageWorkspace/texture_material.gd"))return animated_source(resource!.Get("image"))||animated_source(resource.Get("mix_mask"))||animated_source(resource.Get("secondary"));if(resource is AtlasTexture atlas)return animated_source(atlas.Atlas);return resource is Texture2D texture&&(texture is ViewportTexture||texture.GetClass().ToString() is "AnimatedTexture" or "CameraTexture" or "ExternalTexture");
    }
    public bool layer_needs_time(Node owner,Resource layer)
    {
        if(animated_source(layer.Get("texture"))||animated_source(layer.Get("mask"))||animated_source(layer.Get("properties")))return true;foreach(var value in layer.Get("effects").AsGodotArray()){var effect=value.AsGodotDictionary();if(!Get(effect,"enabled",true).AsBool())continue;if(animated_source(Get(effect,"uniforms",new Settings())))return true;var shaderValue=Get(effect,"shader");var shader=shaderValue.VariantType==Variant.Type.Object?shaderValue.AsGodotObject() as Shader:null;if(shader!=null&&(shader.Code.Contains("TIME",StringComparison.Ordinal)||shader.Code.Contains("#include",StringComparison.Ordinal)||shader.Code.Contains("global uniform",StringComparison.Ordinal)))return true;}
        foreach(var value in layer.Get("live_paint").AsGodotArray()){var region=value.As<Resource>();if(animated_source(region.Get("coverage"))||animated_source(region.Get("raster"))||animated_source(region.Get("coordinates")))return true;var template=_documents.live_material_for_id(Document(owner),region.Get("template_id").AsString());if(template!=null&&animated_source(template.Get("material")))return true;}return false;
    }
    public long live_material_signature(Resource material)
    {
        var parts=new GArray();foreach(string key in new[]{"material_id","parameters","image","texture_size","rotation","alignment","mapping_origin","tint_strength","tiling","blending","mix_amount","mix_distribution","mix_mask","relief","relief_softness","light_direction","highlight","shadow"})parts.Add(material.Get(key));var secondary=material.Get("secondary").As<Resource>();parts.Add(secondary!=null?live_material_signature(secondary):0);return GD.Hash(parts);
    }
    public void propagate_render_dependencies(Node owner,Settings affected)
    {
        var document=Document(owner);bool changed=true;while(changed){changed=false;foreach(var entry in document.Get("layers").AsGodotArray()){var layer=entry.As<Resource>();if(!affected.ContainsKey(layer.Get("id")))continue;var parent=_documents.layer_for_id(document,layer.Get("parent_id").AsString());var seen=new HashSet<string>();while(parent!=null&&seen.Add(parent.Get("id").AsString())){var id=parent.Get("id");if(parent.Get("kind").AsString()=="group"&&!affected.ContainsKey(id)){affected[id]=true;changed=true;}parent=_documents.layer_for_id(document,parent.Get("parent_id").AsString());}var siblings=_documents.children(document,layer.Get("parent_id").AsString());int next=siblings.IndexOf(layer)+1;if(next>0&&next<siblings.Count){var following=siblings[next].As<Resource>();var id=following.Get("id");if(following.Get("clip_to_below").AsBool()&&!affected.ContainsKey(id)){affected[id]=true;changed=true;}}}}
    }
    public void schedule_cached_layers(Node owner)
    {
        var dynamic=new Settings();owner.Set("_settling_frames",8);var dependencies=new Settings();var document=Document(owner);var views=Views(owner);var dirty=owner.Get("_dirty_layers").AsGodotDictionary();foreach(var entry in document.Get("layers").AsGodotArray()){var layer=entry.As<Resource>();var id=layer.Get("id");if(!views.ContainsKey(id))continue;var view=views[id].AsGodotDictionary();long signature=layer_source_stamp(owner,layer);if(Get(view,"cache_signature",-1).AsInt64()!=signature){view["cache_signature"]=signature;dirty[id]=true;}if(layer_needs_time(owner,layer))dynamic[id]=true;owner.Set("_settling_frames",Math.Max(owner.Get("_settling_frames").AsInt32(),render_dependency_frames(owner,layer,dependencies,new Settings())+3));}propagate_render_dependencies(owner,dirty);propagate_render_dependencies(owner,dynamic);foreach(var pair in views){var view=pair.Value.AsGodotDictionary();view["dynamic"]=dynamic.ContainsKey(pair.Key);if(dirty.ContainsKey(pair.Key))view["frames_left"]=owner.Get("_settling_frames");bool render=owner.Get("_enabled").AsBool()&&(owner.Get("exporting").AsBool()||view["dynamic"].AsBool()||Get(view,"frames_left",0).AsInt32()>0);set_layer_update_mode(view,(int)(render?SubViewport.UpdateMode.Always:SubViewport.UpdateMode.Disabled));}dirty.Clear();
    }
    public int render_dependency_frames(Node owner,Resource layer,Settings memo,Settings seen)
    {
        var id=layer.Get("id");if(memo.TryGetValue(id,out var cached))return cached.AsInt32();var views=Views(owner);if(seen.ContainsKey(id)||!views.ContainsKey(id))return 0;seen=seen.Duplicate();seen[id]=true;var view=views[id].AsGodotDictionary();var stages=view["stages"].AsGodotArray();int passes=stages.Count+1;foreach(var stage in stages)if(stage.AsGodotDictionary()["input_viewport"].AsGodotObject()!=null)passes++;int dependency=0;var document=Document(owner);if(layer.Get("kind").AsString()=="group")foreach(var child in _documents.children(document,id.AsString()))dependency=Math.Max(dependency,render_dependency_frames(owner,child.As<Resource>(),memo,seen));if(layer.Get("clip_to_below").AsBool()){var siblings=_documents.children(document,layer.Get("parent_id").AsString());int previous=siblings.IndexOf(layer)-1;if(previous>=0)dependency=Math.Max(dependency,render_dependency_frames(owner,siblings[previous].As<Resource>(),memo,seen));}memo[id]=passes+dependency;return passes+dependency;
    }
    public void set_layer_update_mode(Settings view,int mode){view["base"].As<SubViewport>().RenderTargetUpdateMode=(SubViewport.UpdateMode)mode;foreach(var value in view["stages"].AsGodotArray()){var stage=value.AsGodotDictionary();stage["viewport"].As<SubViewport>().RenderTargetUpdateMode=(SubViewport.UpdateMode)mode;var input=stage["input_viewport"].As<SubViewport>();if(input!=null)input.RenderTargetUpdateMode=(SubViewport.UpdateMode)mode;}}
    public void settle_cached_layers(Node owner)
    {
        if(!owner.Get("_enabled").AsBool())return;foreach(var value in Views(owner).Values){var view=value.AsGodotDictionary();if(view["base"].As<SubViewport>().RenderTargetUpdateMode!=SubViewport.UpdateMode.Disabled)view["frames_rendered"]=Get(view,"frames_rendered",0).AsInt32()+1;if(owner.Get("exporting").AsBool()||Get(view,"dynamic",false).AsBool())continue;int frames=Get(view,"frames_left",0).AsInt32();if(frames<=0)continue;view["frames_left"]=frames-1;if(frames==1)set_layer_update_mode(view,(int)SubViewport.UpdateMode.Disabled);}
    }
}
