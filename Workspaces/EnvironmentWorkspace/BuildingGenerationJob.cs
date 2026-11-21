using Godot;
using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using Settings=Godot.Collections.Dictionary;

public partial class BuildingGenerationJob : RefCounted
{
    private static readonly object ActiveLock=new();
    private static readonly HashSet<BuildingGenerationJob> Active=new();
    private static long _next;
    private Task? _task;
    private Resource? _source;
    private BuildingGeometryOperations? _builder;
    private int _cancelled;
    public Settings result {get;private set;}=new();
    public long task_id {get;private set;}=-1;
    public void cancel()=>Interlocked.Exchange(ref _cancelled,1);
    public bool cancelled()=>Volatile.Read(ref _cancelled)!=0;
    public bool complete()=>task_id>=0&&_task?.IsCompleted==true;
    public Settings collect(){var pending=_task;if(pending!=null)pending.GetAwaiter().GetResult();_task=null;task_id=-1;return result;}
    internal static void CancelAndJoinActive()
    {BuildingGenerationJob[] jobs;lock(ActiveLock){jobs=new BuildingGenerationJob[Active.Count];Active.CopyTo(jobs);}foreach(var job in jobs)job.cancel();foreach(var job in jobs)job.collect();}
    public void start(Resource source)
    {_source=source;_builder=new BuildingGeometryOperations();task_id=Interlocked.Increment(ref _next);lock(ActiveLock)Active.Add(this);_task=Task.Run(Run);}
    private void Run()
    {
        try{result=_builder!.Generate(_source!,cancelled);}
        catch(Exception failure){result=new Settings {["document"]=default,["errors"]=new[]{failure.Message},["warnings"]=Array.Empty<string>()};GD.PushError(failure.ToString());}
        finally{lock(ActiveLock)Active.Remove(this);}
    }
}
