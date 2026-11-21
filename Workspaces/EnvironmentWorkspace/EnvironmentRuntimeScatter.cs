using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class EnvironmentRuntimeOperations
{
    public void poll_scatter(Node3D owner)
    {
        var retired=owner.Get("_retired_scatter").AsGodotArray();for(int index=retired.Count-1;index>=0;index--){var job=retired[index].As<RefCounted>();if(job.Call("complete").AsBool()){job.Call("collect");retired.RemoveAt(index);}}
        var jobs=State(owner,"scatter_jobs");var nodes=State(owner,"nodes");
        foreach(var id in jobs.Keys.ToArray())
        {
            var entry=jobs[id].AsGodotDictionary();var job=entry["job"].As<RefCounted>();if(!job.Call("complete").AsBool())continue;job.Call("collect");jobs.Remove(id);var node=entry["node"].As<Node3D>();var document=Document(owner);
            if(job.Call("cancelled").AsBool()||!Live(node)||Get(nodes,id).As<Node3D>()!=node||document==null)continue;
            var metadata=Get(document.Get("component_settings").AsGodotDictionary(),id,new Settings()).AsGodotDictionary();var rules=Get(metadata,"scatter").As<Resource>();var terrain=document.Call("terrain",entry["terrain_id"]).As<Resource>();
            if(rules==null||terrain==null||rules.Call("signature").AsInt64()!=entry["rules_key"].AsInt64()||terrain.Call("signature").AsInt64()!=entry["terrain_key"].AsInt64())continue;
            var result=job.Get("result").AsGodotDictionary();node.SetMeta("scatter_result",result);State(owner,"signatures")[id]=entry["key"];install_scatter(owner,node,result,rules);Report(owner,result);long count=0;foreach(var value in nodes.Values)count+=Get(value.As<Node3D>().GetMeta("scatter_result",new Settings()).AsGodotDictionary(),"count",0).AsInt64();owner.Set("instances",count);
        }
    }
    private static void Report(Node3D owner,Settings result)
    {string error=Get(result,"error", "").AsString(),warning=Get(result,"warning", "").AsString();if(error.Length>0)Error(owner,error);if(warning.Length>0)Warning(owner,warning);}
    public void scatter(Node3D owner,Resource item,Node3D node,Settings metadata)
    {
        var source=Get(metadata,"scatter").As<Resource>();if(source==null)return;node.SetMeta("scatter_rules",source);if(node.HasMeta("scatter_stream")){State(owner,"stream_nodes")[node.GetInstanceId()]=node;node.GetMeta("scatter_stream").AsGodotDictionary()["rules"]=source;}node.SetMeta("kiwi_physics_excluded",!source.Get("collisions").AsBool()||!node.Visible);
        var document=Document(owner)!;var terrain=document.Call("terrain",source.Get("terrain_id")).As<Resource>();if(terrain==null){Error(owner,"Scatter layer has no valid terrain.");return;}
        using var assetKeys=new GArray();foreach(var entry in source.Get("palette").AsGodotArray()){var asset=Assets().Call("load_scatter_parts",Get(entry.AsGodotDictionary(),"source", "")).AsGodotDictionary();assetKeys.Add(asset["key"]);string error=asset["error"].AsString();if(error.Length>0)Error(owner,error);}
        long rulesKey=source.Call("signature").AsInt64(),terrainKey=terrain.Call("signature").AsInt64(),key=Hash(new GArray {rulesKey,terrainKey,assetKeys});var result=node.GetMeta("scatter_result",new Settings()).AsGodotDictionary();string id=item.Get("id").AsString();var signatures=State(owner,"signatures");var jobs=State(owner,"scatter_jobs");var retired=owner.Get("_retired_scatter").AsGodotArray();
        if(Get(signatures,id,-1).AsInt64()!=key)
        {
            double candidates=source.Get("use_anchors").AsBool()?source.Get("anchor_points").AsGodotArray().Count:Math.Min(source.Get("budget").AsDouble(),Math.Round(source.Get("region").AsRect2().Area*source.Get("density").AsDouble(),MidpointRounding.AwayFromZero));
            if(owner.Get("progressive").AsBool()&&candidates>1000)
            {
                if(!jobs.TryGetValue(id,out var current)||current.AsGodotDictionary()["key"].AsInt64()!=key)
                {
                    if(jobs.TryGetValue(id,out current)){var old=current.AsGodotDictionary()["job"].As<RefCounted>();old.Call("cancel");retired.Add(old);}
                    var job=new EnvironmentScatterJob();jobs[id]=new Settings {["job"]=job,["node"]=node,["key"]=key,["rules_key"]=rulesKey,["terrain_key"]=terrainKey,["terrain_id"]=source.Get("terrain_id")};job.start(source,terrain);
                }
            }
            else
            {
                if(jobs.TryGetValue(id,out var current)){var old=current.AsGodotDictionary()["job"].As<RefCounted>();old.Call("cancel");retired.Add(old);jobs.Remove(id);}result=source.Call("generate",terrain).AsGodotDictionary();node.SetMeta("scatter_result",result);signatures[id]=key;install_scatter(owner,node,result,source);
            }
        }
        else if(node.GetMeta("scatter_render_key",-1).AsInt64()!=source.Call("render_signature").AsInt64())install_scatter(owner,node,result,source);
        var collision=node.GetNodeOrNull<MeshInstance3D>("ScatterCollision");if(collision!=null)collision.GetNode<StaticBody3D>("Collision").CollisionLayer=node.Visible?1u:0u;owner.Set("instances",owner.Get("instances").AsInt64()+Get(result,"count",0).AsInt64());Report(owner,result);
    }
    public void install_scatter(Node3D owner,Node3D node,Settings result,Resource source)
    {
        foreach(var child in node.GetChildren())child.Free();node.SetMeta("scatter_render_key",source.Call("render_signature"));if(node.HasMeta("scatter_stream"))node.RemoveMeta("scatter_stream");State(owner,"stream_nodes").Remove(node.GetInstanceId());double clusterSize=source.Get("render_cluster_size").AsDouble(),distance=source.Get("render_distance").AsDouble();
        if(source.Get("stream_instances").AsBool()&&clusterSize>0&&distance>0){_instances.Install(owner,node,result,source,this);if(source.Get("collisions").AsBool())scatter_collision(owner,node,result,source);return;}
        foreach(var entry in Get(result,"batches",new Settings()).AsGodotDictionary())
        {
            int index=entry.Key.AsInt32();var asset=Assets().Call("load_scatter_parts",Get(source.Get("palette").AsGodotArray()[index].AsGodotDictionary(),"source", "")).AsGodotDictionary();string error=asset["error"].AsString();if(error.Length>0){Error(owner,error);continue;}
            foreach(var partEntry in asset["parts"].AsGodotArray())
            {
                var part=partEntry.AsGodotDictionary();var clusters=new Dictionary<Vector2I,List<Transform3D>>();foreach(var poseEntry in entry.Value.AsGodotArray()){var pose=poseEntry.AsTransform3D();var cell=clusterSize>0?new Vector2I((int)Math.Floor(pose.Origin.X/clusterSize),(int)Math.Floor(pose.Origin.Z/clusterSize)):Vector2I.Zero;if(!clusters.TryGetValue(cell,out var poses))clusters[cell]=poses=new();poses.Add(pose);}
                foreach(var cluster in clusters)
                {
                    var cell=cluster.Key;var poses=cluster.Value;var batch=new MultiMeshInstance3D();using var mesh=new MultiMesh {TransformFormat=MultiMesh.TransformFormatEnum.Transform3D,Mesh=scatter_mesh(owner,part["mesh"].As<Mesh>(),source.Get("lod_enabled").AsBool()),InstanceCount=poses.Count};var center=clusterSize>0?new Vector3((float)((cell.X+.5)*clusterSize),0,(float)((cell.Y+.5)*clusterSize)):Vector3.Zero;
                    for(int i=0;i<poses.Count;i++){var pose=poses[i]*part["transform"].AsTransform3D();pose.Origin-=center;mesh.SetInstanceTransform(i,pose);}batch.Position=center;batch.Multimesh=mesh;batch.LodBias=source.Get("lod_bias").AsSingle();batch.VisibilityRangeEnd=(float)distance;batch.VisibilityRangeEndMargin=(float)(distance*.15);batch.VisibilityRangeFadeMode=distance>0?GeometryInstance3D.VisibilityRangeFadeModeEnum.Self:GeometryInstance3D.VisibilityRangeFadeModeEnum.Disabled;node.AddChild(batch);
                }
            }
        }
        if(source.Get("collisions").AsBool())scatter_collision(owner,node,result,source);_natural.time(node,owner.Get("preview_time").AsDouble(),new Settings());
    }
    public void scatter_collision(Node3D owner,Node3D node,Settings result,Resource source)
    {
        const int maximum=600000;var faces=new List<Vector3>();bool exhausted=false;
        foreach(var entry in Get(result,"batches",new Settings()).AsGodotDictionary())
        {
            int index=entry.Key.AsInt32();var asset=Assets().Call("load_scatter_parts",Get(source.Get("palette").AsGodotArray()[index].AsGodotDictionary(),"source", "")).AsGodotDictionary();
            foreach(var value in asset["parts"].AsGodotArray())
            {
                var part=value.AsGodotDictionary();var mesh=part["mesh"].As<Mesh>();var triangles=mesh.HasMeta("kiwi_collision_faces")?mesh.GetMeta("kiwi_collision_faces").AsVector3Array():mesh.GetFaces();
                foreach(var pose in entry.Value.AsGodotArray()){if(faces.Count+triangles.Length>maximum){exhausted=true;break;}var transform=pose.AsTransform3D()*part["transform"].AsTransform3D();foreach(var point in triangles)faces.Add(transform*point);}if(exhausted)break;
            }
            if(exhausted)break;
        }
        if(exhausted)Error(owner,"Scatter collision limit reached. Reduce the collision-enabled layer's budget or use a simpler source mesh.");if(faces.Count==0)return;
        using var arrays=new GArray();arrays.Resize((int)Mesh.ArrayType.Max);arrays[(int)Mesh.ArrayType.Vertex]=faces.ToArray();using var captured=new ArrayMesh();captured.AddSurfaceFromArrays(Mesh.PrimitiveType.Triangles,arrays);var proxy=new MeshInstance3D {Name="ScatterCollision",Mesh=captured,Visible=false};node.AddChild(proxy);var body=new StaticBody3D {Name="Collision"};proxy.AddChild(body);using var shape=new ConcavePolygonShape3D();shape.SetFaces(faces.ToArray());body.AddChild(new CollisionShape3D {Shape=shape});
    }
}
