using Godot;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;

public partial class WorldRecipeJob : WorldWorkerJob
{
    private readonly WorldSiteOperations _sites=new();
    public Resource? authored {get;set;}
    public long task {get=>task_id;set=>task_id=value;}
    public bool stopped {get=>cancelled();set=>SetCancelled(value);}
    public void start(Resource source)
    {authored=source.Call("copy").As<Resource>();Begin(Generate,"World recipe layout");}
    private Settings Generate()
    {
        var warnings=new List<string>();var settlements=authored!.Get("settlements").AsGodotArray();for(int index=0;index<settlements.Count;index++)
        {
            if(cancelled())return new Settings {["cancelled"]=true};var site=_sites.Find(authored,index,cancelled);if(site.TryGetValue("cancelled",out var stop)&&stop.AsBool())return new Settings {["cancelled"]=true};var settlement=settlements[index].AsGodotDictionary();string error=site["error"].AsString();if(error.Length>0){warnings.Add(settlement["name"].AsString()+": "+error);settlement["enabled"]=false;continue;}var previous=settlement["center"].AsVector3();var next=site["position"].AsVector3();settlement["center"]=next;if(settlement.TryGetValue("districts",out var districts))foreach(var value in districts.AsGodotArray()){var district=value.AsGodotDictionary();var polygon=district["polygon"].AsVector2Array();for(int point=0;point<polygon.Length;point++)polygon[point]+=new Vector2(next.X-previous.X,next.Z-previous.Z);district["polygon"]=polygon;}
        }
        var output=new RoadNetworkOperations().Generate(authored,cancelled);if(!output.TryGetValue("cancelled",out var cancelledValue)||!cancelledValue.AsBool()){var all=new List<string>(output["warnings"].AsStringArray());all.AddRange(warnings);output["warnings"]=all.ToArray();}return output;
    }
    public void _run()=>result=Generate();
}
