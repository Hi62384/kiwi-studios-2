using Godot;
using System;
using Settings=Godot.Collections.Dictionary;

public partial class ModelDocumentOperations
{
    private readonly GrowthActorOperations _growthActors=new();
    private static bool ScriptType(GodotObject value,string path)
    {var script=value.GetScript().As<Script>();while(script!=null){if(script.ResourcePath==path||script.ResourcePath==LegacyResourceLoader.NativeScriptPath(path))return true;script=script.GetBaseScript();}return false;}
    public Resource actor_scene(Resource document,RefCounted registry,string sourcePath)
    {
        prepare_growth(document);var scene=new ActorSceneData();if(validate(document).Length>0)return scene;
        string extension=sourcePath.GetExtension().ToLowerInvariant();var saved=extension is "tres" or "res"?ResourceLoader.Load(sourcePath):null;bool native=saved!=null&&ScriptType(saved,"res://Workspaces/ModelWorkspace/model_document.gd");
        var actors=scene.Get("actors").AsGodotArray();var clips=scene.Get("clips").AsGodotArray();var visible=hierarchy_state(document,new Godot.Collections.Array<string>())["visible"].AsGodotDictionary();
        foreach(var item in Components(document))
        {
            bool skeleton=item.Get("is_skeleton").AsBool();var mesh=item.Get("mesh").As<Resource>();var definition=registry.Call("get_definition",new StringName(skeleton?"skeleton_rig":mesh!=null?"basic_mesh":"point_3d")).As<RefCounted>();if(definition==null)return new ActorSceneData();
            var actor=definition.Call("create_actor").As<Resource>();actor.Set("id",item.Get("id"));actor.Set("parent_id",item.Get("parent_id"));actor.Set("display_name",item.Get("title"));var values=actor.Get("values").AsGodotDictionary();values.Merge(transform_values(item.Get("transform").AsTransform3D()),true);var structural=item.Get("structural").AsGodotDictionary();values.Merge(structural.Duplicate(true),true);
            void Set(string key,Variant value)=>values[new StringName(key)]=value;
            Set("model_component_source",sourcePath);Set("model_component_id",item.Get("id"));Set("model_component_bind_transform",item.Get("transform"));Set("model_component_bind_parent",item.Get("parent_id"));Set("model_component_bind_structure",structural.Duplicate(true));actor.Set("show_timeline_children",true);actor.Set("link_timeline_children",true);
            var bones=item.Get("bones").AsGodotArray();
            if(skeleton)
            {
                Set("rig_bones",bones.Duplicate(true));var poses=new Settings();for(int i=0;i<bones.Count;i++){var bone=bones[i].AsGodotDictionary();poses[i.ToString()]=new Settings{["position"]=bone["position"],["rotation"]=bone["rotation"],["scale"]=bone["scale"]};}Set("bone_poses",poses);
            }
            if(mesh!=null)
            {
                Set("mesh_path",sourcePath);Set("model_component_source",sourcePath);Set("model_component_id",item.Get("id"));string skeletonId=Text(item,"skeleton_id");
                if(skeletonId.Length>0)
                {
                    Set("model_skeleton_actor",skeletonId);var armature=component(document,skeletonId);if(armature!=null){Set("model_rig_bind_signature",_rig.bind_signature(armature.Get("bones").AsGodotArray()));Set("model_component_data",_components.copy_component(item,false));}
                }
                var binding=item.Get("binding").As<Resource>();
                if(binding!=null)
                {
                    bool rigid=Text(binding,"rigid_bone_id").Length>0;Set("model_skin_in_rig_space",!rigid);
                    if(rigid)
                    {
                        var armature=component(document,skeletonId);if(armature!=null){var rigBones=armature.Get("bones").AsGodotArray();for(int i=0;i<rigBones.Count;i++)if(rigBones[i].AsGodotDictionary()["id"].AsString()==Text(binding,"rigid_bone_id")){Set("model_rigid_bone",i);Set("model_rigid_rest_inverse",_rig.globals(rigBones,false)[i].AffineInverse());}}
                    }
                }
                var growth=item.Get("growth").As<Resource>();if(!native||growth!=null)Set("model_component_data",_components.copy_component(item,false));if(growth!=null)_growthActors.initialize(actor,growth);
            }
            if(!visible[Text(item,"id")].AsBool())Set("model_component_hidden",true);actors.Add(actor);var clip=ActorClip.create(actor,0.0,5.0);clip.Set("layer",clips.Count);clips.Add(clip);
        }
        return scene;
    }
}
