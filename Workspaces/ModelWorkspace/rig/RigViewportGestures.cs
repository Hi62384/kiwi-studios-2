using Godot;
using Settings=Godot.Collections.Dictionary;

public partial class RigViewportGestures : RefCounted
{
    private readonly RigViewportGeometry _geometry=new();
    private readonly RigMath _math=new();
    public void finish(Control canvas,RefCounted state,bool cancel)
    {
        string drag=state.Get("drag").AsString();if(drag.Length==0) return;
        if(drag=="region")
        {
            if(!cancel) {Vector2 start=state.Get("region_start").AsVector2();state.Call("select_region",new Rect2(start,state.Get("mouse").AsVector2()-start).Abs(),state.Get("region_additive"));}
        }
        else if(drag=="weight")
        {
            var session=state.Get("stroke_session").As<RefCounted>();var before=state.Get("weight_before").AsGodotDictionary();var after=state.Get("weight_after").AsGodotDictionary();var handler=new RigBindingWeights();
            if(cancel) handler.apply_weight_patch(session,before);
            else if(before.Count>0)
            {
                var document=session.Get("document").As<Resource>();var geometry=new RigBindingGeometry();
                foreach(Variant id in state.Get("touched").AsGodotDictionary().Keys)
                {var item=document.Call("component",id).As<Resource>();if(item!=null&&item.Get("binding").As<Resource>() is Resource binding) item.Set("skin_mesh",geometry.render_mesh(binding,-1));}
                var weak=GodotObject.WeakRef(session) ?? throw new System.InvalidOperationException("The model session is no longer available.");var undo=before.Duplicate(true);var redo=after.Duplicate(true);
                session.Call("custom_action","Paint skin weights",Callable.From(()=>handler.apply_weight_patch(weak,undo)),Callable.From(()=>handler.apply_weight_patch(weak,redo)),before.Count);
            }
            state.Set("weight_before",new Settings());state.Set("weight_after",new Settings());state.Set("touched",new Settings());state.Set("stroke_session",default(Variant));state.Get("stroke_geometry").AsGodotDictionary().Clear();
        }
        else
        {
            var session=canvas.Get("session").As<RefCounted>();if(cancel) session.Call("cancel");else session.Call("commit",drag=="pose"?"Pose bone":drag=="envelope"?"Resize bone envelope":"Move rig joint");
        }
        state.Set("drag","");canvas.Set("_pressed",false);canvas.EmitSignal("gesture_finished");canvas.Call("request_sync");
    }
    public void begin_joint(Control canvas,RigEditor editor,RefCounted state,int index,bool end,Vector2 point)
    {
        if(!editor.can_edit_rest()) {canvas.EmitSignal("gesture_finished");return;}
        editor.selected_bone=index;var world=_geometry.world_bones(canvas,editor,state.Get("compare_rest").AsBool());var armature=editor.rig()!;
        Vector3 origin=end?_math.tail(armature.Get("bones").AsGodotArray()[index].AsGodotDictionary(),world[index]):world[index].Origin;
        Vector3 normal=canvas.Get("camera").As<Camera3D>().Basis.Z;
        state.Set("drag","joint");state.Set("drag_end",end);state.Set("drag_origin",origin);state.Set("drag_normal",normal);state.Set("drag_point",_geometry.plane_hit(canvas,point,origin,normal));state.Set("drag_mouse",point);
        canvas.Get("session").As<RefCounted>().Call("begin");canvas.Set("_pressed",true);
    }
    public bool begin_pose(Control canvas,RigEditor editor,RefCounted state,int index,Vector2 point)
    {
        var geometry=_geometry.handles(canvas,editor,state.Get("compare_rest").AsBool());if(geometry.Count==0) return false;
        Vector3 origin=geometry["origin"].AsVector3();var axes=geometry["axes"].AsGodotArray<Vector3>();
        Vector3 normal=canvas.Get("tool").AsString()=="Rotate"&&index>=0?axes[index]:canvas.Get("camera").As<Camera3D>().Basis.Z;
        Variant value=_geometry.plane_hit(canvas,point,origin,normal);if(value.VariantType==Variant.Type.Nil){state.Set("drag","");return false;}
        state.Set("drag","pose");state.Set("drag_axis",index);state.Set("drag_origin",origin);state.Set("drag_length",geometry["length"]);state.Set("drag_mouse",point);state.Set("drag_axes",axes);state.Set("drag_normal",normal);state.Set("drag_point",value);
        state.Set("drag_before",editor.rig()!.Get("bones").AsGodotArray().Duplicate(true));canvas.Get("session").As<RefCounted>().Call("begin");canvas.Set("_pressed",true);return true;
    }
    public void update_drag(Control canvas,RigEditor editor,RefCounted state,Vector2 point,bool snap)
    {
        var armature=editor.rig();Vector3 origin=state.Get("drag_origin").AsVector3();Variant hit=_geometry.plane_hit(canvas,point,origin,state.Get("drag_normal").AsVector3());
        if(hit.VariantType==Variant.Type.Nil||armature==null) return;
        Vector3 value=hit.AsVector3(),dragPoint=state.Get("drag_point").AsVector3();var session=canvas.Get("session").As<RefCounted>();var document=session.Get("document").As<Resource>();string drag=state.Get("drag").AsString();
        Transform3D rigTransform=document.Call("world_transform",armature).AsTransform3D();
        if(drag=="joint")
        {
            Vector3 next=origin+value-dragPoint;if(snap) next=next.Snapped(Vector3.One*(float)canvas.Get("grid_step").AsDouble());
            editor.move_joint(editor.selected_bone,state.Get("drag_end").AsBool(),rigTransform.AffineInverse()*next);return;
        }
        var bones=armature.Get("bones").AsGodotArray();var bone=bones[editor.selected_bone].AsGodotDictionary();
        if(drag=="envelope") {var inverse=rigTransform.AffineInverse();bone["radius"]=Mathf.Max(.001f,(inverse*value).DistanceTo(inverse*origin));session.EmitSignal("changed");return;}
        if(drag!="pose") return;
        var before=state.Get("drag_before").AsGodotArray();var original=before[editor.selected_bone].AsGodotDictionary();var world=_math.globals(before,true);
        var parent=rigTransform;int parentIndex=bone["parent"].AsInt32();if(parentIndex>=0) parent*=world[parentIndex];
        int dragAxis=state.Get("drag_axis").AsInt32();Vector3 axis=state.Get("drag_axes").AsGodotArray<Vector3>()[System.Math.Max(0,dragAxis)];string tool=canvas.Get("tool").AsString();
        if(tool=="Move")
        {
            Vector3 delta=value-dragPoint;if(dragAxis>=0) delta=axis*delta.Dot(axis);if(snap) delta=delta.Snapped(Vector3.One*.1f);
            bone["position"]=original["position"].AsVector3()+parent.Basis.Inverse()*delta;
        }
        else if(tool=="Rotate")
        {
            float angle=(dragPoint-origin).Normalized().SignedAngleTo((value-origin).Normalized(),axis);if(snap) angle=Mathf.Snapped(angle,Mathf.Pi/12);
            bone["rotation"]=(new Basis((parent.Basis.Inverse()*axis).Normalized(),angle)*Basis.FromEuler(original["rotation"].AsVector3()*(Mathf.Pi/180))).GetEuler()*(180/Mathf.Pi);
        }
        else
        {
            Vector2 mouse=state.Get("drag_mouse").AsVector2();float factor=Mathf.Max(.01f,1+(point.X-mouse.X-point.Y+mouse.Y)/140);
            if(dragAxis>=0)
            {
                Vector2 projected=canvas.Call("project",origin+axis*(float)state.Get("drag_length").AsDouble()).AsVector2()-canvas.Call("project",origin).AsVector2();
                if(projected.LengthSquared()>100) factor=Mathf.Max(.01f,1+(point-mouse).Dot(projected)/projected.LengthSquared());
            }
            if(snap) factor=Mathf.Max(.01f,Mathf.Snapped(factor,.1f));Vector3 scaling=Vector3.One*factor;if(dragAxis>=0){scaling=Vector3.One;scaling[dragAxis]=factor;}
            bone["scale"]=original["scale"].AsVector3()*scaling;
        }
        session.EmitSignal("changed");
    }
}
