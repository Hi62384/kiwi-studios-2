using Godot;
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class EnvironmentInstanceStream : RefCounted
{
    private readonly ModelNaturalRender _natural=new();
    private static Variant Get(Settings values,Variant key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private static GDScript Assets()=>GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/environment_assets.gd");
    private static void Error(Node3D runtime,string text){var values=runtime.Get("errors").AsStringArray().ToList();values.Add(text);runtime.Set("errors",values.ToArray());}
    public void install(Node3D runtime,Node3D node,Settings result,Resource source)
    {var operations=(EnvironmentRuntimeOperations)((MigrationBootstrap)Engine.GetSingleton("KiwiNativeServices")).service("environment_runtime");Install(runtime,node,result,source,operations);}
    internal void Install(Node3D runtime,Node3D node,Settings result,Resource source,EnvironmentRuntimeOperations operations)
    {
        var packets=new Settings();var bins=new Settings();var state=new Settings {["packets"]=packets,["bins"]=bins,["active"]=new Settings(),["rules"]=source,["radius"]=0.0};double size=source.Get("render_cluster_size").AsDouble();
        foreach(var entry in Get(result,"batches",new Settings()).AsGodotDictionary())
        {
            int palette=entry.Key.AsInt32();var asset=Assets().Call("load_scatter_parts",Get(source.Get("palette").AsGodotArray()[palette].AsGodotDictionary(),"source", "")).AsGodotDictionary();string error=asset["error"].AsString();if(error.Length>0){Error(runtime,error);continue;}
            var parts=asset["parts"].AsGodotArray();for(int partIndex=0;partIndex<parts.Count;partIndex++)
            {
                var part=parts[partIndex].AsGodotDictionary();var clusters=new Dictionary<Vector2I,List<Transform3D>>();var mesh=operations.scatter_mesh(runtime,part["mesh"].As<Mesh>(),source.Get("lod_enabled").AsBool());var original=mesh.GetAabb();
                foreach(var value in entry.Value.AsGodotArray()){var pose=value.AsTransform3D();var cell=new Vector2I((int)Math.Floor(pose.Origin.X/size),(int)Math.Floor(pose.Origin.Z/size));if(!clusters.TryGetValue(cell,out var poses))clusters[cell]=poses=new();poses.Add(pose*part["transform"].AsTransform3D());}
                foreach(var cluster in clusters)
                {
                    var cell=cluster.Key;var poses=cluster.Value;string identity=FormattableString.Invariant($"{palette}:{partIndex}:{cell.X}:{cell.Y}");var bounds=poses[0]*original;foreach(var pose in poses)bounds=bounds.Merge(pose*original);var center=new Vector3((float)((cell.X+.5)*size),0,(float)((cell.Y+.5)*size));state["radius"]=Math.Max(state["radius"].AsDouble(),bounds.GetCenter().DistanceTo(center)+bounds.Size.Length()*.5);var poseValues=new GArray();foreach(var pose in poses)poseValues.Add(pose);
                    packets[identity]=new Settings {["mesh"]=mesh,["poses"]=poseValues,["center"]=center,["bounds"]=bounds};if(!bins.TryGetValue(cell,out var values)){values=new GArray();bins[cell]=values;}values.AsGodotArray().Add(identity);
                }
            }
        }
        node.SetMeta("scatter_stream",state);runtime.Get("stream_nodes").AsGodotDictionary()[node.GetInstanceId()]=node;refresh(runtime,node);
    }
    public void refresh(Node3D runtime,Node3D node)
    {
        if(!GodotObject.IsInstanceValid(node)||!node.IsInsideTree())return;var state=node.GetMeta("scatter_stream",new Settings()).AsGodotDictionary();if(state.Count==0)return;var source=state["rules"].As<Resource>();var camera=runtime.GetViewport().GetCamera3D();var priority=runtime.Get("priority_camera").As<Camera3D>();if(camera==null&&GodotObject.IsInstanceValid(priority))camera=priority;
        var candidates=new GArray();var wanted=new HashSet<string>(StringComparer.Ordinal);var position=Vector3.Zero;double size=source.Get("render_cluster_size").AsDouble(),limit=source.Get("render_distance").AsDouble()+Math.Max(8,size*.5);var scale=node.GlobalBasis.Scale.Abs();bool invertible=Math.Abs(node.GlobalBasis.Determinant())>.000001;var packets=state["packets"].AsGodotDictionary();var bins=state["bins"].AsGodotDictionary();var active=state["active"].AsGodotDictionary();
        if(node.IsVisibleInTree())
        {
            if(camera==null||!invertible){foreach(var key in packets.Keys)candidates.Add(key);}
            else
            {
                position=camera.GlobalPosition;var local=node.GlobalTransform.AffineInverse()*position;double radius=(limit/Math.Max(.0001,Math.Min(scale.X,Math.Min(scale.Y,scale.Z)))+state["radius"].AsDouble())/size,reach=Math.Ceiling(radius)+1;var center=new Vector2I((int)Math.Floor(local.X/size),(int)Math.Floor(local.Z/size));
                if((reach*2+1)*(reach*2+1)>bins.Count*2){foreach(var values in bins.Values)candidates.AddRange(values.AsGodotArray());}
                else{int distance=(int)reach;for(int z=center.Y-distance;z<=center.Y+distance;z++)for(int x=center.X-distance;x<=center.X+distance;x++)if(bins.TryGetValue(new Vector2I(x,z),out var values))candidates.AddRange(values.AsGodotArray());}
            }
        }
        foreach(var key in candidates)
        {
            string identity=key.AsString();var packet=packets[identity].AsGodotDictionary();if(camera!=null&&invertible){var bounds=node.GlobalTransform*packet["bounds"].AsAabb();var closest=position.Clamp(bounds.Position,bounds.End);double threshold=active.ContainsKey(identity)?limit+size*.5:limit;if(closest.DistanceSquaredTo(position)>threshold*threshold)continue;}wanted.Add(identity);if(active.ContainsKey(identity))continue;
            var poses=packet["poses"].AsGodotArray();var batch=new MultiMeshInstance3D();using var mesh=new MultiMesh {TransformFormat=MultiMesh.TransformFormatEnum.Transform3D,Mesh=packet["mesh"].As<Mesh>(),InstanceCount=poses.Count};var center=packet["center"].AsVector3();for(int index=0;index<poses.Count;index++){var pose=poses[index].AsTransform3D();pose.Origin-=center;mesh.SetInstanceTransform(index,pose);}double distance=source.Get("render_distance").AsDouble();batch.Position=center;batch.Multimesh=mesh;batch.LodBias=source.Get("lod_bias").AsSingle();batch.VisibilityRangeEnd=(float)distance;batch.VisibilityRangeEndMargin=(float)(distance*.15);batch.VisibilityRangeFadeMode=GeometryInstance3D.VisibilityRangeFadeModeEnum.Self;node.AddChild(batch);active[identity]=batch;_natural.time(batch,runtime.Get("preview_time").AsDouble(),new Settings());
        }
        foreach(var key in active.Keys.ToArray())if(!wanted.Contains(key.AsString())){var batch=active[key].As<MultiMeshInstance3D>();if(GodotObject.IsInstanceValid(batch))batch.Free();active.Remove(key);}
    }
}
