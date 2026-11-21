using Godot;
using System;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class EnvironmentWaterRender : RefCounted
{
    private readonly TerrainWaterfallRender _spray=new();
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    public void sync(Node3D node,Resource terrain)
    {
        var visual=node.GetNodeOrNull<MeshInstance3D>("Water");var source=terrain.Get("hydrology").As<Resource>();
        if(source==null||!terrain.Call("water_valid").AsBool()||!source.Get("enabled").AsBool()){visual?.Hide();return;}
        var data=Get(terrain.Get("water_data").AsGodotDictionary(),"mesh",new Settings()).AsGodotDictionary();
        if(Get(data,"vertices",Array.Empty<Vector3>()).AsVector3Array().Length==0){visual?.Hide();return;}
        if(visual==null){visual=new MeshInstance3D {Name="Water",CastShadow=GeometryInstance3D.ShadowCastingSetting.Off};visual.SetMeta("kiwi_physics_excluded",true);visual.SetMeta("terrain_water",true);node.AddChild(visual);}visual.Show();
        long key=terrain.Get("water_key").AsInt64();
        if(visual.GetMeta("water_key",-1).AsInt64()!=key)
        {
            using var arrays=new GArray();arrays.Resize((int)Mesh.ArrayType.Max);
            arrays[(int)Mesh.ArrayType.Vertex]=data["vertices"];arrays[(int)Mesh.ArrayType.Normal]=data["normals"];arrays[(int)Mesh.ArrayType.TexUV]=data["uv"];arrays[(int)Mesh.ArrayType.TexUV2]=data["uv2"];arrays[(int)Mesh.ArrayType.Color]=data["colors"];arrays[(int)Mesh.ArrayType.Index]=data["indices"];
            using var mesh=new ArrayMesh();mesh.AddSurfaceFromArrays(Mesh.PrimitiveType.Triangles,arrays);visual.Mesh=mesh;visual.SetMeta("water_key",key);
        }
        var material=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/environment_assets.gd").Call("material",source.Get("material_asset")).As<Material>();
        if(material==null)
        {
            var shaderMaterial=visual.MaterialOverride as ShaderMaterial;
            if(shaderMaterial==null||!shaderMaterial.GetMeta("terrain_water",false).AsBool()){shaderMaterial=new ShaderMaterial {Shader=GD.Load<Shader>("res://scripts/actors/physics/fluid/fluid.gdshader")};shaderMaterial.SetMeta("terrain_water",true);shaderMaterial.SetMeta("kiwi_time_uniform","liquid_time");}
            foreach(string name in new[]{"wave_strength","wave_scale","wave_direction","flow_speed","roughness","foam_color","foam_amount"})shaderMaterial.SetShaderParameter(name,source.Get(name));
            shaderMaterial.SetShaderParameter("terrain_surface",true);shaderMaterial.SetShaderParameter("liquid_color",source.Get("water_color"));material=shaderMaterial;
        }
        visual.MaterialOverride=material;visual.CustomAabb=visual.Mesh.GetAabb().Grow((float)(Math.Abs(source.Get("wave_strength").AsDouble())+.01));double distance=terrain.Get("render_distance").AsDouble();visual.VisibilityRangeEnd=(float)Math.Max(0,distance);visual.VisibilityRangeEndMargin=(float)(distance*.15);_spray.sync(visual,terrain);
    }
}
