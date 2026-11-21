using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;

public partial class WorldPlacementOperations : RefCounted
{
    private readonly ModelDocumentOperations _models=new();
    private readonly ModelMeshOperations _meshes=new();
    private readonly EnvironmentDocumentOperations _environments=new();
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    public bool moved(Resource item,Transform3D pose)
    {var parameters=item.Get("parameters").AsGodotDictionary();if(parameters.TryGetValue("world_global_pose",out var global))return !pose.IsEqualApprox(global.AsTransform3D());var transform=item.Get("transform").AsTransform3D();return transform!=Get(parameters,"world_pose",transform).AsTransform3D()||Get(parameters,"world_manual_pose",false).AsBool();}
    public string capture(RefCounted session,string id,Resource source)
    {
        var occupied=source.Get("occupied").AsGodotArray();occupied.Clear();if(!source.Get("respect_existing_objects").AsBool())return "";var document=session.Get("document").As<Resource>();var world=_models.component(document,id);if(world==null)return "The world no longer exists.";var pose=_models.world_transform(document,world);if(Math.Abs(pose.Basis.Determinant())<.000001)return "Restore a non-zero world scale before generating placement masks.";var inverse=pose.AffineInverse();var buildings=new Dictionary<string,Resource>(StringComparer.Ordinal);var roots=new Godot.Collections.Array<string>();var initial=_models.hierarchy_state(document,new Godot.Collections.Array<string>())["poses"].AsGodotDictionary();var components=document.Get("components").AsGodotArray();
        foreach(var value in components){var item=value.As<Resource>();var parameters=item.Get("parameters").AsGodotDictionary();if(!parameters.ContainsKey("architecture_source"))continue;string componentId=item.Get("id").AsString();bool owned=Get(parameters,"world_owner","").AsString()==id;if(owned&&!moved(item,inverse*initial[componentId].AsTransform3D()))continue;buildings[componentId]=item;roots.Add(componentId);}
        var hierarchy=_models.hierarchy_state(document,roots);var poses=hierarchy["poses"].AsGodotDictionary();var selected=hierarchy["selected"].AsGodotDictionary();foreach(var value in components)
        {
            var item=value.As<Resource>();string componentId=item.Get("id").AsString();var parameters=item.Get("parameters").AsGodotDictionary();var local=inverse*poses[componentId].AsTransform3D();var polygon=new List<Vector2>();
            if(buildings.ContainsKey(componentId)){var building=parameters["architecture_source"].As<Resource>();foreach(var point in building.Get("footprint").AsVector2Array()){var transformed=local*new Vector3(point.X,0,point.Y);polygon.Add(new Vector2(transformed.X,transformed.Z));}}
            else{bool owned=Get(parameters,"world_generated",false).AsBool()&&Get(parameters,"world_owner","").AsString()==id;if(selected[componentId].AsBool()||owned&&!moved(item,local)||Get(parameters,"editor_proxy",false).AsBool())continue;var mesh=item.Get("mesh").As<Resource>();if(_environments.component_kind(document,componentId)!="asset"||mesh==null||item.Get("is_skeleton").AsBool())continue;var bounds=_meshes.bounds(mesh);for(int corner=0;corner<8;corner++){var transformed=local*bounds.GetEndpoint(corner);polygon.Add(new Vector2(transformed.X,transformed.Z));}polygon=new List<Vector2>(Geometry2D.ConvexHull(polygon.ToArray()));if(polygon.Count>1&&polygon[0].IsEqualApprox(polygon[^1]))polygon.RemoveAt(polygon.Count-1);}
            if(polygon.Count<3)continue;double area=0;for(int index=0;index<polygon.Count;index++)area+=polygon[index].Cross(polygon[(index+1)%polygon.Count]);if(Math.Abs(area)<.001)continue;occupied.Add(new Settings {["owner"]=componentId,["polygon"]=polygon.ToArray(),["plot"]=Get(parameters,"world_plot",""),["world"]=Get(parameters,"world_owner","")});if(occupied.Count>16384)return "Existing-object footprints exceed the region budget. Generate a smaller environment region.";
        }
        return "";
    }
    public void follow_controls(Resource source)
    {
        var field=source.Get("terrain_field").As<RefCounted>();if(field==null)return;var roads=source.Get("roads").AsGodotArray();var fixedNodes=new HashSet<string>(StringComparer.Ordinal);foreach(var value in roads){var road=value.AsGodotDictionary();if(Get(road,"mode","Ground").AsString()!="Ground"||!Get(road,"follow_terrain",false).AsBool()){fixedNodes.Add(road["from"].AsString());fixedNodes.Add(road["to"].AsString());}}
        var nodes=source.Get("nodes").AsGodotDictionary();foreach(var value in roads){var road=value.AsGodotDictionary();if(Get(road,"mode","Ground").AsString()!="Ground"||!Get(road,"follow_terrain",false).AsBool())continue;var points=road["points"].AsVector3Array();for(int index=0;index<points.Length;index++){if(index==0&&fixedNodes.Contains(road["from"].AsString())||index==points.Length-1&&fixedNodes.Contains(road["to"].AsString()))continue;var point=new Vector2(points[index].X,points[index].Z);var surface=field is WorldTerrainField terrain?terrain.sample(point):field.Call("sample",point).AsGodotDictionary();if(surface.Count>0)points[index].Y=surface["height"].AsSingle()+.03f;}road["points"]=points;nodes[road["from"]]=points[0];nodes[road["to"]]=points[^1];}
    }
}
