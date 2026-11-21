using Godot;
using System;
using System.Threading.Tasks;

public partial class TransformationFlattenJob : Node
{
    [Signal] public delegate void completedEventHandler();
    public bool finished;
    public Image? result;
    public async void Start(Node owner)
    {
        SubViewport? output=null;
        try{var source=owner.Get("viewport").As<SubViewport>();output=new SubViewport {World2D=new World2D(),Size=source.Size,Disable3D=true,TransparentBg=true};owner.AddChild(output);var display=new TextureRect {Texture=source.GetTexture(),Size=(Vector2)output.Size};output.AddChild(display);var shader=new Shader {Code="shader_type canvas_item; render_mode unshaded,blend_disabled; void fragment(){vec4 c=texture(TEXTURE,UV);COLOR=vec4(c.rgb/max(c.a,.00001),c.a);}"};display.Material=new ShaderMaterial {Shader=shader};output.RenderTargetUpdateMode=SubViewport.UpdateMode.Always;for(int index=0;index<3;index++){await ToSignal(Engine.GetSingleton("RenderingServer"),RenderingServer.SignalName.FramePostDraw);if(!GodotObject.IsInstanceValid(owner)||!GodotObject.IsInstanceValid(output)||!owner.IsInsideTree())return;}result=output.GetTexture().GetImage();}
        catch(Exception error){GD.PushError("Transformation image readback failed: "+error.Message);}
        finally{if(GodotObject.IsInstanceValid(output))output!.QueueFree();finished=true;if(GodotObject.IsInstanceValid(this)){EmitSignal(SignalName.completed);QueueFree();}}
    }
}
public partial class TransformationRendererOperations
{
    public TransformationFlattenJob flatten(Node owner){var job=new TransformationFlattenJob();owner.AddChild(job);job.Start(owner);return job;}
}
