using Godot;
using Settings=Godot.Collections.Dictionary;
public partial class TransformImageActorOperations:RefCounted
{
    private readonly ActorTransformationStateOperations _states=new();
    private Settings Asset(Node3D owner)=>_states.load_asset(ActorTransformationStates.Assets,owner.Get("actor").As<Resource>());
    public void ready(Node3D owner)
    {
        var renderer=owner.Get("renderer").As<Node>();owner.AddChild(renderer);renderer.Get("cache").AsGodotObject().Connect("prepared",Callable.From(()=>{if(GodotObject.IsInstanceValid(owner)&&owner.Get("active").AsBool())owner.Call("evaluate",owner.Get("_time"),owner.Get("_values"));}));var material=owner.Get("premultiplied").As<ShaderMaterial>();material.Shader=new Shader{Code="shader_type canvas_item; render_mode unshaded,blend_premul_alpha; void fragment(){COLOR=texture(TEXTURE,UV);}"};owner.Get("visual").As<Node2D>().Material=material;
    }
    public void set_active(Node3D owner,bool active)=>owner.Get("renderer").AsGodotObject().Get("viewport").As<SubViewport>().RenderTargetUpdateMode=active?SubViewport.UpdateMode.Always:SubViewport.UpdateMode.Disabled;
    public void evaluate_transform(Node3D owner,Settings values){var document=Asset(owner)["document"].As<Resource>();var session=owner.Get("session").AsGodotObject();if(document!=null&&session.Get("document").AsGodotObject()!=document){owner.Get("renderer").AsGodotObject().Call("clear_views");session.Set("document",document);}}
    public void evaluate(Node3D owner,double time,Settings values)
    {
        var asset=Asset(owner);var document=asset["document"].As<Resource>();var renderer=owner.Get("renderer").AsGodotObject();var visual=owner.Get("visual").As<Node2D>();if(document==null){visual.Set("texture",default(Variant));if(renderer.Get("views").AsGodotDictionary().Count>0)renderer.Call("clear_views");return;}var session=owner.Get("session").AsGodotObject();if(session.Get("document").AsGodotObject()!=document){renderer.Call("clear_views");session.Set("document",document);}renderer.Call("sync",session,time,_states.samples(owner.Get("actor").As<Resource>(),document,time,values));visual.Set("texture",renderer.Call("texture"));visual.Material=owner.Get("premultiplied").As<ShaderMaterial>();visual.QueueRedraw();
    }
}
