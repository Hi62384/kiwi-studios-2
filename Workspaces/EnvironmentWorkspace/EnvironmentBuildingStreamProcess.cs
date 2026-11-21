using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class EnvironmentBuildingStreamOperations
{
    public void process(RefCounted state)
    {
        var runtime=Runtime(state);var document=runtime?.Get("document").As<Resource>();if(runtime==null||document==null)return;var retired=Retired(state);for(int index=retired.Count-1;index>=0;index--){var job=retired[index].As<RefCounted>();if(job.Call("complete").AsBool()){job.Call("collect");retired.RemoveAt(index);}}
        var wanted=new List<Settings>();int working=0;long memoryLimit=0;var policies=new Dictionary<string,Settings>(StringComparer.Ordinal);ulong uploadStarted=Time.GetTicksUsec();bool uploaded=false;var camera=runtime.GetViewport().GetCamera3D();var priority=runtime.Get("priority_camera").As<Camera3D>();if(camera==null&&Live(priority))camera=priority;var entries=Entries(state);var indexMap=runtime.Get("component_index").AsGodotDictionary();var metadata=document.Get("component_settings").AsGodotDictionary();
        foreach(var identity in entries.Keys.ToArray())
        {
            var entry=entries[identity].AsGodotDictionary();var item=Get(indexMap,identity.AsString()).As<Resource>();var node=entry["node"].As<Node3D>();
            if(item==null||Get(Get(metadata,identity,new Settings()).AsGodotDictionary(),"kind", "").AsString()!="building"||!Live(node)||Get(runtime.Get("nodes").AsGodotDictionary(),identity).As<Node3D>()!=node){retire(state,entry);entries.Remove(identity);continue;}
            entry["wanted"]=false;string owner=Get(item.Get("parameters").AsGodotDictionary(),"world_owner","independent").AsString();if(!policies.TryGetValue(owner,out var limits))policies[owner]=limits=policy(state,entry);memoryLimit=Math.Max(memoryLimit,limits["cache"].AsInt64());double distance=camera==null?0:camera.GlobalPosition.DistanceSquaredTo(node.GlobalPosition);entry["distance"]=distance;entry["near"]=node.IsVisibleInTree()&&(camera==null||distance<Math.Pow(limits["distance"].AsDouble(),2));entry["active_limit"]=limits["active"];
            var job=Get(entry,"job").As<RefCounted>();if(job!=null)
            {
                if(job.Call("complete").AsBool())
                {
                    var result=job.Call("collect").AsGodotDictionary();entry["job"]=default;if(!Get(result,"cancelled",false).AsBool())
                    {
                        var generated=Get(result,"document").As<Resource>();var errors=Get(result,"errors",new[]{"Could not generate building detail."}).AsStringArray();
                        if(generated!=null&&errors.Length==0)
                        {
                            var detailDocument=new KiwiEnvironmentDocument();var components=detailDocument.Get("components").AsGodotArray();foreach(var value in generated.Get("components").AsGodotArray())components.Add(value);var settings=detailDocument.Get("component_settings").AsGodotDictionary();long bytes=0;
                            foreach(var value in components){var component=value.As<Resource>();settings[component.Get("id")]=new Settings {["kind"]="asset",["collision"]=Get(entry,"collision",true).AsBool()};var mesh=component.Get("mesh").As<Resource>();bytes+=mesh!=null?mesh.Get("vertices").AsVector3Array().LongLength*64+mesh.Get("faces").AsGodotArray().Count*96L:256;}entry["document"]=detailDocument;entry["bytes"]=bytes;
                        }
                        else{entry["error"]=string.Join(" · ",errors);Message(runtime,"errors",entry["error"].AsString());}
                    }
                }
                else working++;
            }
            if(entry["near"].AsBool()||state.Get("physics_full").AsBool())wanted.Add(entry);
        }
        wanted=wanted.OrderBy(entry=>entry["distance"].AsDouble()).ToList();var visible=new HashSet<string>(StringComparer.Ordinal);var perWorld=new Dictionary<string,int>(StringComparer.Ordinal);
        foreach(var entry in wanted)
        {
            var item=indexMap[entry["id"].AsString()].As<Resource>();string owner=Get(item.Get("parameters").AsGodotDictionary(),"world_owner","independent").AsString();int count=perWorld.GetValueOrDefault(owner);bool near=entry["near"].AsBool()&&count<entry["active_limit"].AsInt64();if(near)perWorld[owner]=count+1;if(!near&&!state.Get("physics_full").AsBool())continue;visible.Add(entry["id"].AsString());entry["wanted"]=true;
            if(Get(entry,"document").As<Resource>()==null&&Get(entry,"job").As<RefCounted>()==null&&entry["error"].AsString().Length==0&&working<2){var job=new BuildingGenerationJob();entry["job"]=job;job.start(entry["source"].As<Resource>());state.Set("builds",state.Get("builds").AsInt64()+1);working++;}
            var source=Get(entry,"document").As<Resource>();if(source!=null)
            {
                entry["used"]=Time.GetTicksUsec();var detail=Get(entry,"detail").As<Node3D>();if(!Live(detail))
                {
                    detail=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/environment_runtime.gd").New().As<Node3D>();detail.Name="BuildingDetail";detail.Set("progressive",true);detail.Set("priority_camera",camera!=null?Variant.From(camera):default);detail.Set("upload_budget_usec",500);entry["node"].As<Node3D>().AddChild(detail);detail.Call("configure",source);detail.SetProcess(false);detail.Set("preview_time",runtime.Get("preview_time"));entry["detail"]=detail;state.Set("cache_hits",state.Get("cache_hits").AsInt64()+1);
                }
                if(detail!.Get("pending_assets").AsGodotDictionary().Count>0&&(!uploaded||Time.GetTicksUsec()-uploadStarted<2000)){detail.Set("preview_time",runtime.Get("preview_time"));detail.Call("_process",0.0);uploaded=true;}
                bool complete=detail.Get("pending_assets").AsGodotDictionary().Count==0&&detail.Get("pending_chunks").AsGodotDictionary().Count==0;detail.Visible=near&&complete;entry["shell"].As<MeshInstance3D>().Visible=!near||!complete;
            }
        }
        foreach(var value in entries.Values)
        {
            var entry=value.AsGodotDictionary();if(visible.Contains(entry["id"].AsString()))continue;var job=Get(entry,"job").As<RefCounted>();if(job!=null){job.Call("cancel");retired.Add(job);entry["job"]=default;}var detail=Get(entry,"detail").As<Node3D>();if(Live(detail)){detail!.Free();entry["detail"]=default;}entry["shell"].As<MeshInstance3D>().Visible=true;
        }
        long cacheBytes=0;var disposable=new List<Settings>();foreach(var value in entries.Values){var entry=value.AsGodotDictionary();cacheBytes+=entry["bytes"].AsInt64();if(Get(entry,"document").As<Resource>()!=null&&!Live(Get(entry,"detail").As<Node3D>()))disposable.Add(entry);}
        foreach(var entry in disposable.OrderBy(entry=>entry["used"].AsInt64())){if(cacheBytes<=memoryLimit)break;cacheBytes-=entry["bytes"].AsInt64();entry["bytes"]=0;entry["document"]=default;}state.Set("cache_bytes",cacheBytes);
        if(uploaded)
        {
            var actor=runtime.GetParent();if(actor!=null&&actor.HasMethod("set_timeline_time")){var script=actor.GetScript().As<Godot.Script>();while(script!=null){if(script.ResourcePath=="res://scripts/actors/core/ActorRuntime.cs"){actor.Call("set_timeline_time",runtime.Get("preview_time"));break;}script=script.GetBaseScript();}}
        }
    }
}
