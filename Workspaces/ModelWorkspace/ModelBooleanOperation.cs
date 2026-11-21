using Godot;
using System;
using System.Threading.Tasks;

public partial class ModelBooleanOperation : Node
{
    [Signal] public delegate void completedEventHandler();
    public Resource? result {get;private set;}
    private readonly ModelMeshOperations _mesh=new();
    private CsgCombiner3D? _root;
    private bool _running;
    private bool Live()=>GodotObject.IsInstanceValid(this)&&IsInsideTree()&&!IsQueuedForDeletion();
    private void Finish(Resource? value)
    {if(!_running)return;_running=false;result=value;if(GodotObject.IsInstanceValid(this))EmitSignal(SignalName.completed);}
    public override void _ExitTree(){Finish(null);_mesh.Dispose();}
    public bool start(Resource a,Resource b,Transform3D transform,int operation,Godot.Collections.Array<Material> aMaterials,Godot.Collections.Array<Material> bMaterials)
    {
        if(_running||!Live())return false;Resource? first=null;Resource? second=null;
        try{first=_mesh.copy_mesh(a);second=_mesh.copy_mesh(b);_running=true;_ = Run(first,second,transform,operation,new Godot.Collections.Array<Material>(aMaterials),new Godot.Collections.Array<Material>(bMaterials),GetTree());return true;}
        catch(Exception error){first?.Dispose();second?.Dispose();GD.PushError(error.ToString());return false;}
    }
    private async Task Run(Resource a,Resource b,Transform3D transform,int operation,Godot.Collections.Array<Material> aMaterials,Godot.Collections.Array<Material> bMaterials,SceneTree tree)
    {
        try
        {
            // Yield before emitting completion so the caller can subscribe, even on error.
            await ToSignal(tree,SceneTree.SignalName.ProcessFrame);if(!Live()){Finish(null);return;}
            _root=new CsgCombiner3D{CalculateTangents=false,Visible=false};AddChild(_root);
            _root.AddChild(new CsgMesh3D{Mesh=_mesh.render_mesh(a,aMaterials)});
            _root.AddChild(new CsgMesh3D{Mesh=_mesh.render_mesh(b,bMaterials),Transform=transform,Operation=(CsgShape3D.OperationEnum)operation});
            for(int frame=0;frame<3;frame++){await ToSignal(tree,SceneTree.SignalName.ProcessFrame);if(!Live()){Finish(null);return;}}
            var baked=_root.BakeStaticMesh();if(baked==null||baked.GetSurfaceCount()==0){Finish(null);return;}
            var mesh=_mesh.from_mesh(baked);var materials=new Godot.Collections.Array<Material>();for(int surface=0;surface<baked.GetSurfaceCount();surface++)materials.Add(baked.SurfaceGetMaterial(surface));mesh.SetMeta("boolean_materials",materials);Finish(mesh);
        }
        catch(Exception error){if(GodotObject.IsInstanceValid(this)){GD.PushError(error.ToString());Finish(null);}}
        finally{a.Dispose();b.Dispose();if(_root!=null&&GodotObject.IsInstanceValid(_root))_root.QueueFree();_root=null;}
    }
}
