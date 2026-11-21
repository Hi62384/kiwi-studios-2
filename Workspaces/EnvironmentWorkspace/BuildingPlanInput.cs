using Godot;
using System;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class BuildingPlanOperations
{
    public Settings pick(Control owner,Vector2 point,bool openings)
    {
        var source=authored(owner);if(source==null)return new Settings();var floors=source.Get("floors").AsGodotArray();var floor=floors[Math.Clamp(Floor(owner),0,floors.Count-1)].AsGodotDictionary();var best=new Settings();float distance=12;var walls=floor["walls"].AsGodotArray();for(int index=0;index<walls.Count;index++)
        {
            var wall=walls[index].AsGodotDictionary();if(openings){foreach(string endpoint in new[]{"a","b"}){float d=point.DistanceTo(to_screen(owner,wall[endpoint].AsVector2()));if(d<Math.Min(distance,9)){best=new Settings {["wall"]=index,["endpoint"]=endpoint};distance=d;}}var holes=Get(wall,"openings",new GArray()).AsGodotArray();for(int opening=0;opening<holes.Count;opening++){var hole=holes[opening].AsGodotDictionary();float d=point.DistanceTo(to_screen(owner,wall["a"].AsVector2().Lerp(wall["b"].AsVector2(),(float)Get(hole,"t",.5).AsDouble())));if(d<Math.Min(distance,9)){best=new Settings {["wall"]=index,["opening"]=opening};distance=d;}}}var closest=Geometry2D.GetClosestPointToSegment(point,to_screen(owner,wall["a"].AsVector2()),to_screen(owner,wall["b"].AsVector2()));float edgeDistance=point.DistanceTo(closest);if(edgeDistance<distance&&(best.Count==0||!openings)){best=new Settings {["wall"]=index};distance=edgeDistance;}
        }
        return best;
    }
    public void input(Control owner,InputEvent input)
    {
        if(input is InputEventKey key&&key.Pressed&&!key.Echo&&key.Keycode==Key.Escape){cancel(owner);owner.AcceptEvent();return;}var drag=owner.Get("_drag").AsGodotDictionary();
        if(input is InputEventMouseButton button)
        {
            if(button.ButtonIndex is MouseButton.WheelUp or MouseButton.WheelDown&&button.Pressed){var before=to_plan(owner,button.Position);double zoom=Math.Clamp(owner.Get("zoom").AsDouble()*(button.ButtonIndex==MouseButton.WheelUp?1.15:1/1.15),8,200);owner.Set("zoom",zoom);owner.Set("pan",button.Position-owner.Size*.5f-before*(float)zoom);owner.AcceptEvent();return;}
            if(button.ButtonIndex==MouseButton.Middle){owner.Set("_panning",button.Pressed);owner.AcceptEvent();return;}if(button.ButtonIndex==MouseButton.Right&&button.Pressed){cancel(owner);owner.AcceptEvent();return;}if(button.ButtonIndex!=MouseButton.Left)return;owner.GrabFocus();if(!button.Pressed){if(drag.Count>0){if(Get(drag,"valid",false).AsBool())Session(owner).Call("commit","Edit floor plan");else Session(owner).Call("cancel");owner.Set("_drag",new Settings());}owner.AcceptEvent();return;}
            var source=authored(owner);if(source==null)return;var floors=source.Get("floors").AsGodotArray();var floor=floors[Floor(owner)].AsGodotDictionary();var point=snap_point(owner,to_plan(owner,button.Position),button.CtrlPressed);string tool=owner.Get("tool").AsString();if(tool=="Stairs"){if(Floor(owner)>=floors.Count-1){Status(owner,"Add a level above this one first.");return;}var next=_sources.copy(source);next.Get("stairs").AsGodotArray().Add(new Settings {["id"]=Guid.NewGuid().ToString("N"),["from"]=floor["id"],["to"]=floors[Floor(owner)+1].AsGodotDictionary()["id"],["type"]=0,["position"]=point,["width"]=1.0,["length"]=4.0,["steps"]=16});apply(owner,next,false);owner.AcceptEvent();return;}
            if(tool is "Wall" or "Room"){owner.Set("_drag",new Settings {["kind"]=tool,["source"]=_sources.copy(source),["start"]=point,["point"]=point,["new_id"]=Guid.NewGuid().ToString("N"),["valid"]=false});Session(owner).Call("begin");}
            else
            {
                var hit=pick(owner,button.Position,tool=="Select");if(hit.Count==0){owner.Set("selected_wall",-1);owner.Set("selected_opening",-1);return;}int selected=hit["wall"].AsInt32();owner.Set("selected_wall",selected);owner.Set("selected_opening",Get(hit,"opening",-1));if(tool=="Select"){drag=hit.Duplicate();drag["kind"]="Select";drag["source"]=_sources.copy(source);drag["start"]=point;drag["point"]=point;drag["valid"]=false;owner.Set("_drag",drag);Session(owner).Call("begin");}
                else if(tool=="Delete"){var next=_sources.copy(source);next.Get("floors").AsGodotArray()[Floor(owner)].AsGodotDictionary()["walls"].AsGodotArray().RemoveAt(selected);apply(owner,next,false);owner.Set("selected_wall",-1);owner.Set("selected_opening",-1);}
                else{var next=_sources.copy(source);var wall=next.Get("floors").AsGodotArray()[Floor(owner)].AsGodotDictionary()["walls"].AsGodotArray()[selected].AsGodotDictionary();var a=wall["a"].AsVector2();var delta=wall["b"].AsVector2()-a;double t=Math.Clamp((point-a).Dot(delta)/Math.Max(.001,delta.LengthSquared()),0,1);wall["openings"].AsGodotArray().Add(new Settings {["id"]=Guid.NewGuid().ToString("N"),["type"]=tool.ToLowerInvariant(),["t"]=t,["width"]=tool=="Window"?1.4:1.0,["height"]=tool=="Window"?1.2:2.1,["bottom"]=tool=="Window"?1.0:0.0});apply(owner,next,false);}
            }
            owner.AcceptEvent();
        }
        else if(input is InputEventMouseMotion motion)
        {
            if(owner.Get("_panning").AsBool()){owner.Set("pan",owner.Get("pan").AsVector2()+motion.Relative);owner.AcceptEvent();return;}if(drag.Count==0)return;var point=snap_point(owner,to_plan(owner,motion.Position),motion.CtrlPressed);drag["point"]=point;var next=_sources.copy(drag["source"].As<Resource>());var floor=next.Get("floors").AsGodotArray()[Floor(owner)].AsGodotDictionary();string kind=drag["kind"].AsString();var start=drag["start"].AsVector2();if(kind=="Wall"){if(point.DistanceTo(start)<.1)return;floor["walls"].AsGodotArray().Add(new Settings {["id"]=drag["new_id"],["a"]=start,["b"]=point,["height"]=Get(floor,"height",3.0),["openings"]=new GArray()});}else if(kind=="Room"){if(!room(owner,next,floor,new Rect2(start,point-start).Abs(),drag["new_id"].AsString()))return;}else
            {
                var wall=floor["walls"].AsGodotArray()[drag["wall"].AsInt32()].AsGodotDictionary();if(drag.ContainsKey("opening")){var opening=wall["openings"].AsGodotArray()[drag["opening"].AsInt32()].AsGodotDictionary();var delta=wall["b"].AsVector2()-wall["a"].AsVector2();double half=Get(opening,"width",1.0).AsDouble()*.5/Math.Max(.001,delta.Length());opening["t"]=Math.Clamp((point-wall["a"].AsVector2()).Dot(delta)/Math.Max(.001,delta.LengthSquared()),half,1-half);}else{var replacements=new Settings();if(drag.TryGetValue("endpoint",out var endpoint))replacements[wall[endpoint]]=point;else{var offset=point-start;replacements[wall["a"]]=wall["a"].AsVector2()+offset;replacements[wall["b"]]=wall["b"].AsVector2()+offset;}replace_points(next,floor,replacements);}
            }
            drag["valid"]=apply(owner,next,true);owner.AcceptEvent();
        }
    }
}
