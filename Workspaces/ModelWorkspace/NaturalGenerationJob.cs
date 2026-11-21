using Godot;
using System;
using System.Linq;
using System.Threading;
using System.Collections.Concurrent;
using Settings=Godot.Collections.Dictionary;

public partial class NaturalGenerationJob : RefCounted
{
    private static long _sequence;
    private static readonly ConcurrentDictionary<long,NaturalGenerationJob> Active=new();
    private readonly ModelNaturalGenerator _generator=new();
    private readonly object _resultLock=new();
    private Settings _result=new();
    private int _cancelled;
    public Settings result {get{lock(_resultLock)return _result;}set{lock(_resultLock)_result=value;}}
    public long task_id {get;set;}=-1;
    public void cancel()=>Interlocked.Exchange(ref _cancelled,1);
    public bool cancelled()=>Volatile.Read(ref _cancelled)!=0;
    public void start(string kind,Settings parameters)
    {
        if(task_id>=0)throw new InvalidOperationException("Collect the previous natural generation task before starting another.");
        var snapshot=parameters.Duplicate(true);long id=Interlocked.Increment(ref _sequence);Active[id]=this;
        try{task_id=WorkerThreadPool.AddTask(Callable.From(()=>Run(kind,snapshot,id)),false,"Natural object generation");}
        catch{Active.TryRemove(id,out _);throw;}
    }
    private void Run(string kind,Settings snapshot,long id)
    {
        try{result=_generator.Generate(kind,snapshot,cancelled);}
        catch(Exception error){result=new Settings{["error"]=error.Message,["cancelled"]=cancelled()};GD.PushError(error.ToString());}
        finally{Active.TryRemove(id,out _);}
    }
    public bool complete()=>task_id>=0&&WorkerThreadPool.IsTaskCompleted(task_id);
    public Settings collect()
    {if(task_id>=0){WorkerThreadPool.WaitForTaskCompletion(task_id);task_id=-1;}return result;}
    public static void CancelAndJoinActive()
    {
        var jobs=Active.Values.Distinct().ToArray();foreach(var job in jobs)job.cancel();foreach(var job in jobs)job.collect();
    }
}
