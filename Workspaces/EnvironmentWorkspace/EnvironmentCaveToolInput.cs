using Godot;
using System;
using Settings=Godot.Collections.Dictionary;

public partial class EnvironmentCaveTool
{
    public bool input(RefCounted tool,InputEvent inputEvent)
    {
        var canvas=Canvas(tool);string mode=canvas.Get("environment_tool").AsString();if(!mode.StartsWith("Cave ",StringComparison.Ordinal))return false;bool active=State(tool,"_drag").Count>0||State(tool,"_stroke").Count>0;
        if(active&&((inputEvent is InputEventKey escape&&escape.Pressed&&(escape.Keycode==Key.Escape||escape.CtrlPressed&&escape.Keycode is Key.Z or Key.Y))||(inputEvent is InputEventMouseButton right&&right.Pressed&&right.ButtonIndex==MouseButton.Right))){cancel(tool);return true;}
        if(canvas.Get("_navigating").AsBool()||canvas.Get("_panning").AsBool()||canvas.Get("_orbiting").AsBool())return false;
        if(inputEvent is InputEventMouseButton wheel&&wheel.Pressed&&wheel.ShiftPressed&&wheel.ButtonIndex is MouseButton.WheelUp or MouseButton.WheelDown){canvas.Set("brush_radius",Math.Clamp(canvas.Get("brush_radius").AsDouble()*(wheel.ButtonIndex==MouseButton.WheelUp?1.15:1/1.15),.1,100));canvas.EmitSignal("brush_settings_changed");return true;}
        var info=target(tool);if(info.Count==0)return false;
        if(inputEvent is InputEventKey deletion&&deletion.Pressed&&deletion.Keycode is Key.Delete or Key.Backspace&&mode=="Cave path")
        {var cave=info["cave"].As<Resource>().Duplicate(true);if(Remove(cave,tool.Get("path_index").AsInt32(),tool.Get("point_index").AsInt32()))canvas.EmitSignal("cave_replaced",info["id"].AsString(),cave);return true;}
        if(mode=="Cave path")return path_input(tool,inputEvent,info);
        if(inputEvent is InputEventMouseMotion motion)
        {
            var hit=canvas.Call("pick_terrain",motion.Position).AsGodotDictionary();tool.Set("_hit",hit);if(State(tool,"_stroke").Count>0&&hit.Count>0&&hit["id"].AsString()==info["id"].AsString())stroke_dab(tool,hit["local"].AsVector3(),motion.CtrlPressed,false);canvas.Get("overlay").As<Control>().QueueRedraw();return State(tool,"_stroke").Count>0;
        }
        if(inputEvent is InputEventMouseButton button&&button.ButtonIndex==MouseButton.Left)
        {
            if(button.Pressed)
            {
                canvas.GrabFocus();var hit=canvas.Call("pick_terrain",button.Position).AsGodotDictionary();tool.Set("_hit",hit);
                if(hit.Count>0&&hit["id"].AsString()==info["id"].AsString()){tool.Set("_stroke",new Settings {["id"]=info["id"],["cave"]=info["cave"].As<Resource>().Duplicate(true),["last"]=hit["local"]});stroke_dab(tool,hit["local"].AsVector3(),button.CtrlPressed,true);}
            }
            else
            {
                var stroke=State(tool,"_stroke");if(stroke.Count>0){canvas.EmitSignal("cave_replaced",stroke["id"].AsString(),stroke["cave"]);tool.Set("_stroke",new Settings());canvas.EmitSignal("gesture_finished");}
            }
            canvas.Get("overlay").As<Control>().QueueRedraw();return true;
        }
        return false;
    }
    public void stroke_dab(RefCounted tool,Vector3 point,bool invert,bool first)
    {
        var canvas=Canvas(tool);var stroke=State(tool,"_stroke");var last=stroke["last"].AsVector3();double spacing=Math.Max(.1,canvas.Get("brush_radius").AsDouble()*canvas.Get("brush_spacing").AsDouble());if(!first&&last.DistanceTo(point)<spacing)return;
        int count=Math.Clamp((int)Math.Ceiling(last.DistanceTo(point)/spacing),1,32);var edits=stroke["cave"].As<Resource>().Get("edits").AsGodotArray();
        for(int index=1;index<=count;index++)edits.Add(new Settings {["center"]=last.Lerp(point,index/(float)count),["radius"]=Math.Max(.1,canvas.Get("brush_radius").AsDouble()),["strength"]=tool.Get("strength"),["smooth"]=canvas.Get("environment_tool").AsString()=="Cave smooth",["fill"]=(canvas.Get("environment_tool").AsString()=="Cave fill")!=invert});stroke["last"]=point;
    }
}
