using Godot;
using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class TerrainSliceJob : RefCounted
{
    private static readonly object ActiveLock=new();
    private static readonly HashSet<TerrainSliceJob> Active=new();
    private static long _next;
    private Task? _task;
    private int _stopped;
    public Resource? terrain {get;private set;}
    public double height {get;private set;}
    public byte[] pixels {get;private set;}=Array.Empty<byte>();
    public long task {get;private set;}=-1;
    public string error {get;private set;}="";
    public void cancel()=>Interlocked.Exchange(ref _stopped,1);
    public bool canceled()=>Volatile.Read(ref _stopped)!=0;
    public bool complete()=>task>=0&&_task?.IsCompleted==true;
    public void collect(){var pending=_task;if(pending!=null)pending.GetAwaiter().GetResult();_task=null;task=-1;}
    internal static void CancelAndJoinActive()
    {TerrainSliceJob[] jobs;lock(ActiveLock){jobs=new TerrainSliceJob[Active.Count];Active.CopyTo(jobs);}foreach(var job in jobs)job.cancel();foreach(var job in jobs)job.collect();}
    public void start(Resource source,double y)
    {
        terrain=source.Duplicate(false);terrain.Set("edits",source.Get("edits").AsFloat32Array());terrain.Set("volume_chunks",new Settings());var generation=source.Get("generation").As<Resource>();terrain.Set("generation",generation!=null?Variant.From(generation.Duplicate(true)):default);
        foreach(string name in new[]{"erosion","caves"}){var original=source.Get(name).AsGodotArray();var copies=original.Duplicate();copies.Clear();foreach(var value in original)copies.Add(value.As<Resource>().Duplicate(true));terrain.Set(name,copies);}
        height=y;task=Interlocked.Increment(ref _next);lock(ActiveLock)Active.Add(this);_task=Task.Run(Run);
    }
    private void Run()
    {
        try
        {
            var source=terrain!;source.Call("prepare",Callable.From(canceled));if(canceled())return;
            using var sampler=new TerrainVolumeMesher();var caves=new GArray();var bounds=new GArray();using var operations=new TerrainCaveOperations();
            foreach(var value in source.Get("caves").AsGodotArray()){var cave=value.As<Resource>();if(!cave.Get("enabled").AsBool())continue;operations.prepare(cave);caves.Add(cave);bounds.Add(operations.bounds(cave));}sampler.configure(source,caves,bounds);
            var output=new byte[96*96*4];var dimensions=source.Get("dimensions").AsVector2();double boundary=Math.Max(.05,source.Get("voxel_height").AsDouble()*.3);var solid=new Color("ba9568");var air=new Color("3fbbb4");var line=new Color("ecf5f0");
            for(int z=0;z<96;z++)for(int x=0;x<96;x++)
            {
                if(x%8==0&&canceled())return;var point=new Vector3((float)((x/95.0-.5)*dimensions.X),(float)height,(float)((z/95.0-.5)*dimensions.Y));double distance=sampler.density(point);var color=(distance<0?solid:air).Lerp(line,(float)(1-Mathf.SmoothStep(0.0,boundary,Math.Abs(distance))));int index=(x+z*96)*4;
                output[index]=(byte)Math.Round(color.R*255,MidpointRounding.AwayFromZero);output[index+1]=(byte)Math.Round(color.G*255,MidpointRounding.AwayFromZero);output[index+2]=(byte)Math.Round(color.B*255,MidpointRounding.AwayFromZero);output[index+3]=255;
            }
            pixels=output;
        }
        catch(Exception failure){error=failure.Message;GD.PushError(failure.ToString());}
        finally{lock(ActiveLock)Active.Remove(this);}
    }
}
