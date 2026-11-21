using Godot;
using System;
using Settings=Godot.Collections.Dictionary;

public partial class ModelComponentOperations : RefCounted
{
    private readonly RigBindingWeights _bindings=new();
    private readonly ModelMeshOperations _mesh=new();
    private readonly ModelModifiers _modifiers=new();
    private readonly ModelNaturalRender _natural=new();
    public Resource copy_component(Resource source,bool newIdentity)
    {
        var result=new KiwiModelComponent();
        result.Set("id",newIdentity?Guid.NewGuid().ToString("N"):source.Get("id"));
        foreach(string property in new[]{"title","parent_id","transform","pivot","visible","locked","generator","is_skeleton","skin","skin_mesh","skeleton_id","geometry_source","geometry_source_hash"}) result.Set(property,source.Get(property));
        var mesh=source.Get("mesh").As<Resource>();result.Set("mesh",mesh==null?default(Variant):Variant.From(_mesh.copy_mesh(mesh)));
        result.Set("parameters",source.Get("parameters").AsGodotDictionary().Duplicate(true));result.Set("modifiers",source.Get("modifiers").AsGodotArray().Duplicate(true));
        result.Set("surface_materials",source.Get("surface_materials").AsGodotArray().Duplicate(false));result.Set("bones",source.Get("bones").AsGodotArray().Duplicate(true));
        var binding=source.Get("binding").As<Resource>();result.Set("binding",binding==null?default(Variant):Variant.From(_bindings.copy_binding(binding)));
        result.Set("structural",source.Get("structural").AsGodotDictionary().Duplicate(true));var growth=source.Get("growth").As<Resource>();result.Set("growth",growth==null?default:growth.Call("copy_data"));return result;
    }
    public ArrayMesh render_mesh(Resource component,Variant materialScope)
    {
        var evaluated=_modifiers.evaluate(component);
        var result=_mesh.render_mesh(evaluated,component.Get("surface_materials").AsGodotArray<Material>());
        GDScript? assets=null;Settings? scope=materialScope.VariantType==Variant.Type.Dictionary?materialScope.AsGodotDictionary():null;
        for(int surface=0;surface<result.GetSurfaceCount();surface++)
        {
            var material=result.SurfaceGetMaterial(surface);if(material is not ShaderMaterial) continue;
            assets??=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/environment_assets.gd");
            if(scope!=null)
            {
                ulong identity=material.GetInstanceId();if(!scope.TryGetValue(identity,out var scoped)) {scoped=assets.Call("timeline_material",material,true);scope[identity]=scoped;}
                result.SurfaceSetMaterial(surface,scoped.As<Material>());
            }
            else result.SurfaceSetMaterial(surface,assets.Call("timeline_material",material,false).As<Material>());
        }
        var parameters=component.Get("parameters").AsGodotDictionary();
        if(parameters.ContainsKey("architecture_type"))
        {
            result.SetMeta("kiwi_editable_topology",evaluated);
            if(!parameters.TryGetValue("_architecture_manual",out var manual)||!manual.AsBool()) result.SetMeta("kiwi_compound_points",GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/architecture/building_collision.gd").Call("parts",evaluated));
        }
        return _natural.prepare(result,component);
    }
}
