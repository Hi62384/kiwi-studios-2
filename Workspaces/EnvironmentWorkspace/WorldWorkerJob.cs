using Godot;
using System;
using System.Collections.Generic;
using System.Threading;
using Settings=Godot.Collections.Dictionary;

/// <summary>Native cancellation/lifetime boundary for bounded Godot worker-pool jobs.</summary>
public partial class WorldWorkerJob : RefCounted
{
    private static readonly object ActiveLock=new();
    private static readonly HashSet<WorldWorkerJob> Active=new();
    private int _cancelled;
    private Callable _callback;
    public Settings result {get;protected set;}=new();
    public long task_id {get;protected set;}=-1;
    protected virtual void CancelChildren(){}
    public void cancel(){Interlocked.Exchange(ref _cancelled,1);CancelChildren();}
    public bool cancelled()=>Volatile.Read(ref _cancelled)!=0;
    protected void SetCancelled(bool value)=>Interlocked.Exchange(ref _cancelled,value?1:0);
    protected virtual Settings Failure(Exception error)=>new() {["document"]=default,["errors"]=new[]{error.Message},["warnings"]=Array.Empty<string>()};
    protected void Begin(Func<Settings> worker,string label)
    {
        if(task_id>=0)throw new InvalidOperationException("Collect the previous world job before starting another one.");lock(ActiveLock)Active.Add(this);
        _callback=Callable.From(()=>{try{result=worker();}catch(Exception error){result=Failure(error);GD.PushError(error.ToString());}finally{lock(ActiveLock)Active.Remove(this);}});
        try{task_id=WorkerThreadPool.AddTask(_callback,false,label);}catch{lock(ActiveLock)Active.Remove(this);_callback=default;throw;}
    }
    public virtual bool complete()=>task_id>=0&&WorkerThreadPool.IsTaskCompleted(task_id);
    public virtual Settings collect(){if(task_id>=0){WorkerThreadPool.WaitForTaskCompletion(task_id);task_id=-1;}_callback=default;return result;}
    internal static void CancelAndJoinActive()
    {WorldWorkerJob[] jobs;lock(ActiveLock){jobs=new WorldWorkerJob[Active.Count];Active.CopyTo(jobs);}foreach(var job in jobs)job.cancel();foreach(var job in jobs)job.collect();}
}
