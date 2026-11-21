using Godot;
using System;
using GArray=Godot.Collections.Array;
using Settings=Godot.Collections.Dictionary;
public partial class AudioTimelineCanvasOperations
{
    public void ready(Control o)
    {
        o.FocusMode=Control.FocusModeEnum.All;o.MouseDefaultCursorShape=Control.CursorShape.Arrow;o.CustomMinimumSize=new Vector2(400,180);o.ClipContents=true;o.Set("_font",ThemeDB.FallbackFont);var session=Session(o);if(session!=null){session.Connect("changed",new Callable(o,"queue_redraw"));session.Connect("selection_changed",new Callable(o,"queue_redraw"));}var cache=o.Get("cache").AsGodotObject();cache?.Connect("waveform_ready",new Callable(o,"_waveform_ready"));
    }
    public void canvas_notification(Control o,int what){if(what==Control.NotificationFocusExit||what==Node.NotificationExitTree){finish_edit(o,true);if(Text(o,"_lane_id").Length>0)finish_automation_edit(o,true);}}
    private static Settings Originals(Control o)=>o.Get("_clip_originals").AsGodotDictionary();
    private static GArray ClipState(GodotObject clip,Settings values)=>new(){clip.Get("start_time"),clip.Get("duration"),clip.Get("source_offset"),clip.Get("playback_speed"),Get(values,"track_id",""),Get(values,"fade_in",0),Get(values,"fade_out",0)};
    public void gui_input(Control o,InputEvent input)
    {
        var session=Session(o) as RefCounted;if(session==null)return;var document=Document(o);var gesture=o.Get("_gesture").AsGodotObject();if(Originals(o).Count>0&&!gesture.Call("valid",session).AsBool())finish_edit(o,false);if(input is InputEventKey key&&key.Pressed&&key.Keycode==Key.Escape){finish_edit(o,false);finish_automation_edit(o,false);o.AcceptEvent();return;}if(handle_automation_input(o,input)){o.AcceptEvent();return;}using var edits=new AudioEditSessionOperations();
        if(input is InputEventMouseButton e)
        {
            if(e.Pressed&&e.ButtonIndex is MouseButton.WheelUp or MouseButton.WheelDown){double direction=e.ButtonIndex==MouseButton.WheelUp?1:-1;if(e.CtrlPressed){double anchor=time_at(o,e.Position.X),zoom=Math.Clamp(N(o,"zoom")*Math.Pow(1.2,direction),8,200000);o.Set("zoom",zoom);o.Set("scroll_time",Math.Max(0,anchor-(e.Position.X-LabelWidth)/zoom));}else if(e.ShiftPressed)o.Set("scroll_time",Math.Max(0,N(o,"scroll_time")-direction*80/N(o,"zoom")));else o.Set("track_scroll",Math.Clamp(N(o,"track_scroll")-direction*35,0,Math.Max(0,Items(document,"tracks").Count*N(o,"track_height")-o.Size.Y+Ruler)));o.QueueRedraw();o.AcceptEvent();return;}
            var selected=Items(session,"selected_ids");if(e.ButtonIndex==MouseButton.Right&&e.Pressed){var clip=clip_at(o,e.Position);if(clip!=null&&!selected.Contains(clip.Get("id")))edits.select(session,clip.Get("id").AsString(),false);o.EmitSignal("context_requested",e.GlobalPosition);o.AcceptEvent();return;}if(e.ButtonIndex!=MouseButton.Left)return;if(!e.Pressed){if(Text(o,"_drag") is "move" or "trim_left" or "trim_right" or "slip" or "stretch" or "fade_in" or "fade_out")finish_edit(o,o.Get("_changed").AsBool());o.Set("_drag","");o.AcceptEvent();return;}
            o.GrabFocus();o.Set("_origin",e.Position);o.Set("_changed",false);var tracks=Items(document,"tracks");if(e.Position.X<LabelWidth&&e.Position.Y>=Ruler)
            {
                int index=track_at(o,e.Position.Y);if(index<0||index>=tracks.Count)return;var track=tracks[index].AsGodotDictionary();selected.Clear();session.Set("selected_track",track["id"]);double local=e.Position.Y-(Ruler+index*N(o,"track_height")-N(o,"track_scroll"));if(local>=49&&local<=71){int button=(int)((e.Position.X-12)/40);if(button>=0&&button<3){using var lanes=new AudioAutomationLaneOperations();if(lanes.is_lane(track)&&button<2){session.EmitSignal("selection_changed");o.EmitSignal("automation_requested",S(track,"id"),button==1);o.QueueRedraw();return;}string name=new[]{"mute","solo","locked"}[button];session.Call("action","Toggle "+name,Callable.From(()=>track[name]=!Get(track,name,false).AsBool()));}}session.EmitSignal("selection_changed");o.QueueRedraw();return;
            }
            if(e.Position.Y<Ruler){string drag=e.ShiftPressed?"range":"seek";o.Set("_drag",drag);double time=snap_time(o,time_at(o,e.Position.X),new GArray());if(drag=="range")o.Set("time_selection",new Vector2((float)time,(float)time));else o.EmitSignal("seek_requested",time,true);o.QueueRedraw();return;}
            var target=clip_at(o,e.Position);if(target==null){if(e.ShiftPressed){o.Set("_drag","range");float time=(float)snap_time(o,time_at(o,e.Position.X),new GArray());o.Set("time_selection",new Vector2(time,time));}else{edits.select(session,"",false);o.EmitSignal("seek_requested",snap_time(o,time_at(o,e.Position.X),new GArray()),false);}return;}string id=target.Get("id").AsString();if(e.DoubleClick){edits.select(session,id,false);o.EmitSignal("edit_requested",id);return;}if(!selected.Contains(id)||e.CtrlPressed)edits.select(session,id,e.CtrlPressed);if(!edits.can_edit(session,id))return;var rect=clip_rect(o,target);var values=document.Call("actor_for_clip",id).AsGodotObject().Get("values").AsGodotDictionary();string operation="move";if(e.AltPressed)operation="slip";else if(e.Position.Y<rect.Position.Y+12){if(Math.Abs(e.Position.X-(rect.Position.X+N(values,"fade_in")*N(o,"zoom")))<12)operation="fade_in";else if(Math.Abs(e.Position.X-(rect.End.X-N(values,"fade_out")*N(o,"zoom")))<12)operation="fade_out";}if(operation=="move"){if(Math.Abs(e.Position.X-rect.Position.X)<7)operation="trim_left";else if(Math.Abs(e.Position.X-rect.End.X)<7)operation=e.ShiftPressed?"stretch":"trim_right";}o.Set("_drag",operation);Originals(o).Clear();foreach(var selectedId in selected){var clip=document.Call("clip_for_id",selectedId).AsGodotObject();if(clip==null)continue;var actorValues=document.Call("actor_for_clip",selectedId).AsGodotObject().Get("values").AsGodotDictionary();Originals(o)[selectedId]=new Settings{["start"]=clip.Get("start_time"),["duration"]=clip.Get("duration"),["offset"]=clip.Get("source_offset"),["speed"]=clip.Get("playback_speed"),["track"]=document.Call("track_for_clip",selectedId).AsGodotDictionary()["id"],["fade_in"]=Get(actorValues,"fade_in",0),["fade_out"]=Get(actorValues,"fade_out",0)};}gesture.Call("begin",session,operation.Capitalize()+" clips");o.AcceptEvent();
        }
        else if(input is InputEventMouseMotion motion&&Text(o,"_drag").Length>0)
        {
            string drag=Text(o,"_drag");if(drag=="seek")o.EmitSignal("seek_requested",snap_time(o,time_at(o,motion.Position.X),new GArray()),true);else if(drag=="range"){double a=snap_time(o,time_at(o,o.Get("_origin").AsVector2().X),new GArray()),b=snap_time(o,time_at(o,motion.Position.X),new GArray());var selection=new Vector2((float)Math.Min(a,b),(float)Math.Max(a,b));o.Set("time_selection",selection);o.EmitSignal("range_changed",selection);}else
            {
                double delta=(motion.Position.X-o.Get("_origin").AsVector2().X)/N(o,"zoom");foreach(var idRaw in Originals(o).Keys){string id=idRaw.AsString();var original=Originals(o)[idRaw].AsGodotDictionary();var clip=document.Call("clip_for_id",id).AsGodotObject();if(clip==null||!edits.can_edit(session,id))continue;var values=document.Call("actor_for_clip",id).AsGodotObject().Get("values").AsGodotDictionary();var previous=ClipState(clip,values);var changes=new Settings{["start_time"]=original["start"],["duration"]=original["duration"],["source_offset"]=original["offset"],["playback_speed"]=original["speed"]};var selected=Items(session,"selected_ids");double start=N(original,"start"),duration=N(original,"duration"),speed=N(original,"speed"),offset=N(original,"offset");switch(drag)
                    {
                        case "move":changes["start_time"]=snap_time(o,start+delta,selected);var tracks=Items(document,"tracks");int old=tracks.IndexOf(document.Call("track_for_id",original["track"])),shift=(int)((motion.Position.Y-o.Get("_origin").AsVector2().Y)/N(o,"track_height"));changes["track_id"]=tracks[Math.Clamp(old+shift,0,tracks.Count-1)].AsGodotDictionary()["id"];break;
                        case "trim_left":double left=Math.Clamp(snap_time(o,start+delta,selected),Math.Max(0,start-offset/speed),start+duration-1.0/44100);changes["start_time"]=left;changes["duration"]=duration+start-left;changes["source_offset"]=offset+(left-start)*speed;break;
                        case "trim_right":changes["duration"]=Math.Max(1.0/44100,snap_time(o,start+duration+delta,selected)-start);break;
                        case "slip":changes["source_offset"]=Math.Max(0,offset+delta*speed);break;
                        case "stretch":double length=Math.Max(1.0/44100,snap_time(o,start+duration+delta,selected)-start);changes["duration"]=length;changes["playback_speed"]=Math.Clamp(speed*duration/length,.05,16);break;
                        case "fade_in":values[new StringName("fade_in")]=Math.Clamp(N(original,"fade_in")+delta,0,N(clip,"duration"));break;
                        case "fade_out":values[new StringName("fade_out")]=Math.Clamp(N(original,"fade_out")-delta,0,N(clip,"duration"));break;
                    }
                    if(edits.edit_clip(session,id,changes)&&!ClipState(clip,values).RecursiveEqual(previous))o.Set("_changed",true);
                }
                if(o.Get("_changed").AsBool())session.Call("preview");
            }
            o.QueueRedraw();o.AcceptEvent();
        }
    }
}
