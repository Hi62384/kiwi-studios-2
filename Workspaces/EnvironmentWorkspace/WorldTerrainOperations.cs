using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class WorldTerrainOperations : RefCounted
{
    private readonly ModelDocumentOperations _models=new();
    private readonly EnvironmentDocumentOperations _documents=new();
    private readonly WorldSourceOperations _sources=new();
    private readonly RoadGeometryOperations _geometry=new();
    private readonly RoadRoutingOperations _routing=new();
    private readonly RoadSectionOperations _sections=new();
    private readonly TerrainGenerationOperations _generation=new();
    private readonly TerrainDataOperations _terrain=new();
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private static Settings Failure(string error)=>new() {["error"]=error};
    public Settings context(RefCounted session,string id,Resource source)
    {
        var document=session.Get("document").As<Resource>();string terrainId=source.Get("terrain_id").AsString();var owner=_models.component(document,id);var ground=_models.component(document,terrainId);var terrain=_documents.terrain(document,terrainId);if(owner==null||ground==null||terrain==null)return Failure("Choose a terrain reference for this world first.");var pose=_models.world_transform(document,owner);var groundPose=_models.world_transform(document,ground);if(Math.Abs(pose.Basis.Determinant())<.00001||Math.Abs(groundPose.Basis.Determinant())<.00001)return Failure("A zero-sized world or terrain cannot be sampled.");if(pose.Basis.Y.Normalized().Dot(Vector3.Up)<.999||groundPose.Basis.Y.Normalized().Dot(Vector3.Up)<.999)return Failure("Road terrain fitting requires upright world and terrain groups.");terrain.Call("prepare");return new Settings {["error"]="",["terrain"]=terrain,["to_ground"]=groundPose.AffineInverse()*pose,["to_world"]=pose.AffineInverse()*groundPose};
    }
    public Settings sample(Settings info,Vector2 point)
    {
        var local=info["to_ground"].AsTransform3D()*new Vector3(point.X,0,point.Y);var terrain=info["terrain"].As<Resource>();var uv=new Vector2(local.X,local.Z)/terrain.Get("dimensions").AsVector2()+Vector2.One*.5f;if(uv.X<0||uv.Y<0||uv.X>1||uv.Y>1)return new();var p=uv*(terrain.Get("resolution").AsInt32()-1);var cell=(Vector2I)p.Floor();var f=p-(Vector2)cell;
        // Scalar calls preserve live edits on the legacy Resource without copying its packed buffers per query.
        double Height(int x,int z)=>terrain.Call("height",x,z).AsDouble();double height=Mathf.Lerp(Mathf.Lerp(Height(cell.X,cell.Y),Height(cell.X+1,cell.Y),f.X),Mathf.Lerp(Height(cell.X,cell.Y+1),Height(cell.X+1,cell.Y+1),f.X),f.Y);var toWorld=info["to_world"].AsTransform3D();var position=toWorld*new Vector3(local.X,(float)height,local.Z);var water=_terrain.water_at(terrain,new Vector3(local.X,(float)(height+.001),local.Z));bool wet=water.Count>0&&Get(water,"depth",0.0).AsDouble()>.03;var surface=Get(water,"surface",new Vector3(local.X,(float)height,local.Z)).AsVector3();return new Settings {["height"]=(double)position.Y+.03,["water"]=wet,["water_level"]=(toWorld*surface).Y,["water_depth"]=Get(water,"depth",0.0)};
    }
    public Settings fit(RefCounted session,string id,Resource source,int index,bool automatic)
    {
        var info=context(session,id,source);if(info["error"].AsString().Length>0)return new Settings {["source"]=default,["error"]=info["error"]};var next=_sources.copy(source);var roads=next.Get("roads").AsGodotArray();var road=roads[index].AsGodotDictionary();var controls=road["points"].AsVector3Array();var points=_geometry.sample(controls,2);
        if(automatic){var from=sample(info,new Vector2(controls[0].X,controls[0].Z));var to=sample(info,new Vector2(controls[^1].X,controls[^1].Z));if(from.Count==0||to.Count==0)return new Settings {["source"]=default,["error"]="Both road endpoints must lie on the referenced terrain."};var exclusions=new List<Vector2[]>();foreach(var value in next.Get("exclusions").AsGodotArray()){var area=value.AsGodotDictionary();if(Get(area,"protected",true).AsBool())exclusions.Add(Get(area,"polygon",Array.Empty<Vector2>()).AsVector2Array());}var dimensions=next.Get("dimensions").AsVector2();var route=_routing.Route(new Vector3(controls[0].X,from["height"].AsSingle(),controls[0].Z),new Vector3(controls[^1].X,to["height"].AsSingle(),controls[^1].Z),new Rect2(-dimensions*.5f,dimensions),point=>sample(info,point),exclusions.ToArray(),49,()=>false,false);if(route["error"].AsString().Length>0)return new Settings {["source"]=default,["error"]=route["error"]};points=_geometry.sample(route["points"].AsVector3Array(),2);}
        if(points.Length>512)return new Settings {["source"]=default,["error"]="Split this road into segments under about one kilometer before detailed terrain fitting."};for(int point=0;point<points.Length;point++){var surface=sample(info,new Vector2(points[point].X,points[point].Z));if(surface.Count==0)return new Settings {["source"]=default,["error"]="Road "+Get(road,"name","").AsString()+" leaves the referenced terrain."};points[point].Y=surface["height"].AsSingle();}road["points"]=points;var nodes=next.Get("nodes").AsGodotDictionary();nodes[road["from"]]=points[0];nodes[road["to"]]=points[^1];foreach(var value in roads){var other=value.AsGodotDictionary();var values=other["points"].AsVector3Array();if(nodes.TryGetValue(other["from"],out var from))values[0]=from.AsVector3();if(nodes.TryGetValue(other["to"],out var to))values[^1]=to.AsVector3();other["points"]=values;}return new Settings {["source"]=next,["error"]=""};
    }
    public string grade(RefCounted session,string id,Resource source,bool remove)
    {var plan=grading_plan(session,id,source,remove);if(plan["error"].AsString().Length>0)return plan["error"].AsString();session.Call("regenerate_terrain",plan["id"].AsString(),plan["settings"]);return "";}
    public Settings grading_plan(RefCounted session,string id,Resource source,bool remove)
    {
        var info=context(session,id,source);if(info["error"].AsString().Length>0)return Failure(info["error"].AsString());var terrain=info["terrain"].As<Resource>();var original=terrain.Get("generation").As<Resource>();var generator=original?.Duplicate(true)??GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/terrain/terrain_generator.gd").New().As<Resource>();if(original==null){generator.Set("medium_weight",0.0);generator.Set("fine_weight",0.0);}var layers=generator.Get("layers").AsGodotArray().Duplicate();layers.Clear();foreach(var value in generator.Get("layers").AsGodotArray())if(Get(value.AsGodotDictionary(),"world_road_owner","").AsString()!=id)layers.Add(value);
        if(!remove)
        {
            var owner=_models.component(session.Get("document").As<Resource>(),id)!;var parameters=owner.Get("parameters").AsGodotDictionary();var graph=Get(parameters,"world_graph",new Settings()).AsGodotDictionary();var roads=Get(graph,"edges",source.Get("roads")).AsGodotArray();var toGround=info["to_ground"].AsTransform3D();foreach(var value in roads){var road=value.AsGodotDictionary();if(!Get(road,"enabled",true).AsBool()||Get(road,"bridge",false).AsBool()||Get(road,"mode","Ground").AsString()!="Ground")continue;var points=_geometry.sample(road["points"].AsVector3Array(),2);for(int segment=0;segment<points.Length-1;segment++){var a=points[segment];var b=points[segment+1];if(new Vector2(a.X,a.Z).DistanceTo(new Vector2(b.X,b.Z))<.02)continue;var direction=(b-a).Normalized();var side=new Vector3(-direction.Z,0,direction.X).Normalized()*(float)(_sections.outer_half(road)+.5);var polygon=new List<Vector2>();foreach(var point in new[]{a+side,a-side,b-side,b+side}){var local=toGround*(point-Vector3.Up*.03f);polygon.Add(new Vector2(local.X,local.Z));}var plane=new Plane(toGround*(a-Vector3.Up*.03f),toGround*(b-Vector3.Up*.03f),toGround*(a+side-Vector3.Up*.03f));if(Math.Abs(plane.Normal.Y)<.2)return Failure("A road section is too steep to grade safely.");layers.Add(new Settings {["id"]="roadbed:"+road["id"].AsString()+":"+segment,["type"]="Foundation",["world_road_owner"]=id,["road_id"]=road["id"],["polygon"]=polygon.ToArray(),["plane"]=plane,["feather"]=2.0,["enabled"]=true,["surface_target"]=true});}}
        }
        generator.Set("foundation_edits",terrain.Get("edits").AsFloat32Array());generator.Set("layers",layers);var errors=_generation.validate(generator);if(errors.Length>0)return Failure(errors[0]);if(!layers.Any(value=>Get(value.AsGodotDictionary(),"surface_target",false).AsBool()))generator.Set("foundation_edits",Array.Empty<float>());return new Settings {["error"]="",["id"]=source.Get("terrain_id"),["settings"]=new Settings {["generation"]=generator}};
    }
}
