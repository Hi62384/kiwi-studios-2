using Godot;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class RigViewportSync : RefCounted
{
    private readonly RigMath _math=new();
    private readonly RigBindingGeometry _geometry=new();
    private readonly StandardMaterial3D _heatMaterial=new(){ShadingMode=BaseMaterial3D.ShadingModeEnum.Unshaded,VertexColorUseAsAlbedo=true};
    public void sync(Control canvas,RigEditor editor,bool compareRest,Settings nodes,Settings signatures,Settings heatSignatures,Settings geometryCache)
    {
        var document=canvas.Get("session").As<RefCounted>().Get("document").As<Resource>(); var components=document.Get("components").AsGodotArray(); var live=new Settings();
        foreach(Variant value in components)
        {
            var armature=value.As<Resource>(); if(!armature.Get("is_skeleton").AsBool()) continue;
            _math.ensure(armature); string id=armature.Get("id").AsString(); live[id]=true; var bones=armature.Get("bones").AsGodotArray(); var hashInput=new GArray();
            foreach(Variant boneValue in bones) {var bone=boneValue.AsGodotDictionary();hashInput.Add(new GArray{bone["name"],bone["parent"],bone["rest"]});}
            long restHash=GD.Hash(hashInput);
            if(!nodes.ContainsKey(id)||!signatures.TryGetValue(id,out var signature)||signature.AsInt64()!=restHash)
            {
                if(nodes.TryGetValue(id,out var old)) old.As<Skeleton3D>().Free(); var skeleton=new RigSkeletonRuntime().create_skeleton(bones);
                canvas.Get("world").As<Node3D>().AddChild(skeleton); nodes[id]=skeleton;signatures[id]=restHash;
            }
            var target=nodes[id].As<Skeleton3D>(); target.Transform=document.Call("world_transform",armature).AsTransform3D();
            bool restMode=compareRest||(editor.enabled&&editor.rig_id==id&&editor.mode is "Edit" or "Draw" or "Envelope");
            for(int i=0;i<bones.Count;i++)
            {
                var bone=bones[i].AsGodotDictionary();var rest=bone["rest"].AsTransform3D();
                target.SetBonePosePosition(i,restMode?rest.Origin:bone["position"].AsVector3());
                target.SetBonePoseRotation(i,restMode?rest.Basis.GetRotationQuaternion():Quaternion.FromEuler(bone["rotation"].AsVector3()*(Mathf.Pi/180)));
                target.SetBonePoseScale(i,restMode?rest.Basis.Scale:bone["scale"].AsVector3());
            }
        }
        foreach(Variant id in nodes.Keys.ToArray()) if(!live.ContainsKey(id)) {nodes[id].As<Skeleton3D>().Free();nodes.Remove(id);signatures.Remove(id);}
        var visuals=canvas.Get("visuals").AsGodotDictionary();
        foreach(Variant value in components)
        {
            var item=value.As<Resource>();string id=item.Get("id").AsString(),rigId=item.Get("skeleton_id").AsString(); if(!visuals.TryGetValue(id,out var found)) continue;var visual=found.As<MeshInstance3D>();
            if(visual.GetScript().As<Script>()?.ResourcePath=="res://Workspaces/ModelWorkspace/growth/surface_growth_instance.gd")
            {visual.Set("growth_skeleton",nodes.TryGetValue(rigId,out var growthSkeleton)?growthSkeleton:default);visual.Call("update_growth");continue;}
            if(!nodes.TryGetValue(rigId,out var skeletonValue)) {visual.Skin=null;visual.Skeleton=new NodePath();visual.MaterialOverride=null;heatSignatures.Remove(id);continue;}
            var armature=document.Call("component",rigId).As<Resource>(); var skeleton=skeletonValue.As<Skeleton3D>();var binding=item.Get("binding").As<Resource>();
            if(binding==null) {visual.MaterialOverride=null;heatSignatures.Remove(id);if(item.Get("skin_mesh").As<Mesh>()!=null){visual.Skin=item.Get("skin").As<Skin>();visual.Skeleton=visual.GetPathTo(skeleton);}continue;}
            string rigidId=binding.Get("rigid_bone_id").AsString();var bones=armature.Get("bones").AsGodotArray();
            if(rigidId.Length>0)
            {
                visual.Skin=null;visual.Skeleton=new NodePath();visual.MaterialOverride=null;heatSignatures.Remove(id);
                for(int i=0;i<bones.Count;i++) if(bones[i].AsGodotDictionary()["id"].AsString()==rigidId) visual.Transform=skeleton.Transform*skeleton.GetBoneGlobalPose(i)*binding.Get("attachment_offset").AsTransform3D();
                continue;
            }
            visual.Transform=skeleton.Transform;visual.Skin=item.Get("skin").As<Skin>();visual.Skeleton=visual.GetPathTo(skeleton);
            bool heat=editor.enabled&&editor.mode=="Weight"&&rigId==editor.rig_id;
            int bone=heat&&editor.selected_bone>=0&&editor.selected_bone<bones.Count?System.Array.IndexOf(binding.Get("bone_ids").AsStringArray(),bones[editor.selected_bone].AsGodotDictionary()["id"].AsString()):-1;
            long hash=GD.Hash(new GArray{item.Get("skin_mesh"),binding.Get("revision"),bone});
            if(!heatSignatures.TryGetValue(id,out var previous)||previous.AsInt64()!=hash) {visual.Mesh=heat?_geometry.render_mesh(binding,bone):item.Get("skin_mesh").As<Mesh>();heatSignatures[id]=hash;}
            visual.MaterialOverride=heat?_heatMaterial:null;
        }
        foreach(Variant id in geometryCache.Keys.ToArray()) if(!visuals.ContainsKey(id)) geometryCache.Remove(id);
    }
}
