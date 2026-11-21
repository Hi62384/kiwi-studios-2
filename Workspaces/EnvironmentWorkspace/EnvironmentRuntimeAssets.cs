using Godot;
using System;
using System.Globalization;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class EnvironmentRuntimeOperations
{
    public long native_asset_key(Resource item)
    {var mesh=item.Get("mesh").As<Resource>();return Hash(new GArray {mesh.Get("vertices"),mesh.Get("faces"),mesh.Get("uv"),mesh.Get("materials"),mesh.Get("smooth"),item.Get("modifiers"),item.Get("surface_materials")});}
    public void asset(Node3D owner,Resource item,Node3D node,Settings metadata)
    {
        string path=Get(metadata,"source", "").AsString(),id=item.Get("id").AsString();var loaded=new Settings {["parts"]=new GArray(),["error"]="",["key"]=0};var signatures=State(owner,"signatures");bool collision=Get(metadata,"collision",false).AsBool();
        if(path.Length>0)loaded=Assets().Call("load_parts",path).AsGodotDictionary();
        else if(item.Get("mesh").As<Resource>()!=null)
        {
            loaded["key"]=native_asset_key(item);if(Get(signatures,id,-1).AsInt64()==loaded["key"].AsInt64()){_collision.sync_asset_collision(node,collision);return;}
            loaded["parts"]=new GArray {new Settings {["mesh"]=item.Call("render_mesh",State(owner,"_material_scope")),["transform"]=Transform3D.Identity,["name"]=item.Get("title")}};
        }
        string error=loaded["error"].AsString();if(error.Length>0)Error(owner,error);if(Get(signatures,id,-1).AsInt64()==loaded["key"].AsInt64()){_collision.sync_asset_collision(node,collision);return;}signatures[id]=loaded["key"];foreach(var child in node.GetChildren())child.Free();
        foreach(var entry in loaded["parts"].AsGodotArray())
        {
            var part=entry.AsGodotDictionary();var visual=new MeshInstance3D {Name=part["name"].AsString().ValidateNodeName(),Mesh=part["mesh"].As<Mesh>(),Transform=part["transform"].AsTransform3D()};node.AddChild(visual);
            if(item.Get("parameters").AsGodotDictionary().ContainsKey("world_owner"))visual.Mesh=lod_mesh(visual.Mesh,State(owner,"_asset_lod_scope"));
            if(path.Length>0)
            {
                var scope=State(owner,"_material_scope");for(int surface=0;surface<visual.Mesh.GetSurfaceCount();surface++)
                {
                    if(visual.Mesh.SurfaceGetMaterial(surface) is not ShaderMaterial authored)continue;ulong identity=authored.GetInstanceId();if(!scope.TryGetValue(identity,out var material)){material=Assets().Call("timeline_material",authored,true);scope[identity]=material;}visual.SetSurfaceOverrideMaterial(surface,material.As<Material>());
                }
            }
        }
        _collision.sync_asset_collision(node,collision);_natural.time(node,owner.Get("preview_time").AsDouble(),new Settings());
    }
    public void world_render(Node3D runtime,Resource item,Node3D node)
    {
        var parameters=item.Get("parameters").AsGodotDictionary();string id=Get(parameters,"world_owner", "").AsString();var owner=Get(State(runtime,"component_index"),id).As<Resource>();if(owner==null)return;var source=Get(owner.Get("parameters").AsGodotDictionary(),"world_source");if(source.VariantType!=Variant.Type.Object||source.AsGodotObject() is not Resource settings)return;
        foreach(var child in node.GetChildren())if(child is GeometryInstance3D geometry&&child is not MultiMeshInstance3D){geometry.VisibilityRangeEnd=(float)Math.Max(0,settings.Get("render_distance").AsDouble());geometry.VisibilityRangeEndMargin=geometry.VisibilityRangeEnd*.1f;geometry.VisibilityRangeFadeMode=geometry.VisibilityRangeEnd>0?GeometryInstance3D.VisibilityRangeFadeModeEnum.Self:GeometryInstance3D.VisibilityRangeFadeModeEnum.Disabled;}
    }
    public Mesh lod_mesh(Mesh source,Settings cache)
    {
        if(source is not ArrayMesh mesh||mesh.GetSurfaceCount()==0)return source;ulong key=source.GetInstanceId();if(cache.TryGetValue(key,out var cached))return cached.As<Mesh>();int indices=0;
        for(int surface=0;surface<source.GetSurfaceCount();surface++){if(mesh.SurfaceGetPrimitiveType(surface)!=Mesh.PrimitiveType.Triangles)return source;int length=mesh.SurfaceGetArrayIndexLen(surface);indices+=length>0?length:mesh.SurfaceGetArrayLen(surface);}if(indices<768)return source;
        var result=_lod.prepare(mesh)??mesh;if(cache.Count>=256)cache.Clear();cache[key]=result;return result;
    }
    public Mesh scatter_mesh(Node3D owner,Mesh source,bool lod)
    {
        string key=unchecked((long)source.GetInstanceId()).ToString(CultureInfo.InvariantCulture)+":"+(lod?"true":"false");var meshes=State(owner,"_scatter_mesh_scope");if(meshes.TryGetValue(key,out var cached))return cached.As<Mesh>();if(meshes.Count>=128)meshes.Clear();
        var result=(Mesh)(lod?lod_mesh(source,State(owner,"_asset_lod_scope")):source).Duplicate(false);var scope=State(owner,"_material_scope");for(int surface=0;surface<result.GetSurfaceCount();surface++)
        {
            if(source.SurfaceGetMaterial(surface) is not ShaderMaterial authored)continue;ulong identity=authored.GetInstanceId();if(!scope.TryGetValue(identity,out var material)){material=Assets().Call("timeline_material",authored,true);scope[identity]=material;}result.SurfaceSetMaterial(surface,material.As<Material>());
        }
        meshes[key]=result;return result;
    }
}
