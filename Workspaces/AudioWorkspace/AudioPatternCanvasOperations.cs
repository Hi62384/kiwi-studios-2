using Godot;
using System;
using GArray=Godot.Collections.Array;
using Settings=Godot.Collections.Dictionary;
public partial class AudioPatternCanvasOperations:RefCounted
{
    private const float Keys=70,Top=24;
    private static readonly int[] Drums={36,38,42,46,45,49,51,39};
    private static GodotObject Session(Control o)=>o.Get("session").AsGodotObject();
    private static GodotObject Actor(Control o)=>Session(o)?.Call("primary_actor").AsGodotObject()!;
    private static GodotObject Clip(Control o)=>Session(o)?.Call("primary_clip").AsGodotObject()!;
    private static double N(GodotObject o,string key)=>o.Get(key).AsDouble();
    private static double N(Settings d,string key,double fallback=0)=>d.TryGetValue(key,out var v)?v.AsDouble():fallback;
    private static string Text(GodotObject o,string key)=>o.Get(key).AsString();
    private static GArray Selected(Control o)=>o.Get("selected").AsGodotArray();
    private static Settings Originals(Control o)=>o.Get("_original").AsGodotDictionary();
    private static Settings Values(Control o)=>Actor(o).Get("values").AsGodotDictionary();
    private static string Id(){using var crypto=new Crypto();return Convert.ToHexString(crypto.GenerateRandomBytes(16)).ToLowerInvariant();}
    private static void Changed(Control o){o.EmitSignal("notes_changed");o.QueueRedraw();}
    private static void Action(Control o,string label,System.Action action)=>Session(o).Call("action",label,Callable.From(action));
    public void ready(Control o){o.FocusMode=Control.FocusModeEnum.All;o.ClipContents=true;o.CustomMinimumSize=new Vector2(300,180);o.Set("_font",ThemeDB.FallbackFont);}
    public void canvas_notification(Control o,int what){if(what==Control.NotificationFocusExit||what==Node.NotificationExitTree)finish_edit(o,true);}
    public GArray notes(Control o){var actor=Actor(o);if(actor==null)return new GArray();var values=actor.Get("values").AsGodotDictionary();return values.TryGetValue(new StringName("notes"),out var raw)?raw.AsGodotArray():new GArray();}
    public int pitch(Control o,double y){int row=(int)((y-Top)/N(o,"row_height"));return Text(o,"mode")=="steps"?Drums[Math.Clamp(row,0,Drums.Length-1)]:Math.Clamp((int)N(o,"start_pitch")-row,0,127);}
    public Rect2 note_rect(Control o,Settings note){int row=Text(o,"mode")=="steps"?Array.IndexOf(Drums,(int)N(note,"pitch")):(int)N(o,"start_pitch")-(int)N(note,"pitch");return new Rect2((float)(Keys+(N(note,"start")-N(o,"scroll_beat"))*N(o,"pixels_per_beat")),(float)(Top+row*N(o,"row_height")+1),(float)Math.Max(5,N(note,"duration")*N(o,"pixels_per_beat")),(float)N(o,"row_height")-2);}
    public Settings hit(Control o,Vector2 point){foreach(var raw in notes(o)){var note=raw.AsGodotDictionary();if(note_rect(o,note).HasPoint(point))return note;}return new Settings();}
    public bool editable(Control o){var session=Session(o);var clip=Clip(o);return session!=null&&clip!=null&&Actor(o)!=null&&session.Call("can_edit",clip.Get("id")).AsBool();}
    public void mark_changed(Control o)
    {
        if(Actor(o)==null)return;var values=Values(o);values.Remove(new StringName("drum_patterns"));values.Remove(new StringName("drum_instances"));values[new StringName("notes_dirty")]=true;double length=N(values,"pattern_beats",N(o,"pattern_beats"));foreach(var raw in notes(o)){var note=raw.AsGodotDictionary();length=Math.Max(length,Math.Ceiling(N(note,"start")+N(note,"duration")));}values[new StringName("pattern_beats")]=length;o.Set("pattern_beats",length);
    }
    public void finish_edit(Control o,bool keep)
    {
        bool changed=o.Get("_drag_changed").AsBool();o.Set("_drag","");Originals(o).Clear();o.Set("_drag_clip","");o.Set("_drag_changed",false);o.Get("_gesture").AsGodotObject().Call("finish",Session(o),keep&&changed);if(changed)Changed(o);
    }
    public void delete_selected(Control o)
    {
        if(!editable(o))return;Action(o,"Delete notes",()=>{var keep=new GArray();foreach(var raw in notes(o))if(!Selected(o).Contains(raw.AsGodotDictionary()["id"].AsString()))keep.Add(raw);Values(o)[new StringName("notes")]=keep;mark_changed(o);});Selected(o).Clear();Changed(o);
    }
    public void copy(Control o){var clipboard=o.Get("_clipboard").AsGodotArray();clipboard.Clear();foreach(var raw in notes(o))if(Selected(o).Contains(raw.AsGodotDictionary()["id"].AsString()))clipboard.Add(raw.AsGodotDictionary().Duplicate(true));}
    public void paste(Control o,double at)
    {
        var clipboard=o.Get("_clipboard").AsGodotArray();if(clipboard.Count==0||!editable(o))return;double earliest=double.PositiveInfinity;foreach(var raw in clipboard)earliest=Math.Min(earliest,N(raw.AsGodotDictionary(),"start"));Action(o,"Paste notes",()=>{Selected(o).Clear();foreach(var raw in clipboard){var note=raw.AsGodotDictionary();var duplicate=note.Duplicate(true);duplicate["id"]=Id();duplicate["start"]=N(note,"start")-earliest+at;notes(o).Add(duplicate);Selected(o).Add(duplicate["id"]);}mark_changed(o);});Changed(o);
    }
    public void quantize(Control o)
    {
        if(!editable(o))return;Action(o,"Quantize notes",()=>{double snap=N(o,"snap_beat");foreach(var raw in notes(o)){var note=raw.AsGodotDictionary();if(Selected(o).Count==0||Selected(o).Contains(note["id"].AsString())){note["start"]=Mathf.Snapped(N(note,"start"),snap);note["duration"]=Math.Max(snap,Mathf.Snapped(N(note,"duration"),snap));}}mark_changed(o);});Changed(o);
    }
    public void key_input(Control o,InputEvent input)
    {
        if(!o.HasFocus()||input is not InputEventKey e||!e.Pressed||e.Echo)return;
        if(e.Keycode==Key.Escape)finish_edit(o,false);else if(e.Keycode==Key.Delete){finish_edit(o,true);delete_selected(o);}else if(e.CtrlPressed&&e.Keycode==Key.A){Selected(o).Clear();foreach(var raw in notes(o))Selected(o).Add(raw.AsGodotDictionary()["id"].AsString());o.QueueRedraw();}else if(e.CtrlPressed&&e.Keycode==Key.C)copy(o);else if(e.CtrlPressed&&e.Keycode==Key.V)paste(o,N(o,"scroll_beat"));else if(e.CtrlPressed&&e.Keycode==Key.D){copy(o);paste(o,N(o,"pattern_beats"));}else return;o.GetViewport().SetInputAsHandled();
    }
    public void gui_input(Control o,InputEvent input)
    {
        var session=Session(o);var gesture=o.Get("_gesture").AsGodotObject();if(Text(o,"_drag").Length>0&&(!gesture.Call("valid",session).AsBool()||Clip(o)==null||Clip(o).Get("id").AsString()!=Text(o,"_drag_clip")))finish_edit(o,true);
        if(input is InputEventKey key&&key.Pressed&&key.Keycode==Key.Escape){finish_edit(o,false);o.AcceptEvent();return;}if(!editable(o))return;
        if(input is InputEventMouseButton e)
        {
            if(e.Pressed&&e.ButtonIndex is MouseButton.WheelUp or MouseButton.WheelDown){int direction=e.ButtonIndex==MouseButton.WheelUp?1:-1;if(e.CtrlPressed)o.Set("pixels_per_beat",Math.Clamp(N(o,"pixels_per_beat")*Math.Pow(1.2,direction),15,1000));else if(e.ShiftPressed)o.Set("scroll_beat",Math.Max(0,N(o,"scroll_beat")-direction));else if(Text(o,"mode")=="piano")o.Set("start_pitch",Math.Clamp((int)N(o,"start_pitch")+direction*3,12,127));o.QueueRedraw();o.AcceptEvent();return;}
            if(e.ButtonIndex==MouseButton.Right&&e.Pressed){var remove=hit(o,e.Position);if(remove.Count>0){Action(o,"Delete note",()=>{notes(o).Remove(remove);mark_changed(o);});Changed(o);}return;}if(e.ButtonIndex!=MouseButton.Left)return;if(!e.Pressed){finish_edit(o,true);return;}o.GrabFocus();o.Set("_origin",e.Position);if(e.Position.X<Keys){o.EmitSignal("audition",pitch(o,e.Position.Y));return;}
            var note=hit(o,e.Position);if(note.Count==0){var created=new Settings{["id"]=Id(),["pitch"]=pitch(o,e.Position.Y),["start"]=Math.Max(0,Mathf.Snapped(N(o,"scroll_beat")+(e.Position.X-Keys)/N(o,"pixels_per_beat"),N(o,"snap_beat"))),["duration"]=N(o,"snap_beat"),["velocity"]=.8,["probability"]=1.0,["ratchets"]=1};Action(o,"Add note",()=>{var values=notes(o);values.Add(created);Values(o)[new StringName("notes")]=values;mark_changed(o);});Selected(o).Clear();Selected(o).Add(created["id"]);o.EmitSignal("audition",created["pitch"].AsInt32());Changed(o);return;}
            if(Text(o,"mode")=="steps"&&!e.CtrlPressed&&!e.ShiftPressed){Action(o,"Remove step",()=>{notes(o).Remove(note);mark_changed(o);});Changed(o);return;}if(!e.CtrlPressed)Selected(o).Clear();if(!Selected(o).Contains(note["id"].AsString()))Selected(o).Add(note["id"].AsString());o.Set("_drag",e.AltPressed||e.Position.Y>o.Size.Y-26?"velocity":e.Position.X>note_rect(o,note).End.X-8?"resize":"move");Originals(o).Clear();foreach(var raw in notes(o)){var entry=raw.AsGodotDictionary();if(Selected(o).Contains(entry["id"].AsString()))Originals(o)[entry["id"]]=entry.Duplicate(true);}gesture.Call("begin",session,"Edit notes");o.Set("_drag_clip",Clip(o).Get("id"));o.Set("_drag_changed",false);o.QueueRedraw();
        }
        else if(input is InputEventMouseMotion motion&&Text(o,"_drag").Length>0)
        {
            var delta=motion.Position-o.Get("_origin").AsVector2();double earliest=double.PositiveInfinity;int lowest=127,highest=0;foreach(var raw in Originals(o).Values){var original=raw.AsGodotDictionary();earliest=Math.Min(earliest,N(original,"start"));lowest=Math.Min(lowest,(int)N(original,"pitch"));highest=Math.Max(highest,(int)N(original,"pitch"));}double beatDelta=Math.Max(-earliest,Mathf.Snapped(delta.X/N(o,"pixels_per_beat"),N(o,"snap_beat")));int pitchDelta=Math.Clamp(-(int)Math.Round(delta.Y/N(o,"row_height"),MidpointRounding.AwayFromZero),-lowest,127-highest);
            foreach(var raw in notes(o)){var note=raw.AsGodotDictionary();if(!Originals(o).TryGetValue(note["id"],out var saved))continue;var original=saved.AsGodotDictionary();var previous=note.Duplicate(true);switch(Text(o,"_drag")){case "move":note["start"]=N(original,"start")+beatDelta;if(Text(o,"mode")=="piano")note["pitch"]=(int)N(original,"pitch")+pitchDelta;break;case "resize":note["duration"]=Math.Max(N(o,"snap_beat"),Mathf.Snapped(N(original,"duration")+delta.X/N(o,"pixels_per_beat"),N(o,"snap_beat")));break;case "velocity":note["velocity"]=Math.Clamp(N(original,"velocity",.8)-delta.Y/100,.01,1);break;}if(!note.RecursiveEqual(previous))o.Set("_drag_changed",true);}
            if(o.Get("_drag_changed").AsBool()){mark_changed(o);session.Call("preview");}o.QueueRedraw();
        }
    }
}
