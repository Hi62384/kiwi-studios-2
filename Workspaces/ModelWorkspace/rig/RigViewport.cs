using Godot;
using Settings=Godot.Collections.Dictionary;

public partial class RigViewport : RefCounted
{
    public Control canvas {get;set;}=null!;
    public RigEditor editor {get;set;}=null!;
    public Settings nodes {get;set;}=new();
    public Settings signatures {get;set;}=new();
    public Settings heat_signature {get;set;}=new();
    public string construction {get;set;}="Inside mesh";
    public double depth {get;set;}
    public double brush_radius {get;set;}=.3;
    public double brush_strength {get;set;}=.25;
    public double brush_value {get;set;}=1;
    public string brush_mode {get;set;}="Add";
    public bool paint_hidden {get;set;}
    public Variant chain {get;set;}
    public int chain_parent {get;set;}=-1;
    public bool placing {get;set;}
    public Vector3 cursor {get;set;}
    public Vector2 mouse {get;set;}
    public string drag {get;set;}="";
    public bool drag_end {get;set;}
    public int drag_axis {get;set;}=-1;
    public Vector3 drag_origin {get;set;}
    public Vector3 drag_point {get;set;}
    public Vector2 drag_mouse {get;set;}
    public Vector3 drag_normal {get;set;}=Vector3.Forward;
    public Godot.Collections.Array<Settings> drag_before {get;set;}=new();
    public Godot.Collections.Array<Vector3> drag_axes {get;set;}=new();
    public double drag_length {get;set;}=1;
    public Settings weight_before {get;set;}=new();
    public Settings weight_after {get;set;}=new();
    public Settings touched {get;set;}=new();
    public Settings geometry_cache {get;set;}=new();
    public Settings stroke_geometry {get;set;}=new();
    public long last_paint {get;set;}
    public Settings hover_hit {get;set;}=new();
    public bool compare_rest {get;set;}
    public RefCounted? stroke_session {get;set;}
    public string weight_tool {get;set;}="Brush";
    public bool selected_only {get;set;}
    public Settings region {get;set;}=new();
    public Vector2 region_start {get;set;}
    public bool region_additive {get;set;}
    private readonly RigViewportGeometry _geometry=new();
    private readonly RigViewportSync _sync=new();
    private readonly RigPaintGeometry _paint=new();
    private readonly RigViewportGestures _gestures=new();
    private readonly RigViewportOverlay _overlay=new();
    private readonly RigViewportInput _input=new();
    public void sync()
    {
        var active=editor.enabled?editor.rig():null;
        if(active!=null&&chain_parent>=active.Get("bones").AsGodotArray().Count){chain=default;chain_parent=-1;placing=false;}
        _sync.sync(canvas,editor,compare_rest,nodes,signatures,heat_signature,geometry_cache);
    }
    public Godot.Collections.Array<Transform3D> world_bones()=>_geometry.world_bones(canvas,editor,compare_rest);
    public Settings pick_bone(Vector2 point,bool jointsOnly)=>_geometry.pick_bone(canvas,editor,compare_rest,point,jointsOnly);
    public Variant plane_hit(Vector2 point,Vector3 origin,Vector3 normal)=>_geometry.plane_hit(canvas,point,origin,normal);
    public Vector3 placement(Vector2 point)=>_geometry.placement(canvas,editor,compare_rest,point,construction,depth);
    public Settings handles()=>_geometry.handles(canvas,editor,compare_rest);
    public int handle_at(Vector2 point,Settings geometry)=>_geometry.handle_at(canvas.Get("tool").AsString(),point,geometry);
    public void draw()=>_overlay.draw(canvas,editor,this);
    public void begin_joint(int index,bool end,Vector2 point)=>_gestures.begin_joint(canvas,editor,this,index,end,point);
    public bool begin_pose(int index,Vector2 point)=>_gestures.begin_pose(canvas,editor,this,index,point);
    public void update_drag(Vector2 point,bool snap)=>_gestures.update_drag(canvas,editor,this,point,snap);
    public Settings _paint_geometry(Resource item)=>_paint.geometry(item,editor.rig()!,compare_rest,drag=="weight",geometry_cache,stroke_geometry);
    public void paint(Vector2 point,bool subtract,bool force)=>_paint.paint(canvas,editor,this,point,subtract,force);
    public void finish(bool cancel)=>_gestures.finish(canvas,this,cancel);
    public bool handle_event(InputEvent input)=>_input.handle_event(canvas,editor,this,input);
    public void select_region(Rect2 rect,bool additive)=>_paint.select_region(canvas,editor,this,rect,additive);
    public void fill_region()=>editor.fill_region(region,brush_value);
    public void release()
    {
        // A managed editor must not keep an entire GDScript document graph alive
        // until Godot has already unloaded those scripts during engine shutdown.
        stroke_session=null;chain=default;drag="";
        if(editor!=null)editor.session=null;
        editor=null!;canvas=null!;
        nodes.Clear();signatures.Clear();heat_signature.Clear();drag_before.Clear();
        weight_before.Clear();weight_after.Clear();touched.Clear();geometry_cache.Clear();
        stroke_geometry.Clear();hover_hit.Clear();region.Clear();
    }
}
