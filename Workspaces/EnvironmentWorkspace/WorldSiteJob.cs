using Godot;
using System;
using Settings=Godot.Collections.Dictionary;

public partial class WorldSiteJob : WorldWorkerJob
{
    private readonly WorldSiteOperations _sites=new();
    protected override Settings Failure(Exception error)=>new() {["error"]=error.Message};
    public void start(Resource source,int index)
    {Begin(()=>_sites.Find(source,index,cancelled),"Find settlement site");}
    public override bool complete()=>task_id<0||base.complete();
}
