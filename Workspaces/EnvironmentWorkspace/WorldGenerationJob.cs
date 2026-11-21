using Godot;
using Settings=Godot.Collections.Dictionary;

public partial class WorldGenerationJob : WorldWorkerJob
{
    public EnvironmentGenerationJob? terrain_job {get;set;}
    public Settings terrain_plan {get;set;}=new();
    protected override void CancelChildren()=>terrain_job?.cancel();
    public void start(Resource source,Settings plan,Resource? development)
    {
        terrain_plan=plan;if(plan.ContainsKey("settings")){terrain_job=new EnvironmentGenerationJob();terrain_job.start(plan["source"].As<Resource>(),plan["settings"].AsGodotDictionary(),false);}var generator=new RoadNetworkOperations();Begin(()=>generator.Generate(source,cancelled,development),"World generation");
    }
    public override bool complete()=>base.complete()&&(terrain_job==null||terrain_job.complete());
    public override Settings collect()
    {
        base.collect();if(terrain_job!=null){terrain_job.collect();if(terrain_job.cancelled())result["cancelled"]=true;else if(terrain_job.error.Length>0){result["document"]=default;result["errors"]=new[]{terrain_job.error};}else result["terrain_result"]=new Settings {["id"]=terrain_plan["id"],["terrain"]=terrain_job.terrain!=null?Variant.From(terrain_job.terrain):default,["mesh"]=terrain_job.mesh!=null?Variant.From(terrain_job.mesh):default};}if(cancelled())result["cancelled"]=true;return result;
    }
}
