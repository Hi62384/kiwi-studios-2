using Godot;
using System;
using System.Threading.Tasks;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class TerrainBakeJob : Node
{
    [Signal] public delegate void completedEventHandler(Variant result);
    private RefCounted? _state;
    private Node? _owner;
    private bool _running;
    private readonly ModelImport _import=new();
    private readonly TerrainBakeOperations _materials=new();
    private static Variant ObjectValue(GodotObject? value)=>value!=null?Variant.From(value):default;
    private bool Live()=>_running&&GodotObject.IsInstanceValid(_owner)&&_owner!.IsInsideTree()&&!_owner.IsQueuedForDeletion()&&_state!=null&&!_state.Get("cancelled").AsBool();
    public void start(RefCounted state,Node3D runtime,string id,Node owner,bool includeWater)
    {if(_running)return;_state=state;_owner=owner;_running=true;_ = Run(runtime,id,includeWater,GetTree());}
    private void Finish(Resource? output)
    {if(!_running)return;_running=false;EmitSignal(SignalName.completed,output!=null?Variant.From(output):default);_state=null;_owner=null;if(IsInsideTree())QueueFree();}
    public override void _ExitTree(){Finish(null);}
    private async Task Run(Node3D runtime,string id,bool includeWater,SceneTree tree)
    {
        Resource? output=null;
        try
        {
            await ToSignal(tree,SceneTree.SignalName.ProcessFrame);if(!Live()||!GodotObject.IsInstanceValid(runtime))return;
            _state!.Set("error", "");_state.Set("progress",0.0);var document=runtime.Get("document").As<Resource>();var source=document?.Call("terrain",id).As<Resource>();
            if(document==null||source==null){_state.Set("error","Choose a terrain component.");return;}
            source=source.Duplicate(true);var item=document.Call("component",id).As<Resource>();var pose=document.Call("world_transform",item).AsTransform3D();var metadata=document.Get("component_settings").AsGodotDictionary()[id].AsGodotDictionary();
            output=new KiwiModelDocument();var group=new KiwiModelComponent();
            group.Set("id",Guid.NewGuid().ToString("N"));group.Set("title",item.Get("title"));group.Set("transform",pose);output.Get("components").AsGodotArray().Add(group);
            foreach(string method in new[]{"water_valid","biomes_valid","volumes_valid","cave_biomes_valid"})if(!source.Call(method).AsBool()){_state.Set("error","Finish terrain generation before baking.");output=null;return;}
            var nodes=runtime.Get("nodes").AsGodotDictionary();var root=nodes.TryGetValue(id,out var rootValue)?rootValue.As<Node3D>():null;
            var assets=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/environment_assets.gd");var ground=assets.Call("material",metadata.TryGetValue("material",out var groundValue)?groundValue:default).As<Material>()??runtime.Get("default_ground").As<Material>();
            var paint=assets.Call("material",metadata.TryGetValue("paint_material",out var paintValue)?paintValue:default).As<Material>();Material? blended=null;
            if(root!=null)
            {
                blended=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/terrain/terrain_biome_render.gd").Call("material",root,source,ground,paint).As<Material>();
                blended??=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/terrain/terrain_paint_render.gd").Call("material",root,source,ground,paint).As<Material>();
            }
            var first=_materials.freeze(blended??ground);var second=blended!=null?first:_materials.freeze(paint??ground);
            int side=(int)Math.Ceiling((source.Get("resolution").AsDouble()-1)/32.0),completed=0;
            for(int z=0;z<side;z++)for(int x=0;x<side;x++)
            {
                if(!Live()){output=null;return;}
                var mesh=source.Call("chunk_mesh",new Vector2I(x,z),false,blended!=null).As<Mesh>();
                if(mesh.GetSurfaceCount()>0)
                {
                    var baked=_import._add_mesh(output,mesh,Transform3D.Identity,$"Terrain {x} · {z}");baked.Set("parent_id",group.Get("id"));var slots=mesh.GetMeta("environment_material_slots",Array.Empty<int>()).AsInt32Array();var surfaces=baked.Get("surface_materials").AsGodotArray();surfaces.Clear();
                    for(int surface=0;surface<mesh.GetSurfaceCount();surface++)surfaces.Add(ObjectValue(surface<slots.Length&&slots[surface]==1?second:first));
                    var geometry=baked.Get("geometry_source").As<Mesh>();foreach(string name in new[]{"kiwi_terrain_collision","environment_lods"})if(geometry.HasMeta(name))geometry.RemoveMeta(name);
                }
                completed++;_state!.Set("progress",(double)completed/(side*side));await ToSignal(tree,SceneTree.SignalName.ProcessFrame);
            }
            if(!Live()){output=null;return;}
            if(includeWater&&GodotObject.IsInstanceValid(root)&&root?.GetNodeOrNull<MeshInstance3D>("Water") is MeshInstance3D water&&water.Mesh!=null)
            {var baked=_import._add_mesh(output,water.Mesh,Transform3D.Identity,"Water surface");baked.Set("parent_id",group.Get("id"));var surfaces=baked.Get("surface_materials").AsGodotArray();surfaces.Clear();surfaces.Add(ObjectValue(_materials.freeze(water.MaterialOverride)));}
            var errors=output.Call("validate").AsStringArray();if(errors.Length>0){_state!.Set("error",errors[0]);output=null;}
        }
        catch(Exception failure){if(_state!=null)_state.Set("error",failure.Message);GD.PushError(failure.ToString());output=null;}
        finally{Finish(output);}
    }
}
