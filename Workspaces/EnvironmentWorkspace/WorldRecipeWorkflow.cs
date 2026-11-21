using Godot;
using System;
using Settings=Godot.Collections.Dictionary;

public partial class WorldRecipeOperations
{
    private static long SessionKey(RefCounted session)=>unchecked((long)session.GetInstanceId());
    private static Settings Pending(Settings pending,RefCounted session)=>pending.TryGetValue(SessionKey(session),out var value)?value.AsGodotDictionary():new Settings();
    private static Resource Document(RefCounted session)=>session.Get("document").As<Resource>();
    private static void Status(Control workspace,string text)=>workspace.Get("status").As<Label>().Text=text;
    public bool same_workspace(Control? workspace,RefCounted session)=>workspace!=null&&GodotObject.IsInstanceValid(workspace)&&workspace.IsInsideTree()&&workspace.Get("session").As<RefCounted>()==session;
    private static bool Current(RefCounted session,Settings state)=>Document(session)==state["document"].As<Resource>()&&session.Get("revision").AsInt64()==state["revision"].AsInt64();
    public bool can_start(Control workspace,RefCounted session,Settings pending)
    {if(!pending.ContainsKey(SessionKey(session)))return true;Status(workspace,"Finish or cancel the current world preset first.");return false;}
    public void cancel(RefCounted session,Settings pending)
    {var state=Pending(pending,session);if(state.Count==0)return;state["cancelled"]=true;var job=state["job"].AsGodotObject();if(job is EnvironmentGenerationJob terrain)terrain.cancel();else if(job is WorldRecipeJob recipe)recipe.cancel();}
    public Settings begin_recipe(Control workspace,RefCounted session,string id,string name,Settings pending,Settings callback,Settings presets,Settings species)
    {
        var document=Document(session);var worlds=new WorldSessionOperations();var authored=worlds.source(document.Call("component",id).As<Resource>());
        if(authored==null||authored.Get("terrain_id").AsString().Length==0||authored.Get("terrain_id").AsString()!=authored.Get("owned_terrain_id").AsString()){Status(workspace,"Presets need an empty world with its own terrain; external terrain is preserved.");return new Settings();}
        var recipe=configure(authored,name,presets,species);string error=recipe["error"].AsString();if(error.Length>0){Status(workspace,error);return new Settings();}
        var bridge=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/world/world_recipes.gd");if(bridge.Call("_has_cancel",session).AsBool()||session.Get("_gesture").AsGodotDictionary().Count>0){Status(workspace,"Finish the current edit before generating a world preset.");return new Settings();}
        string terrainId=authored.Get("terrain_id").AsString();var ground=session.Call("environment").As<Resource>().Call("terrain",terrainId).As<Resource>();if(ground==null){Status(workspace,"The world's owned terrain is missing.");return new Settings();}
        if(!document.Call("editable_component",document.Call("component",id)).AsBool()||!document.Call("editable_component",document.Call("component",terrainId)).AsBool()){Status(workspace,"Unlock the world and its terrain before generating a preset.");return new Settings();}
        var terrainJob=new EnvironmentGenerationJob();var state=new Settings {["job"]=terrainJob,["terrain_job"]=terrainJob,["document"]=document,["revision"]=session.Get("revision"),["success"]=false,["cancelled"]=false,["was_dirty"]=session.Get("dirty"),["finished"]=false,["phase"]="terrain",["authored"]=authored,["recipe"]=recipe,["id"]=id,["name"]=name,["error"]="",["generated"]=new Settings(),["cancel_callback"]=callback["callback"]};pending[SessionKey(session)]=state;session.Set("pending_source_cancel",callback["callback"]);session.Set("dirty",true);workspace.SetMeta("world_recipe_job",terrainJob);terrainJob.start(ground,recipe["terrain_settings"].AsGodotDictionary(),true);Status(workspace,"Generating "+name+" terrain…");return state;
    }
    public void poll_recipe(Control? workspace,RefCounted session,Settings state,Settings pending)
    {
        if(Get(state,"finished",false).AsBool())return;if(!same_workspace(workspace,session)||!Current(session,state))cancel(session,pending);
        if(state["phase"].AsString()=="terrain")
        {
            var terrainJob=state["terrain_job"].As<EnvironmentGenerationJob>();if(terrainJob.task_id>=0&&!terrainJob.complete())return;terrainJob.collect();state["error"]=terrainJob.error;
            if(state["cancelled"].AsBool()||terrainJob.error.Length>0){FinishRecipe(workspace,session,state,pending);return;}
            var authored=state["authored"].As<Resource>();var staged=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/environment_session.gd").New().As<RefCounted>();staged.Set("document",session.Call("environment").As<Resource>().Call("snapshot"));var environment=staged.Call("environment").As<Resource>();var terrainId=authored.Get("terrain_id");environment.Get("component_settings").AsGodotDictionary()[terrainId].AsGodotDictionary()["terrain"]=terrainJob.terrain!=null?Variant.From(terrainJob.terrain):default;Document(staged).Call("component",terrainId).As<Resource>().Set("mesh",terrainJob.mesh!=null?Variant.From(terrainJob.mesh):default);var desired=state["recipe"].AsGodotDictionary()["source"].As<Resource>();
            var field=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/world/world_terrain_field.gd").Call("capture",staged,state["id"],desired).AsGodotDictionary();string error=field["error"].AsString();state["error"]=error;
            if(error.Length==0){desired.Set("terrain_field",field["field"]);desired.Set("terrain_dependency_key",field["field"].As<RefCounted>().Get("key"));error=new WorldPlacementOperations().capture(session,state["id"].AsString(),desired);state["error"]=error;}
            if(error.Length>0){FinishRecipe(workspace,session,state,pending);return;}var job=new WorldRecipeJob();state["job"]=job;state["staged"]=staged;state["phase"]="layout";workspace!.SetMeta("world_recipe_job",job);Status(workspace!,"Placing settlements and generating "+state["name"].AsString()+"…");job.start(desired);return;
        }
        var recipeJob=state["job"].As<WorldRecipeJob>();if(recipeJob.task>=0&&!recipeJob.complete())return;var generated=recipeJob.collect();state["generated"]=generated;
        if(!state["cancelled"].AsBool()&&!Get(generated,"cancelled",false).AsBool()&&Get(generated,"document").AsGodotObject()!=null&&generated["errors"].AsStringArray().Length==0)
        {
            var desired=recipeJob.authored!;generated["signature"]=new WorldSourceOperations().signature(desired);generated["document"].As<Resource>().Call("component",state["id"]).As<Resource>().Get("parameters").AsGodotDictionary()["world_recipe"]=state["name"];var terrainJob=state["terrain_job"].As<EnvironmentGenerationJob>();generated["terrain_result"]=new Settings {["id"]=state["authored"].As<Resource>().Get("terrain_id"),["terrain"]=terrainJob.terrain!=null?Variant.From(terrainJob.terrain):default,["mesh"]=terrainJob.mesh!=null?Variant.From(terrainJob.mesh):default};session.Set("pending_source_cancel",default(Callable));var applied=new WorldSessionOperations().update(session,state["id"].AsString(),desired,"Generate "+state["name"].AsString(),generated);state["generated"]=applied;state["success"]=applied["errors"].AsStringArray().Length==0;
        }
        FinishRecipe(workspace,session,state,pending);
    }
    private void FinishRecipe(Control? workspace,RefCounted session,Settings state,Settings pending)
    {
        pending.Remove(SessionKey(session));GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/world/world_recipes.gd").Call("_clear_cancel",session,state);if(!state["success"].AsBool()&&Current(session,state))session.Set("dirty",state["was_dirty"]);state["finished"]=true;if(!same_workspace(workspace,session))return;workspace!.RemoveMeta("world_recipe_job");
        string error=state["error"].AsString();var generated=state["generated"].AsGodotDictionary();if(state["cancelled"].AsBool())Status(workspace!,"World preset canceled; the previous terrain and world are intact.");else if(error.Length>0)Status(workspace!,error);else if(Get(generated,"errors",Array.Empty<string>()).AsStringArray().Length>0)Status(workspace!,generated["errors"].AsStringArray()[0]);else{var warnings=Get(generated,"warnings",Array.Empty<string>()).AsStringArray();Status(workspace!,warnings.Length>0?string.Join(" · ",warnings):state["name"].AsString()+" generated");workspace!.Get("canvas").As<Control>().Call("frame",true);}
    }
}
