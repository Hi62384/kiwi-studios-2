using Godot;
using System;
public partial class ImageCanvasSelectionOperations
{
    private readonly ImageWarpInteractionOperations _warpInteraction=new();private readonly ImageRepairInteractionOperations _repairInteraction=new();
    private const string MaskShader="shader_type canvas_item;\nrender_mode unshaded;\nuniform float strength=0.65;\nuniform bool warped=false;\nuniform vec3 row0=vec3(1.0,0.0,0.0);\nuniform vec3 row1=vec3(0.0,1.0,0.0);\nuniform vec3 row2=vec3(0.0,0.0,1.0);\nvoid fragment(){\n vec2 sample_uv=UV;\n if(warped){vec3 p=vec3(UV,1.0); float w=dot(row2,p); sample_uv=abs(w)>0.000001 ? vec2(dot(row0,p),dot(row1,p))/w : vec2(-1.0);}\n float a=texture(TEXTURE,sample_uv).a;\n if(any(lessThan(sample_uv,vec2(0.0))) || any(greaterThan(sample_uv,vec2(1.0)))) a=0.0;\n float stripe=step(0.5,fract((FRAGCOORD.x+FRAGCOORD.y)/12.0));\n COLOR=vec4(vec3(stripe),a*strength);\n}";
    public void ready(Control canvas)
    {
        canvas.Get("warp_tool").AsGodotObject().Set("canvas",canvas);var smart=canvas.Get("smart_selection").As<Node>();canvas.AddChild(smart);smart.Connect("proposed",new Callable(canvas,"_smart_proposed"));smart.Connect("analyzed",Callable.From(()=>{canvas.Get("_edge_follower").AsGodotObject().Set("field",smart.Get("edges"));canvas.EmitSignal("hint_changed","Edge analysis ready");}));canvas.MouseFilter=Control.MouseFilterEnum.Stop;canvas.FocusMode=Control.FocusModeEnum.All;canvas.ClipContents=true;canvas.TextureFilter=CanvasItem.TextureFilterEnum.Linear;canvas.Material=new CanvasItemMaterial{BlendMode=CanvasItemMaterial.BlendModeEnum.PremultAlpha};canvas.Connect("gui_input",new Callable(canvas,"_input_canvas"));canvas.MouseExited+=canvas.QueueRedraw;
        var overlay=canvas.Get("_selection_overlay").As<TextureRect>();overlay.MouseFilter=Control.MouseFilterEnum.Ignore;overlay.ExpandMode=TextureRect.ExpandModeEnum.IgnoreSize;overlay.TextureFilter=CanvasItem.TextureFilterEnum.Nearest;overlay.Material=new ShaderMaterial{Shader=new Shader{Code=MaskShader}};canvas.AddChild(overlay);overlay.Hide();canvas.Resized+=()=>sync_selection_overlay(canvas);
    }
    public void process(Control canvas,double delta)
    {
        string tool=canvas.Get("tool").AsString();if(tool=="warp")_warpInteraction.process(canvas.Get("warp_tool").As<RefCounted>(),delta);if(tool=="repair")_repairInteraction.process(canvas.Get("repair_tool").As<RefCounted>());if(canvas.Get("_drag").AsString()=="paint"&&canvas.Get("_corrector").AsGodotObject()!=null)flush_corrected_stroke(canvas);flush_edge_motion(canvas);
        if(canvas.Get("_edge_hover_pending").AsBool()){canvas.Set("_edge_hover_pending",false);var edges=canvas.Get("smart_selection").AsGodotObject().Get("edges").AsGodotObject();if(canvas.Get("_drag").AsString().Length==0&&tool=="pixel_select"&&canvas.Get("edge_magnet").AsBool()&&edges!=null){var kernel=edges.Get("_kernel").As<PixelEdgeFieldKernel>();int ridge=kernel.nearest(to_document(canvas,canvas.Get("_mouse").AsVector2()),canvas.Get("edge_threshold").AsDouble(),-1,Vector2.Zero);canvas.Set("_edge_preview",ridge>=0?kernel.refine(ridge):Vector2.Inf);canvas.QueueRedraw();}}
        sync_selection_overlay(canvas);if(tool!="pixel_select"||!canvas.Get("edge_magnet").AsBool())canvas.Set("_edge_preview",Vector2.Inf);
    }
}
