using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
public partial class PointActorOperations:RefCounted
{
    private readonly ModelSourceLink _links=new();private readonly ActorAnimationOperations _animation=new();
    public void ready(Node3D owner){var anchor=new Node3D{Name="ParentingAnchor"};owner.AddChild(anchor);owner.Set("parenting_anchor",anchor);var actor=owner.Get("actor").As<Resource>();if(_links.register_actor(actor,owner)){owner.AddToGroup("model_instance_runtimes");owner.CallDeferred("refresh_model_binding",actor.Get("values").AsGodotDictionary().GetValueOrDefault("model_component_source","").AsString());}}
    public void refresh_model_binding(Node3D owner,string path){var actor=owner.Get("actor").As<Resource>();if(_links.refresh(actor,path))evaluate_transform(owner,_animation.sampled_values(actor,actor.Get("animation_time").AsDouble()));}
    public void set_active(Node3D owner,bool active)=>owner.Get("transform_node").As<Node3D>().Visible=active;
    public Node parenting_node(Node3D owner)=>owner.Get("parenting_anchor").As<Node3D>()??owner;
    public void evaluate_transform(Node3D owner,Settings values){var node=owner.Get("transform_node").As<Node3D>();var anchor=owner.Get("parenting_anchor").As<Node3D>();var position=values.GetValueOrDefault("position",Vector3.Zero).AsVector3();var rotation=values.GetValueOrDefault("rotation",Vector3.Zero).AsVector3();var scale=values.GetValueOrDefault("scale",Vector3.One).AsVector3();node.Position=position;node.RotationDegrees=rotation;node.Scale=scale;anchor.Position=position;anchor.RotationDegrees=rotation;anchor.Scale=scale;if(values.TryGetValue("model_basis_residual",out var residual)){var basis=Basis.FromEuler(node.Rotation)*Basis.FromScale(scale)*residual.AsBasis();node.Basis=basis;anchor.Basis=basis;}}
    public Transform3D remote_transform(Node3D owner)=>owner.Get("transform_node").As<Node3D>().GlobalTransform;
    public void apply_remote_transform(Node3D owner,Transform3D source,bool position,bool rotation,bool scale){var node=owner.Get("transform_node").As<Node3D>();var result=node.GlobalTransform;if(position)result.Origin=source.Origin;var orientation=rotation?source.Basis.GetRotationQuaternion():result.Basis.GetRotationQuaternion();var size=scale?source.Basis.Scale:result.Basis.Scale;result.Basis=new Basis(orientation)*Basis.FromScale(size);node.GlobalTransform=result;owner.Get("parenting_anchor").As<Node3D>().GlobalTransform=result;}
}
public partial class VideoActorOperations:RefCounted
{
    public void ready(Node3D owner){var mesh=new MeshInstance3D{Layers=1,Mesh=new QuadMesh()};var material=new StandardMaterial3D{ShadingMode=BaseMaterial3D.ShadingModeEnum.Unshaded,CullMode=BaseMaterial3D.CullModeEnum.Disabled};mesh.MaterialOverride=material;owner.Set("mesh",mesh);owner.Set("material",material);owner.AddChild(mesh);var anchor=new Node3D();owner.AddChild(anchor);owner.Set("anchor",anchor);}
    public void process(Node3D owner,double delta){var mesh=owner.Get("mesh").As<MeshInstance3D>();var values=owner.Get("_values").AsGodotDictionary();if(mesh!=null&&mesh.Visible&&values.Count>0)evaluate(owner,owner.Get("_time").AsDouble(),values);}
    public Node parenting_node(Node3D owner)=>owner.Get("anchor").As<Node3D>()??owner;
    public void set_active(Node3D owner,bool value){var mesh=owner.Get("mesh").As<MeshInstance3D>();if(mesh!=null)mesh.Visible=value;}
    public void evaluate_transform(Node3D owner,Settings values){var mesh=owner.Get("mesh").As<MeshInstance3D>();if(mesh==null)return;foreach(var node in new Node3D[]{mesh,owner.Get("anchor").As<Node3D>()}){node.Position=values.GetValueOrDefault("position",Vector3.Zero).AsVector3();node.RotationDegrees=values.GetValueOrDefault("rotation",Vector3.Zero).AsVector3();node.Scale=values.GetValueOrDefault("scale",Vector3.One).AsVector3();}}
    public void evaluate(Node3D owner,double time,Settings values){owner.Set("_time",time);owner.Set("_values",values);var mesh=owner.Get("mesh").As<MeshInstance3D>();if(mesh==null)return;string path=values.GetValueOrDefault("video","").AsString();var material=owner.Get("material").As<StandardMaterial3D>();if(path!=owner.Get("_path").AsString()){owner.Set("_path",path);material.AlbedoTexture=null;}var video=GD.Load<CSharpScript>("res://scripts/actors/core/ActorVideo.cs");var source=video.Call("info",path).AsGodotDictionary();if(source.Count==0){material.AlbedoTexture=null;return;}int width=source["width"].AsInt32(),height=source["height"].AsInt32();((QuadMesh)mesh.Mesh).Size=new Vector2(width,height)/Math.Max(width,height);var texture=video.Call("frame",path,time,true).As<Texture2D>();if(texture!=null){material.AlbedoTexture=texture;owner.Set("_last_texture",texture);}}
}
