using Godot;
using System;
using System.Collections.Generic;

public partial class ModelDocumentOperations
{
    private readonly RigSkeletonRuntime _skeleton=new();
    private SurfaceGrowthGeometry? _growthGenerator;
    public void prepare_growth(Resource document)
    {
        foreach(var item in Components(document))
        {
            var growth=item.Get("growth").As<Resource>();if(growth==null)continue;_growthGenerator??=new SurfaceGrowthGeometry();
            string error=_growthGenerator.prepare(document,item,component(document,Text(growth,"source_id")));if(error.Length>0)growth.Set("error",error);
        }
    }
    private static bool GrowthInstance(Node node)
    {
        var script=node.GetScript().As<Script>();while(script!=null){if(script.ResourcePath=="res://Workspaces/ModelWorkspace/growth/surface_growth_instance.gd")return true;script=script.GetBaseScript();}return false;
    }
    public Node3D instantiate_model(Resource document)
    {
        prepare_growth(document);var root=new RigModelRuntime{Name="KiwiModel"};var nodes=new Dictionary<string,Node3D>();var materialScope=new Godot.Collections.Dictionary();var items=Components(document);
        foreach(var item in items)
        {
            Node3D node=item.Get("is_skeleton").AsBool()?_skeleton.create_skeleton(item.Get("bones").AsGodotArray()):new Node3D();node.Name=Text(item,"title").ValidateNodeName();node.Transform=item.Get("transform").AsTransform3D();node.Visible=item.Get("visible").AsBool();node.SetMeta("kiwi_component_id",item.Get("id"));node.SetMeta("kiwi_component_pivot",item.Get("pivot"));root.AddChild(node);nodes[Text(item,"id")]=node;
            var growth=item.Get("growth").As<Resource>();var mesh=item.Get("mesh").As<Resource>();
            if(growth!=null){var visual=GD.Load<GDScript>("res://Workspaces/ModelWorkspace/growth/surface_growth_instance.gd").New().As<MeshInstance3D>();visual.Call("configure",item);node.AddChild(visual);}
            else if(mesh!=null&&mesh.Call("validate").AsStringArray().Length==0)
            {
                var binding=item.Get("binding").As<Resource>();var visual=new MeshInstance3D{Mesh=item.Get("skin_mesh").As<Mesh>()??(binding!=null?binding.Get("source_mesh").As<Mesh>():_components.render_mesh(item,materialScope)),Skin=item.Get("skin").As<Skin>(),Layers=1};node.AddChild(visual);
            }
        }
        foreach(var item in items)
        {
            string id=Text(item,"id"),parentId=Text(item,"parent_id");if(nodes.TryGetValue(parentId,out var parent)&&parentId!=id&&!nodes[id].IsAncestorOf(parent)){var node=nodes[id];root.RemoveChild(node);parent.AddChild(node);}
        }
        foreach(var item in items)
        {
            string id=Text(item,"id"),skeletonId=Text(item,"skeleton_id");if(skeletonId.Length==0||!nodes.TryGetValue(skeletonId,out var skeleton))continue;
            if(item.Get("growth").As<Resource>()!=null){foreach(Node child in nodes[id].GetChildren())if(GrowthInstance(child))child.Set("growth_skeleton",skeleton);continue;}
            var binding=item.Get("binding").As<Resource>();
            if(binding!=null&&Text(binding,"rigid_bone_id").Length>0)
            {
                var armature=component(document,skeletonId);if(armature==null)continue;var bones=armature.Get("bones").AsGodotArray();
                for(int i=0;i<bones.Count;i++)if(bones[i].AsGodotDictionary()["id"].AsString()==Text(binding,"rigid_bone_id"))root.attachments.Add(new Godot.Collections.Dictionary{["target"]=nodes[id],["skeleton"]=skeleton,["bone"]=i,["offset"]=binding.Get("attachment_offset")});continue;
            }
            foreach(Node child in nodes[id].GetChildren())if(child is MeshInstance3D visual)
            {visual.Skeleton=visual.GetPathTo(skeleton);if(binding!=null&&Text(binding,"rigid_bone_id").Length==0)visual.Transform=world_transform(document,item).AffineInverse()*world_transform(document,component(document,skeletonId)!);}
        }
        return root;
    }
}
