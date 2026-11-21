using Godot;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading;
using System.Threading.Tasks;
using Settings=Godot.Collections.Dictionary;

public partial class EnvironmentGenerationJob : RefCounted
{
    private static readonly object ActiveLock=new();
    private static readonly HashSet<EnvironmentGenerationJob> Active=new();
    private static long _next;
    private Task? _task;
    private int _cancelled;
    private double _progress;
    public Resource? terrain {get;private set;}
    public Resource? mesh {get;private set;}
    public long task_id {get;private set;}=-1;
    public double elapsed_ms {get;private set;}
    public string error {get;private set;}="";
    public void cancel()=>Interlocked.Exchange(ref _cancelled,1);
    public bool cancelled()=>Volatile.Read(ref _cancelled)!=0;
    public double progress()=>Volatile.Read(ref _progress);
    public void _set_progress(double value)=>Volatile.Write(ref _progress,value);
    public bool complete()=>task_id>=0&&_task?.IsCompleted==true;
    public void collect(){var task=_task;if(task!=null)task.GetAwaiter().GetResult();_task=null;task_id=-1;}
    internal static void CancelAndJoinActive()
    {EnvironmentGenerationJob[] jobs;lock(ActiveLock){jobs=new EnvironmentGenerationJob[Active.Count];Active.CopyTo(jobs);}foreach(var job in jobs)job.cancel();foreach(var job in jobs)job.collect();}
    public void start(Resource source,Settings settings,bool resetEdits)
    {
        terrain=source.Duplicate(true);foreach(var pair in settings)
        {
            string key=pair.Key.AsString();if(key is "caves" or "erosion"){var typed=terrain.Get(key).AsGodotArray().Duplicate();typed.Clear();foreach(var value in pair.Value.AsGodotArray())typed.Add(value.As<Resource>().Duplicate(true));terrain.Set(key,typed);}
            else if(key is "dimensions" or "resolution" or "seed" or "geology" or "base_height" or "amplitude" or "frequency" or "generation" or "hydrology" or "biomes" or "voxel_height" or "voxel_cell_budget"){var value=pair.Value;terrain.Set(key,value.VariantType==Variant.Type.Object&&value.AsGodotObject() is Resource resource?Variant.From(resource.Duplicate(true)):value);}
        }
        if(resetEdits)terrain.Set("edits",Array.Empty<float>());task_id=Interlocked.Increment(ref _next);lock(ActiveLock)Active.Add(this);_task=Task.Run(Run);
    }
    private void Run()
    {
        var timer=Stopwatch.StartNew();var callback=Callable.From(cancelled);try
        {
            var surface=terrain!;surface.Call("prepare",callback);if(cancelled())return;if(!surface.Call("prepare_water",callback).AsBool()){error=surface.Get("water_status").AsString();return;}if(!surface.Call("prepare_biomes",callback).AsBool()){error=surface.Get("water_status").AsString();return;}_set_progress(.4);if(!surface.Call("prepare_volumes",callback,Callable.From<double>(value=>_set_progress(.4+value*.4))).AsBool()){error=surface.Get("volume_status").AsString();return;}if(!surface.Call("prepare_cave_biomes",callback).AsBool()){error=surface.Get("volume_status").AsString();return;}_set_progress(.8);mesh=surface.Call("editable_mesh",callback).As<Resource>();if(!surface.Call("prepare_geometry_keys",callback).AsBool()||cancelled())return;_set_progress(1);elapsed_ms=timer.Elapsed.TotalMilliseconds;
        }
        catch(Exception failure){error=failure.Message;GD.PushError(failure.ToString());}
        finally{lock(ActiveLock)Active.Remove(this);}
    }
}
