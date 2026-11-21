using Godot;
using System;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class TerrainWaterfallRender : RefCounted
{
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    public void sync(MeshInstance3D water,Resource terrain)
    {
        var source=terrain.Get("hydrology").As<Resource>();var data=terrain.Get("water_data").AsGodotDictionary();var falls=Get(data,"waterfalls",new GArray()).AsGodotArray();var visual=water.GetNodeOrNull<MultiMeshInstance3D>("Spray");
        if(!source.Get("waterfall_spray").AsBool()||falls.Count==0){visual?.Hide();return;}
        if(visual==null){visual=new MultiMeshInstance3D {Name="Spray",CastShadow=GeometryInstance3D.ShadowCastingSetting.Off};visual.SetMeta("kiwi_physics_excluded",true);water.AddChild(visual);}
        visual.Show();long key=unchecked((uint)GD.Hash(new GArray {falls,terrain.Get("seed"),source.Get("spray_per_fall"),source.Get("spray_lifetime"),source.Get("spray_size")}));
        if(visual.GetMeta("spray_key",-1).AsInt64()!=key)
        {
            int perFall=Math.Clamp(source.Get("spray_per_fall").AsInt32(),1,128),count=Math.Min(2048,falls.Count*perFall);
            using var mesh=new MultiMesh {TransformFormat=MultiMesh.TransformFormatEnum.Transform3D,UseCustomData=true};using var quad=new QuadMesh();mesh.Mesh=quad;mesh.InstanceCount=count;
            using var rng=new RandomNumberGenerator {Seed=unchecked((ulong)terrain.Get("seed").AsInt64())};var bounds=new Aabb();bool first=true;
            for(int index=0;index<count;index++)
            {
                var fall=falls[index/perFall].AsGodotDictionary();var direction=Get(fall,"flow",Vector2.Zero).AsVector2();var side=new Vector3(direction.Y,0,-direction.X);var center=fall["to"].AsVector3();
                center+=side*rng.RandfRange(-.5f,.5f)*fall["width"].AsSingle();
                var velocity=side*rng.RandfRange(-.8f,.8f)+new Vector3(direction.X,(float)(rng.RandfRange(.5f,1.5f)*Math.Sqrt(Math.Max(.01,fall["drop"].AsDouble()))),direction.Y)*.55f;
                float lifetime=(float)Math.Max(.01,source.Get("spray_lifetime").AsDouble());var end=center+velocity*lifetime+new Vector3(0,-2,0)*lifetime*lifetime;
                mesh.SetInstanceTransform(index,new Transform3D(Basis.Identity,center));mesh.SetInstanceCustomData(index,new Color(velocity.X,velocity.Y,velocity.Z,rng.Randf()));
                var box=new Aabb(center,Vector3.Zero).Expand(end).Grow((float)(Math.Abs(source.Get("spray_size").AsDouble())+velocity.Y*velocity.Y/8));bounds=first?box:bounds.Merge(box);first=false;
            }
            mesh.CustomAabb=bounds;visual.Multimesh=mesh;visual.SetMeta("spray_key",key);
        }
        var material=visual.MaterialOverride as ShaderMaterial;
        if(material==null){material=new ShaderMaterial {Shader=GD.Load<Shader>("res://Workspaces/EnvironmentWorkspace/terrain/terrain_spray.gdshader")};material.SetMeta("kiwi_time_uniform","liquid_time");material.SetMeta("terrain_water",true);visual.MaterialOverride=material;}
        material.SetShaderParameter("lifetime",Math.Max(.01,source.Get("spray_lifetime").AsDouble()));material.SetShaderParameter("size",Math.Max(.001,source.Get("spray_size").AsDouble()));material.SetShaderParameter("foam_color",source.Get("foam_color"));
    }
}
