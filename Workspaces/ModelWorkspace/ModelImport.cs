using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class ModelImport : RefCounted
{
    private readonly ModelMeshOperations _meshes=new();
    private static bool Document(Resource resource)
    {var script=resource.GetScript().As<Script>();while(script!=null){if((script.ResourcePath=="res://Workspaces/ModelWorkspace/model_document.gd"||script.ResourcePath=="res://Workspaces/ModelWorkspace/KiwiModelDocument.cs"))return true;script=script.GetBaseScript();}return false;}
    private static Resource EmptyDocument()=>new KiwiModelDocument();
    public Resource load_document(Variant source)
    {
        Resource? resource=source.VariantType==Variant.Type.Object?source.AsGodotObject() as Resource:null;string path=source.VariantType==Variant.Type.String?source.AsString():"";
        if(resource!=null&&Document(resource))return resource.Call("validate").AsStringArray().Length==0?resource.Call("snapshot").As<Resource>():EmptyDocument();
        if(resource==null&&ResourceLoader.Exists(path))resource=ResourceLoader.Load(path,"",ResourceLoader.CacheMode.Ignore);
        if(resource!=null&&Document(resource))return resource.Call("validate").AsStringArray().Length==0?resource.Call("snapshot").As<Resource>():EmptyDocument();
        var document=EmptyDocument();if(resource is Mesh mesh){_add_mesh(document,mesh,Transform3D.Identity,"Imported mesh");return document;}
        Node? scene=null;
        if(resource is PackedScene packed)scene=packed.Instantiate();
        else if(path.GetExtension().ToLowerInvariant() is "glb" or "gltf")
        {using var gltf=new GltfDocument();using var state=new GltfState();if(gltf.AppendFromFile(path,state)==Error.Ok)scene=gltf.GenerateScene(state);}
        if(scene==null)return document;
        try
        {
            var bindings=new Dictionary<Node,Resource>();Walk(document,scene,Transform3D.Identity,"",bindings);
            foreach(var pair in bindings)
            {
                if(pair.Key is not MeshInstance3D visual||visual.Mesh==null)continue;var skeleton=visual.GetNodeOrNull<Skeleton3D>(visual.Skeleton);
                if(skeleton==null||!bindings.TryGetValue(skeleton,out var armature))continue;
                pair.Value.Set("skin",visual.Skin!=null?visual.Skin.Duplicate(true):skeleton.CreateSkinFromRestTransforms());pair.Value.Set("skin_mesh",visual.Mesh.Duplicate(true));pair.Value.Set("skeleton_id",armature.Get("id"));
            }
        }
        finally{scene.Free();}
        return document;
    }
    private void Walk(Resource document,Node node,Transform3D accumulated,string parentId,Dictionary<Node,Resource> bindings)
    {
        Transform3D transform=accumulated*(node is Node3D spatial?spatial.Transform:Transform3D.Identity);string nextParent=parentId;
        if(node is Node3D spatialNode)
        {
            Resource item;
            if(node is MeshInstance3D visual&&visual.Mesh!=null)
            {
                item=_add_mesh(document,visual.Mesh,transform,node.Name.ToString());var materials=item.Get("surface_materials").AsGodotArray();
                for(int surface=0;surface<visual.Mesh.GetSurfaceCount();surface++){var material=visual.GetActiveMaterial(surface);if(material!=null)materials[surface]=material;}
            }
            else
            {item=new KiwiModelComponent();item.Set("id",Guid.NewGuid().ToString("N"));item.Set("title",node.Name.ToString());item.Set("transform",transform);document.Get("components").AsGodotArray().Add(item);}
            item.Set("parent_id",parentId);item.Set("visible",spatialNode.Visible);bindings[node]=item;
            if(node is Skeleton3D skeleton)
            {
                item.Set("is_skeleton",true);var bones=item.Get("bones").AsGodotArray();
                for(int i=0;i<skeleton.GetBoneCount();i++)bones.Add(new Settings{["name"]=skeleton.GetBoneName(i),["parent"]=skeleton.GetBoneParent(i),["rest"]=skeleton.GetBoneRest(i),["position"]=skeleton.GetBonePosePosition(i),["rotation"]=skeleton.GetBonePoseRotation(i).GetEuler()*(180/Mathf.Pi),["scale"]=skeleton.GetBonePoseScale(i)});
            }
            nextParent=item.Get("id").AsString();transform=Transform3D.Identity;
        }
        foreach(Node child in node.GetChildren())Walk(document,child,transform,nextParent,bindings);
    }
    public Resource _add_mesh(Resource document,Mesh mesh,Transform3D transform,string title)
    {
        var item=new KiwiModelComponent();item.Set("id",Guid.NewGuid().ToString("N"));item.Set("title",title);var topology=_meshes.from_mesh(mesh);item.Set("mesh",topology);item.Set("transform",transform);item.Set("geometry_source",mesh.Duplicate(true));item.Set("geometry_source_hash",GD.Hash(new GArray{topology.Get("vertices"),topology.Get("faces"),topology.Get("uv"),topology.Get("materials")}));
        var materials=item.Get("surface_materials").AsGodotArray();for(int surface=0;surface<mesh.GetSurfaceCount();surface++)materials.Add(mesh.SurfaceGetMaterial(surface));document.Get("components").AsGodotArray().Add(item);return item;
    }
}
