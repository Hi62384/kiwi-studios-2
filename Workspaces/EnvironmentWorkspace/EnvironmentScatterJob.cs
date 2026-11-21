using Godot;
using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using Settings=Godot.Collections.Dictionary;

public partial class EnvironmentScatterJob : RefCounted
{
    private static readonly object ActiveLock=new();
    private static readonly HashSet<EnvironmentScatterJob> Active=new();
    private static long _next;
    private Task? _task;
    private int _cancelled;
    public Resource? source {get;private set;}
    public Resource? terrain {get;private set;}
    public Settings result {get;private set;}=new();
    public long task_id {get;private set;}=-1;
    public void cancel()=>Interlocked.Exchange(ref _cancelled,1);
    public bool cancelled()=>Volatile.Read(ref _cancelled)!=0;
    public bool complete()=>task_id>=0&&_task?.IsCompleted==true;
    public void collect(){var pending=_task;if(pending!=null)pending.GetAwaiter().GetResult();_task=null;task_id=-1;}
    internal static void CancelAndJoinActive()
    {EnvironmentScatterJob[] jobs;lock(ActiveLock){jobs=new EnvironmentScatterJob[Active.Count];Active.CopyTo(jobs);}foreach(var job in jobs)job.cancel();foreach(var job in jobs)job.collect();}
    public void start(Resource rules,Resource surface)
    {source=rules.Duplicate(true);terrain=surface.Duplicate(true);task_id=Interlocked.Increment(ref _next);lock(ActiveLock)Active.Add(this);_task=Task.Run(Run);}
    private void Run()
    {
        var state=new Settings {["enabled"]=true,["callback"]=Callable.From(cancelled)};
        try
        {
            terrain!.Call("prepare",state["callback"]);
            if(cancelled()){result=new Settings {["batches"]=new Settings(),["count"]=0,["error"]="Generation canceled."};return;}
            using var operations=new EnvironmentScatterOperations();result=operations.generate(source!,terrain,state);
        }
        catch(Exception failure){result=new Settings {["batches"]=new Settings(),["count"]=0,["error"]=failure.Message};GD.PushError(failure.ToString());}
        finally{state.Clear();lock(ActiveLock)Active.Remove(this);}
    }
}
