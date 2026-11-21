using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;
using Topology=ModelGeometryOperations.Topology;

public partial class BuildingGeometryOperations
{
    public void wall_finishes(Resource item,Resource source,Settings floor,Settings wall)
    {
        var a=wall["a"].AsVector2();var b=wall["b"].AsVector2();var direction=(b-a).Normalized();var normal=new Vector2(-direction.Y,direction.X);var polygon=Get(floor,"footprint",source.Get("footprint")).AsVector2Array();bool plus=Geometry2D.IsPointInPolygon((a+b)*.5f+normal*.05f,polygon),minus=Geometry2D.IsPointInPolygon((a+b)*.5f-normal*.05f,polygon);var materials=source.Get("materials").AsGodotArray();Variant interior=materials.Count>5?materials[5]:materials.Count>0?materials[0]:default;var parameters=item.Get("parameters").AsGodotDictionary();var surfaces=item.Get("surface_materials").AsGodotArray();var mesh=item.Get("mesh").As<Resource>();
        if(plus&&minus){parameters["architecture_material_slot"]=5;surfaces.Clear();surfaces.Add(interior);}
        else if(plus!=minus)
        {
            surfaces.Clear();surfaces.Add(materials.Count>0?materials[0]:default);surfaces.Add(interior);parameters["architecture_material_slots"]=new[]{0,5};var data=Top(mesh);float sign=plus?1:-1;for(int face=0;face<data.Faces.Count;face++)data.Materials[face]=ModelGeometryOperations.Normal(data.Points,data.Faces[face]).Z*sign>.5?1:0;Assign(mesh,data);
        }
        parameters["_architecture_generated_mesh"]=mesh_key(mesh,2);
    }
    public GArray interior_trim(Resource source,Settings floor,Settings wall,double length,double height)
    {
        var output=new GArray();double baseboard=source.Get("baseboard_height").AsDouble(),crown=source.Get("crown_height").AsDouble();if(baseboard<=0&&crown<=0)return output;var a=wall["a"].AsVector2();var b=wall["b"].AsVector2();var direction=(b-a).Normalized();var normal=new Vector2(-direction.Y,direction.X);var polygon=Get(floor,"footprint",source.Get("footprint")).AsVector2Array();
        foreach(var spec in new[]{("baseboard",baseboard,0.0),("crown",crown,height-crown)})
        {
            double trimHeight=spec.Item2,bottom=spec.Item3;if(trimHeight<=0||trimHeight>height)continue;var cuts=new List<(double Left,double Right)>();
            foreach(var value in Get(wall,"openings",new GArray()).AsGodotArray())
            {var opening=value.AsGodotDictionary();double center=Get(opening,"t",.5).AsDouble()*length,half=Get(opening,"width",1.0).AsDouble()*.5,low=Get(opening,"bottom",0.0).AsDouble();if(low<bottom+trimHeight&&low+Get(opening,"height",2.0).AsDouble()>bottom)cuts.Add((Math.Max(0,center-half),Math.Min(length,center+half)));}
            var spans=new List<(double Left,double Right)>();double cursor=0;foreach(var cut in cuts.OrderBy(c=>c.Left)){if(cut.Left>cursor)spans.Add((cursor,cut.Left));cursor=Math.Max(cursor,cut.Right);}if(cursor<length)spans.Add((cursor,length));var mesh=new Topology();double depth=source.Get("interior_trim_depth").AsDouble();
            foreach(float side in new[]{-1f,1f})
            {
                if(!Geometry2D.IsPointInPolygon((a+b)*.5f+normal*.05f*side,polygon))continue;
                foreach(var span in spans){var center=new Vector3((float)((span.Left+span.Right)*.5),(float)(bottom+trimHeight*.5),(float)(side*(source.Get("wall_thickness").AsDouble()+depth)*.5));mesh.Append(ModelPrimitives.Box(new Vector3((float)(span.Right-span.Left),(float)trimHeight,(float)depth)),new Transform3D(Basis.Identity,center));}
            }
            if(mesh.Faces.Count>0)output.Add(new Settings {["kind"]=spec.Item1,["mesh"]=mesh.Build()});
        }
        return output;
    }
    public Resource item(Resource document,string id,string title,string parent,Resource? mesh,Transform3D pose,Resource source,int material,string type)
    {
        var result=new KiwiModelComponent();string owner=source.Get("source_id").AsString();result.Set("id",id);result.Set("title",title);result.Set("parent_id",parent);result.Set("mesh",mesh!=null?Variant.From(mesh):default);result.Set("transform",pose);
        result.Set("parameters",new Settings {["architecture_type"]=type,["architecture_owner"]=owner,["architecture_key"]=id.StartsWith(owner,StringComparison.Ordinal)?id[owner.Length..]:id,["architecture_material_slot"]=material,["_architecture_generated_mesh"]=mesh_key(mesh,2),["_architecture_mesh_format"]=2,["_architecture_generated_name"]=title});
        if(mesh!=null){int fallback=material==6?1:material==5?0:material;var materials=source.Get("materials").AsGodotArray();var surfaces=result.Get("surface_materials").AsGodotArray();if(material<materials.Count)surfaces.Add(materials[material]);else if(fallback<materials.Count)surfaces.Add(materials[fallback]);}
        bool physical=source.Get("physics_enabled").AsBool()&&mesh!=null&&new[]{"wall","slab","roof","door","stair treads","landing","railing","foundation"}.Contains(type);
        result.Set("structural",new Settings {[new StringName("structure_enabled")]=physical,[new StringName("structure_role")]=0,[new StringName("structure_assembly")]=owner});document.Get("components").AsGodotArray().Add(result);return result;
    }
}
