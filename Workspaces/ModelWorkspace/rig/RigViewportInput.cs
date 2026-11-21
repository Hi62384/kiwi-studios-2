using Godot;
using System;

public partial class RigViewportInput : RefCounted
{
    private readonly RigViewportGeometry _geometry=new();
    private readonly RigViewportGestures _gestures=new();
    private readonly RigPaintGeometry _paint=new();
    private readonly RigMath _math=new();
    public bool handle_event(Control canvas,RigEditor editor,RefCounted state,InputEvent input)
    {
        if(!editor.enabled) return false;string drag=state.Get("drag").AsString();bool compare=state.Get("compare_rest").AsBool();var session=canvas.Get("session").As<RefCounted>();
        Vector3 Place(Vector2 p)=>_geometry.placement(canvas,editor,compare,p,state.Get("construction").AsString(),state.Get("depth").AsDouble());
        void Finish(bool cancel)=>_gestures.finish(canvas,state,cancel);
        if(input is InputEventMouseMotion motion)
        {
            state.Set("mouse",motion.Position);
            if(drag.Length>0) {if(drag=="weight") _paint.paint(canvas,editor,state,motion.Position,motion.CtrlPressed,false);else if(drag!="region") _gestures.update_drag(canvas,editor,state,motion.Position,canvas.Get("snap").AsBool()!=motion.CtrlPressed);return true;}
            if(editor.mode=="Draw") state.Set("cursor",Place(motion.Position));return false;
        }
        if(input is InputEventMouseButton mouse)
        {
            if(mouse.ButtonIndex==MouseButton.Right&&mouse.Pressed) {if(drag.Length>0){Finish(true);return true;}if(state.Get("placing").AsBool()){state.Set("placing",false);return true;}}
            if(mouse.ButtonIndex is MouseButton.WheelUp or MouseButton.WheelDown&&mouse.Pressed&&mouse.ShiftPressed&&editor.mode=="Weight")
            {state.Set("brush_radius",Math.Clamp(state.Get("brush_radius").AsDouble()*(mouse.ButtonIndex==MouseButton.WheelUp?1.15:1/1.15),.005,100));canvas.EmitSignal("gesture_finished");return true;}
            if(mouse.ButtonIndex!=MouseButton.Left) return false;canvas.GrabFocus();
            if(editor.mode=="Draw")
            {
                if(mouse.Pressed) {state.Set("placing",true);state.Set("cursor",Place(mouse.Position));}
                else if(state.Get("placing").AsBool())
                {
                    state.Set("placing",false);Vector3 endpoint=Place(mouse.Position);var armature=editor.rig();var chain=state.Get("chain");
                    if(chain.VariantType==Variant.Type.Vector3&&chain.AsVector3().DistanceTo(endpoint)>.005f&&armature!=null)
                    {var inverse=session.Get("document").As<Resource>().Call("world_transform",armature).AsTransform3D().AffineInverse();editor.add(inverse*chain.AsVector3(),inverse*endpoint,state.Get("chain_parent").AsInt32());state.Set("chain_parent",editor.selected_bone);}
                    else
                    {var joint=_geometry.pick_bone(canvas,editor,compare,mouse.Position,true);int parent=-1;if(joint.Count>0&&armature!=null){int bone=joint["bone"].AsInt32();parent=joint["end"].AsBool()?bone:armature.Get("bones").AsGodotArray()[bone].AsGodotDictionary()["parent"].AsInt32();}state.Set("chain_parent",parent);}
                    state.Set("chain",endpoint);canvas.EmitSignal("gesture_finished");
                }
                return true;
            }
            if(!mouse.Pressed){state.Set("mouse",mouse.Position);if(drag.Length>0) Finish(false);return true;}
            var selected=_geometry.pick_bone(canvas,editor,compare,mouse.Position,true);
            if(selected.Count>0&&selected["bone"].AsInt32()!=editor.selected_bone){editor.selected_bone=selected["bone"].AsInt32();canvas.EmitSignal("gesture_finished");return true;}
            if(editor.show_bones&&editor.mode is "Pose" or "Weight")
            {int handle=_geometry.handle_at(canvas.Get("tool").AsString(),mouse.Position,_geometry.handles(canvas,editor,compare));if(handle!=-2){_gestures.begin_pose(canvas,editor,state,handle,mouse.Position);return true;}}
            if(editor.mode=="Weight")
            {
                if(state.Get("weight_tool").AsString()!="Brush") {state.Set("drag","region");state.Set("region_start",mouse.Position);state.Set("mouse",mouse.Position);state.Set("region_additive",mouse.CtrlPressed||mouse.ShiftPressed);canvas.Set("_pressed",true);return true;}
                state.Set("drag","weight");state.Set("stroke_session",session);canvas.Set("_pressed",true);_paint.paint(canvas,editor,state,mouse.Position,mouse.CtrlPressed,true);return true;
            }
            if(editor.mode=="Envelope"&&_geometry.handles(canvas,editor,compare).Count>0)
            {
                var world=_geometry.world_bones(canvas,editor,compare);var bones=editor.rig()!.Get("bones").AsGodotArray();var bone=bones[editor.selected_bone].AsGodotDictionary();Vector3 center=world[editor.selected_bone].Origin.Lerp(_math.tail(bone,world[editor.selected_bone]),.5f);var camera=canvas.Get("camera").As<Camera3D>();
                Vector2 projected=canvas.Call("project",center).AsVector2();float pixels=canvas.Call("project",center+camera.Basis.X*(float)bone["radius"].AsDouble()).AsVector2().DistanceTo(projected);
                if(Mathf.Abs(mouse.Position.DistanceTo(projected)-pixels)<10) {state.Set("drag","envelope");state.Set("drag_origin",center);state.Set("drag_normal",camera.Basis.Z);session.Call("begin");canvas.Set("_pressed",true);return true;}
            }
            selected=_geometry.pick_bone(canvas,editor,compare,mouse.Position,false);
            if(selected.Count>0){editor.selected_bone=selected["bone"].AsInt32();if(editor.mode=="Edit"&&(!selected.TryGetValue("line",out var line)||!line.AsBool())) _gestures.begin_joint(canvas,editor,state,editor.selected_bone,selected["end"].AsBool(),mouse.Position);canvas.EmitSignal("gesture_finished");}
            return true;
        }
        if(input is InputEventKey key&&key.Pressed&&!key.Echo)
        {
            if(key.Keycode==Key.Escape){if(drag.Length>0) Finish(true);else{state.Set("chain",default(Variant));state.Set("placing",false);}return true;}
            if(key.CtrlPressed&&key.Keycode is Key.Z or Key.Y){state.Set("chain",default(Variant));state.Set("chain_parent",-1);state.Set("placing",false);if(drag.Length>0) Finish(true);else session.Call(key.Keycode==Key.Y||key.ShiftPressed?"redo":"undo");return true;}
            if(key.Keycode==Key.Enter&&editor.mode=="Draw"){state.Set("chain",default(Variant));state.Set("placing",false);return true;}
            if(drag.Length>0) return true;
            if(key.Keycode is Key.Delete or Key.Backspace){editor.delete_bone();canvas.EmitSignal("gesture_finished");return true;}
        }
        return false;
    }
}
