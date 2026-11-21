using Godot;
using System;
using System.Globalization;
using GArray=Godot.Collections.Array;
using Settings=Godot.Collections.Dictionary;
public partial class AudioAutomationCanvasOperations:RefCounted
{
    private static GodotObject Session(Control o)=>o.Get("session").AsGodotObject();
    private static GodotObject Document(Control o)=>Session(o).Get("document").AsGodotObject();
    private static Variant Get(Settings d,string key,Variant fallback=default)=>d.TryGetValue(key,out var v)?v:fallback;
    private static double N(GodotObject o,string key)=>o.Get(key).AsDouble();
    private static double N(Settings d,string key,double fallback=0)=>Get(d,key,fallback).AsDouble();
    private static string Text(GodotObject o,string key)=>o.Get(key).AsString();
    private static string S(Settings d,string key,string fallback="")=>Get(d,key,fallback).AsString();
    private static GodotObject Gesture(Control o)=>o.Get("_gesture").AsGodotObject();
    private static void Action(Control o,string label,System.Action operation)=>Session(o).Call("action",label,Callable.From(operation));
    private static void Sort(GArray values){var sorted=new System.Collections.Generic.List<Settings>();foreach(var raw in values)sorted.Add(raw.AsGodotDictionary());sorted.Sort((a,b)=>N(a,"time").CompareTo(N(b,"time")));values.Clear();foreach(var point in sorted)values.Add(point);}
    public void ready(Control o){o.FocusMode=Control.FocusModeEnum.All;o.CustomMinimumSize=new Vector2(360,230);o.MouseDefaultCursorShape=Control.CursorShape.Cross;o.ClipContents=true;Session(o)?.Connect("changed",new Callable(o,"_session_changed"));}
    public void session_changed(Control o){if(o.Get("_drag").AsBool()&&!Gesture(o).Call("valid",Session(o)).AsBool())finish_edit(o,false);o.QueueRedraw();}
    public Settings owner_data(Control o)
    {
        if(Session(o)==null)return new Settings();var document=Document(o);Settings owner;string kind=Text(o,"owner_kind"),id=Text(o,"owner_id");if(kind=="master")owner=document.Get("master").AsGodotDictionary();else if(kind=="clip"){var actor=document.Call("actor_for_clip",id).AsGodotObject();owner=actor!=null?actor.Get("values").AsGodotDictionary():new Settings();}else owner=document.Call("track_for_id",id).AsGodotDictionary();string effectId=Text(o,"effect_id");if(effectId.Length>0){foreach(var raw in Get(owner,"effects",new GArray()).AsGodotArray()){var effect=raw.AsGodotDictionary();if(S(effect,"id")==effectId)return effect;}return new Settings();}return owner;
    }
    public bool can_edit(Control o)
    {
        if(Session(o)==null||owner_data(o).Count==0)return false;var document=Document(o);string laneId=Text(o,"lane_id"),kind=Text(o,"owner_kind"),id=Text(o,"owner_id");using var lanes=new AudioAutomationLaneOperations();if(laneId.Length>0){if(!lanes.editable(document,laneId))return false;var target=new Settings{["owner_kind"]=kind,["owner_id"]=id,["effect_id"]=o.Get("effect_id"),["parameter"]=o.Get("parameter")};if(lanes.key(Get(document.Call("track_for_id",laneId).AsGodotDictionary(),"automation_target",new Settings()).AsGodotDictionary())!=lanes.key(target))return false;}if(kind=="master")return true;if(kind=="clip")return Session(o).Call("can_edit",id).AsBool();return !Get(document.Call("track_for_id",id).AsGodotDictionary(),"locked",false).AsBool();
    }
    public GArray points(Control o)=>Get(Get(owner_data(o),"automation",new Settings()).AsGodotDictionary(),Text(o,"parameter"),new GArray()).AsGodotArray();
    public Vector2 position_for(Control o,Settings point)=>new((float)(45+N(point,"time")/N(o,"duration")*(o.Size.X-60)),(float)(o.Size.Y-28-(N(point,"value")-N(o,"minimum"))/(N(o,"maximum")-N(o,"minimum"))*(o.Size.Y-44)));
    public Settings value_for(Control o,Vector2 point)=>new(){["time"]=Math.Clamp(Mathf.Snapped((point.X-45)/(o.Size.X-60)*N(o,"duration"),N(o,"grid")),0,N(o,"duration")),["value"]=Math.Clamp(N(o,"minimum")+(o.Size.Y-28-point.Y)/(o.Size.Y-44)*(N(o,"maximum")-N(o,"minimum")),N(o,"minimum"),N(o,"maximum")),["curve"]="linear"};
    public int hit(Control o,Vector2 point){var values=points(o);for(int i=0;i<values.Count;i++)if(point.DistanceTo(position_for(o,values[i].AsGodotDictionary()))<10)return i;return -1;}
    public void finish_edit(Control o,bool keep){bool changed=o.Get("_drag_changed").AsBool();if(keep&&Gesture(o).Call("valid",Session(o)).AsBool())Sort(points(o));o.Set("_drag",false);o.Set("_drag_before",default(Variant));o.Set("_drag_changed",false);Gesture(o).Call("finish",Session(o),keep&&changed);o.QueueRedraw();}
    public void canvas_notification(Control o,int what){if(what==Control.NotificationFocusExit)finish_edit(o,true);}
    public void gui_input(Control o,InputEvent input)
    {
        if(o.Get("_drag").AsBool()&&!Gesture(o).Call("valid",Session(o)).AsBool())finish_edit(o,false);if(input is InputEventKey key&&key.Pressed&&key.Keycode==Key.Escape){finish_edit(o,false);o.AcceptEvent();return;}if(!can_edit(o)){finish_edit(o,true);return;}var session=Session(o);
        if(input is InputEventMouseButton e)
        {
            if(e.ButtonIndex==MouseButton.Right&&e.Pressed){int at=hit(o,e.Position);if(at>=0){Action(o,"Delete automation point",()=>points(o).RemoveAt(at));o.Set("selected",-1);o.QueueRedraw();}o.AcceptEvent();return;}if(e.ButtonIndex!=MouseButton.Left)return;if(!e.Pressed){finish_edit(o,true);o.AcceptEvent();return;}o.GrabFocus();int selected=hit(o,e.Position);var proposed=value_for(o,e.Position);var values=points(o);if(selected<0)for(int i=0;i<values.Count;i++)if(Math.Abs(N(values[i].AsGodotDictionary(),"time")-N(proposed,"time"))<.000001){selected=i;break;}o.Set("selected",selected);if(selected<0&&values.Count>=10000)return;Gesture(o).Call("begin",session,"Edit automation");o.Set("_drag_before",session.Get("_before"));o.Set("_drag_changed",false);if(selected<0){var owner=owner_data(o);var curves=Get(owner,"automation",new Settings()).AsGodotDictionary();values=Get(curves,Text(o,"parameter"),new GArray()).AsGodotArray();values.Add(proposed);Sort(values);curves[Text(o,"parameter")]=values;owner["automation"]=curves;o.Set("selected",values.IndexOf(proposed));o.Set("_drag_changed",true);session.Call("preview");}o.Set("_drag",true);o.QueueRedraw();o.AcceptEvent();
        }
        else if(input is InputEventMouseMotion motion&&o.Get("_drag").AsBool())
        {
            int selected=o.Get("selected").AsInt32();var values=points(o);if(selected>=0&&selected<values.Count){var value=value_for(o,motion.Position);var point=values[selected].AsGodotDictionary();double low=selected>0?N(values[selected-1].AsGodotDictionary(),"time")+.000001:0,high=selected+1<values.Count?N(values[selected+1].AsGodotDictionary(),"time")-.000001:N(o,"duration"),time=Math.Clamp(N(value,"time"),low,Math.Max(low,high));if(!Mathf.IsEqualApprox(N(point,"time"),time)||!Mathf.IsEqualApprox(N(point,"value"),N(value,"value"))){point["time"]=time;point["value"]=value["value"];o.Set("_drag_changed",true);session.Call("preview");}}o.QueueRedraw();o.AcceptEvent();
        }
    }
    public void set_curve(Control o,string curve){if(!can_edit(o))return;int selected=o.Get("selected").AsInt32();if(selected<0||selected>=points(o).Count)return;Action(o,"Automation interpolation",()=>points(o)[selected].AsGodotDictionary()["curve"]=curve);o.QueueRedraw();}
    public void clear_points(Control o){if(!can_edit(o))return;Action(o,"Clear automation",()=>{var owner=owner_data(o);var curves=Get(owner,"automation",new Settings()).AsGodotDictionary();curves.Remove(Text(o,"parameter"));owner["automation"]=curves;});o.Set("selected",-1);o.QueueRedraw();}
    public void modulate(Control o,Settings settings){if(!can_edit(o))return;var values=modulation_points(settings,N(o,"duration"),N(Document(o),"tempo"),N(o,"minimum"),N(o,"maximum"));Action(o,"Generate editable modulation",()=>{var owner=owner_data(o);var curves=Get(owner,"automation",new Settings()).AsGodotDictionary();curves[Text(o,"parameter")]=values;owner["automation"]=curves;});o.Set("selected",-1);o.QueueRedraw();}
    public GArray modulation_points(Settings settings,double seconds,double tempo,double low,double high)
    {
        var output=new GArray();double rate=Math.Clamp(N(settings,"rate",1),.01,20);if(Get(settings,"sync",true).AsBool())rate=tempo/60/Math.Max(.0625,N(settings,"beats",1));using var rng=new RandomNumberGenerator{Seed=unchecked((ulong)Get(settings,"seed",1).AsInt64())};double held=rng.RandfRange(-1,1);int cycle=-1,count=Math.Clamp((int)Math.Ceiling(seconds*rate*32),2,4096);string shape=S(settings,"shape","sine");for(int i=0;i<=count;i++){double time=seconds*i/count,phase=time*rate+N(settings,"phase"),value=Math.Sin(Math.Tau*phase);switch(shape){case "triangle":value=1-4*Math.Abs(Mathf.PosMod(phase,1)-.5);break;case "saw":value=2*Mathf.PosMod(phase,1)-1;break;case "square":value=Mathf.PosMod(phase,1)<.5?1:-1;break;case "random step":if((int)Math.Floor(phase)!=cycle){cycle=(int)Math.Floor(phase);held=rng.RandfRange(-1,1);}value=held;break;case "envelope":value=-1+2*Math.Sin(Math.PI*i/count);break;}output.Add(new Settings{["time"]=time,["value"]=Math.Clamp(N(settings,"center")+N(settings,"depth",1)*value,low,high),["curve"]=shape is "square" or "random step"?"hold":"linear"});}return output;
    }
    public void draw(Control o)
    {
        o.DrawRect(new Rect2(Vector2.Zero,o.Size),new Color("101c27"));var font=ThemeDB.FallbackFont;for(int i=0;i<7;i++){double value=Mathf.Lerp(N(o,"minimum"),N(o,"maximum"),(double)i/6);float y=position_for(o,new Settings{["time"]=0,["value"]=value}).Y;o.DrawLine(new Vector2(45,y),new Vector2(o.Size.X-15,y),new Color("304352"));o.DrawString(font,new Vector2(2,y+4),value.ToString("F1",CultureInfo.InvariantCulture),HorizontalAlignment.Left,40,10);}for(int i=0;i<9;i++){double time=N(o,"duration")*i/8;float x=position_for(o,new Settings{["time"]=time,["value"]=0}).X;o.DrawLine(new Vector2(x,12),new Vector2(x,o.Size.Y-28),new Color("263846"));o.DrawString(font,new Vector2(x-6,o.Size.Y-9),time.ToString("F2",CultureInfo.InvariantCulture),HorizontalAlignment.Left,55,10);}var values=points(o);if(values.Count==0)return;using var lanes=new AudioAutomationLaneOperations();var owner=owner_data(o);var parameters=Get(owner,"parameters",owner).AsGodotDictionary();double fallback=N(parameters,Text(o,"parameter"));var last=Vector2.Zero;for(int pixel=0;pixel<Math.Max(1,(int)(o.Size.X-60));pixel++){double time=N(o,"duration")*pixel/(o.Size.X-60),value=lanes.value(values,time,fallback);var at=position_for(o,new Settings{["time"]=time,["value"]=value});if(pixel>0)o.DrawLine(last,at,new Color("70dfc3"),2);last=at;}for(int i=0;i<values.Count;i++)o.DrawCircle(position_for(o,values[i].AsGodotDictionary()),5,new Color(i==o.Get("selected").AsInt32()?"f7cc74":"d6ece7"));
    }
}
