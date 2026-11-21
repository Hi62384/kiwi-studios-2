using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class EnvironmentRuntimeOperations
{
    private static Settings Revisions()=>Assets().Call("_revision_state").AsGodotDictionary();
    public void terrain(Node3D owner,Resource item,Node3D node,Settings metadata)
    {
        var source=Get(metadata,"terrain").As<Resource>();if(source==null)return;source.Call("prepare");var material=Assets().Call("material",Get(metadata,"material")).As<Material>()??owner.Get("default_ground").As<Material>();var paint=Assets().Call("material",Get(metadata,"paint_material")).As<Material>();var live=new HashSet<string>(StringComparer.Ordinal);source.Call("prepare_geometry_keys");var revisions=Revisions();
        var blended=_biome.material(node,source,material,paint!,revisions);foreach(string warning in node.GetMeta("biome_material_warnings",Array.Empty<string>()).AsStringArray().Distinct(StringComparer.Ordinal))Warning(owner,warning);blended??=_paint.material(node,source,material,paint!,revisions);if(blended!=null){material=blended;paint=blended;}
        string id=item.Get("id").AsString();var overlay=id==owner.Get("biome_preview_terrain").AsString()?biome_overlay(owner,node,source):null;int n=source.Get("resolution").AsInt32(),side=(int)Math.Ceiling((n-1)/32.0);bool cutaway=owner.Get("cave_cutaway").AsBool(),progressive=owner.Get("progressive").AsBool();double distance=source.Get("render_distance").AsDouble();var volumes=source.Get("volume_chunks").AsGodotDictionary();
        for(int z=0;z<side;z++)for(int x=0;x<side;x++)
        {
            var coordinate=new Vector2I(x,z);string name=$"Chunk_{x}_{z}";live.Add(name);var chunk=node.GetNodeOrNull<MeshInstance3D>(name);if(chunk==null){chunk=new MeshInstance3D {Name=name};node.AddChild(chunk);}chunk.SetMeta("smooth_paint",blended!=null);chunk.MaterialOverlay=overlay;chunk.LodBias=(float)Math.Max(.01,source.Get("lod_bias").AsDouble());chunk.VisibilityRangeEnd=(float)Math.Max(0,distance);chunk.VisibilityRangeEndMargin=(float)(distance*.15);chunk.VisibilityRangeFadeMode=distance>0?GeometryInstance3D.VisibilityRangeFadeModeEnum.Self:GeometryInstance3D.VisibilityRangeFadeModeEnum.Disabled;bool volume=source.Call("needs_volume",coordinate).AsBool();chunk.Visible=!cutaway||volume;
            long key=Hash(new GArray {source.Call("chunk_geometry_key",coordinate,blended==null),cutaway,blended!=null});
            if(volume&&(!volumes.TryGetValue(coordinate,out var data)||Get(data.AsGodotDictionary(),"key",-1).AsInt64()!=_terrainData.PreparedVolumeKey(source,coordinate))){Error(owner,"Cave geometry needs generation.");continue;}
            bool collision=Get(metadata,"collision",true).AsBool()&&node.Visible;
            if(chunk.GetMeta("terrain_key",-1).AsInt64()!=key)
            {
                if(progressive)State(owner,"pending_chunks")[id+":"+name]=new Settings {["id"]=id,["node"]=node,["chunk"]=chunk,["terrain"]=source,["coordinate"]=coordinate,["key"]=key,["material"]=material,["paint"]=paint!=null?Variant.From(paint):default,["collision"]=collision};else _collision.build_chunk(owner,source,coordinate,chunk,key);
            }
            if(chunk.Mesh!=null)_collision.assign_chunk_materials(chunk,material,paint,collision);
        }
        _water.sync(node,source);live.Add("Water");foreach(var child in node.GetChildren())if(!live.Contains(child.Name.ToString()))child.QueueFree();
    }
    public Material? biome_overlay(Node3D owner,Node3D node,Resource source)
    {
        string id=owner.Get("biome_preview_id").AsString();var data=source.Get("biome_data").AsGodotDictionary();var weights=Get(Get(data,"weights",new Settings()).AsGodotDictionary(),id,Array.Empty<float>()).AsFloat32Array();int n=source.Get("resolution").AsInt32();if(weights.Length!=n*n)return null;
        long key=Hash(new GArray {id,source.Get("biome_key"),Get(data,"preview_revision",0),n});var material=node.HasMeta("biome_overlay")?node.GetMeta("biome_overlay").As<ShaderMaterial>():null;
        if(material==null){material=new ShaderMaterial {Shader=GD.Load<Shader>("res://Workspaces/EnvironmentWorkspace/terrain/terrain_biome_overlay.gdshader")};node.SetMeta("biome_overlay",material);}
        if(node.GetMeta("biome_overlay_key",-1).AsInt64()!=key)
        {
            var bytes=new byte[weights.Length*sizeof(float)];Buffer.BlockCopy(weights,0,bytes,0,bytes.Length);using var image=Image.CreateFromData(n,n,false,Image.Format.Rf,bytes);image.GenerateMipmaps();var texture=material.GetShaderParameter("weights").As<ImageTexture>();if(texture!=null&&texture.GetSize()==new Vector2(n,n))texture.Update(image);else texture=ImageTexture.CreateFromImage(image);
            material.SetShaderParameter("weights",texture);material.SetShaderParameter("terrain_size",source.Get("dimensions"));material.SetShaderParameter("tint",Color.FromHsv((float)(Hash(id)%360/360.0),.65f,1));node.SetMeta("biome_overlay_key",key);
        }
        return material;
    }
}
