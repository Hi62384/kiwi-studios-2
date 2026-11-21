using Godot;
using System;
using System.Collections.Generic;
using GArray=Godot.Collections.Array;
using Settings=Godot.Collections.Dictionary;
public partial class DebrisDefinitionOperations:RefCounted
{
    private readonly ActorDefinitionOperations _definitions=new();
    private readonly ActorPropertyOperations _properties=new();
    private readonly DestructionDefinitionOperations _fields=new();
    private readonly ModelDocumentOperations _documents=new();
    private readonly ModelMeshOperations _meshes=new();
    private readonly ActorRuntimeOperations _runtime=new();
    private GArray Rows(string name)=>GD.Load<GDScript>("res://scripts/actors/physics/destruction/debris_definition.gd").GetScriptConstantMap()[name].AsGodotArray();
    public void extend_actor(Resource definition)
    {
        if(definition.Get("type_id").AsString() is not ("basic_shape" or "basic_mesh")||_definitions.find_property(definition,new StringName("debris_enabled"))!=null)return;
        foreach(var value in Rows("FIELD_ROWS")){var row=value.AsGodotArray();var hints=row[3].AsGodotDictionary();_fields.add(definition,row[0].AsString(),row[1].AsString(),row[2],"Debris & Effects",hints,!hints.GetValueOrDefault("no_keyframes",false).AsBool());}
        var property=_properties.create(new StringName("debris_vfx_preset"),"Custom VFX preset",default,false);property.Set("object_type",new StringName("debris_vfx"));property.Get("options").AsGodotDictionary()["group"]="Debris & Effects";definition.Get("properties").AsGodotArray().Add(property);
    }
    public Resource preset_definition()
    {
        var definition=new ActorObjectDefinition();definition.Set("type_id",new StringName("debris_vfx"));definition.Set("display_name","Destruction VFX Preset");
        foreach(var value in Rows("PRESET_ROWS")){var row=value.AsGodotArray();var property=_properties.create(new StringName(row[0].AsString()),row[1].AsString(),row[2],true);property.Get("options").AsGodotDictionary().Merge(row[3].AsGodotDictionary());definition.Get("properties").AsGodotArray().Add(property);}return definition;
    }
    public void copy_fragments(Node editor,Resource actor)
    {
        var physics=editor.Get("physics").AsGodotObject();var state=physics.Get("display_states").AsGodotDictionary().GetValueOrDefault(actor.Get("id"),new Settings()).AsGodotDictionary();var fragments=state.GetValueOrDefault("destruction_fragments",new GArray()).AsGodotArray();var scene=new ActorSceneData();var registry=editor.Get("registry").AsGodotObject();var nodes=physics.Get("destruction").AsGodotObject().Get("nodes").AsGodotDictionary();
        for(int i=0;i<fragments.Count;i++)
        {
            var fragment=fragments[i].AsGodotDictionary();var data=_definitions.create_actor(registry.Call("get_definition",new StringName("basic_mesh")).As<Resource>(),new Settings());data.Set("display_name",actor.Get("display_name").AsString()+" debris "+(i+1));var values=data.Get("values").AsGodotDictionary();values.Merge(_documents.transform_values(fragment["pose"].AsTransform3D()),true);var materials=new Godot.Collections.Array<Material>();
            if(nodes.TryGetValue(actor.Get("id"),out var actorNodes)&&i<actorNodes.AsGodotArray().Count){var node=actorNodes.AsGodotArray()[i].As<MeshInstance3D>();if(GodotObject.IsInstanceValid(node)&&node.Mesh!=null)for(int surface=0;surface<node.Mesh.GetSurfaceCount();surface++)materials.Add(node.GetActiveMaterial(surface));}
            values["mesh_path"]=_meshes.render_mesh(fragment["mesh"].As<Resource>(),materials);values["physics"]=new Settings{["enabled"]=false,["mass"]=fragment["mass"],["velocity"]=fragment["v"],["angular_velocity"]=fragment["w"].AsVector3()*(180f/Mathf.Pi)};scene.Get("actors").AsGodotArray().Add(data);var clip=_runtime.create_clip(data,0,5);clip.Set("layer",i);scene.Get("clips").AsGodotArray().Add(clip);
        }
        if(fragments.Count>0){var model=editor.Get("model").AsGodotObject();model.Call("instantiate_scene",scene,registry.Call("get_definition",new StringName("point_3d")),editor.Get("canvas").AsGodotObject().Get("playhead"),model.Get("selected_layer"),"Debris snapshot","Copy debris as editable actors");}
    }
}
