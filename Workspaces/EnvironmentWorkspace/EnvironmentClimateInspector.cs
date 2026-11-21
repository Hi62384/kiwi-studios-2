using Godot;
using System;
using Settings=Godot.Collections.Dictionary;

/// <summary>Climate controls and validated undoable edits for the environment workspace.</summary>
public partial class EnvironmentClimateInspector : RefCounted
{
    private readonly EnvironmentClimateOperations _climate=new();
    private static readonly string[] Weather={"Clear","Cloudy","Rain","Storm","Snow","Fog","Dust"};
    private static readonly string[] Seasons={"Spring","Summer","Autumn","Winter"};
    private static Resource Source(Resource document)=>document.Get("climate").As<Resource>()??new EnvironmentClimate();
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private void Edit(Control owner,Resource document,string label,Action<Resource> edit)
    {
        if(!GodotObject.IsInstanceValid(owner)||!owner.IsInsideTree())return;
        var session=owner.Get("session").As<RefCounted>();
        if(session.Get("document").As<Resource>()!=document)return;
        var next=_climate.copy_climate(Source(document));edit(next);var errors=_climate.validate(next);
        if(errors.Length>0){owner.Get("status").As<Label>().Text=errors[0];return;}
        session.Call("begin");document.Set("climate",next);session.Call("commit",label);owner.Get("canvas").As<Control>().Call("request_sync");
    }
    private static void Heading(Node parent,string title){var text=new Label {Text=title};text.AddThemeColorOverride("font_color",new Color("7edbc4"));parent.AddChild(text);}
    private static void Number(Node parent,string title,double value,double low,double high,double step,Action<double> write)
    {
        var row=new HBoxContainer();parent.AddChild(row);row.AddChild(new Label {Text=title,SizeFlagsHorizontal=Control.SizeFlags.ExpandFill});
        var input=new DragNumber();input.MinValue=low;input.MaxValue=high;input.Step=step;input.CustomMinimumSize=new Vector2(85,0);input.SetValueNoSignal(value);row.AddChild(input);input.ValueChanged+=write.Invoke;input.Connect("drag_committed",Callable.From<double>(write));
    }
    private static void Choice(Node parent,string[] options,int selected,Action<int> write)
    {var choice=new OptionButton();parent.AddChild(choice);foreach(string label in options)choice.AddItem(label);choice.Select(selected);choice.ItemSelected+=index=>write((int)index);}
    private static void Toggle(Node parent,string title,bool enabled,Action<bool> write)
    {var button=new CheckButton {Text=title,ButtonPressed=enabled};parent.AddChild(button);button.Toggled+=value=>write(value);}
    private void Fields(Control owner,Resource document,Resource source,Node parent,(string Title,string Key,double Low,double High,double Step)[] specs,string prefix="Change ")
    {foreach(var spec in specs)Number(parent,spec.Title,source.Get(spec.Key).AsDouble(),spec.Low,spec.High,spec.Step,value=>Edit(owner,document,prefix+spec.Title.ToLowerInvariant(),next=>next.Set(spec.Key,spec.Key is "date_day" or "weather_seed"?Variant.From((long)value):Variant.From(value))));}
    public void properties(Control owner)
    {
        var document=owner.Get("session").As<RefCounted>().Get("document").As<Resource>();var source=Source(document);var parent=owner.Get("properties").As<VBoxContainer>();
        Heading(parent,"Climate and time");Choice(parent,new[]{"Manual time","Follow scene timeline","Automatic day cycle"},source.Get("time_mode").AsInt32(),value=>Edit(owner,document,"Change environment clock",next=>next.Set("time_mode",value)));
        Fields(owner,document,source,parent,new[]{("Time of day (hours)","time_of_day",0.0,23.99,.05),("Day length (seconds)","day_length_seconds",.1,86400.0,1.0),("Start time","start_time",0.0,23.99,.05),("Latitude","latitude",-90.0,90.0,.1),("Date (day of year)","date_day",1.0,366.0,1.0)});
        Toggle(parent,"Pause time",source.Get("time_paused").AsBool(),value=>Edit(owner,document,"Pause environment time",next=>next.Set("time_paused",value)));
        Choice(parent,Seasons,source.Get("season").AsInt32(),value=>Edit(owner,document,"Change season",next=>next.Set("season",value)));
        Heading(parent,"Weather and atmosphere");Choice(parent,Weather,source.Get("weather").AsInt32(),value=>Edit(owner,document,"Change global weather",next=>next.Set("weather",value)));
        Fields(owner,document,source,parent,new[]{("Temperature (°C)","temperature",-100.0,100.0,.1),("Humidity","humidity",0.0,1.0,.01),("Cloud coverage","cloud_coverage",0.0,1.0,.01),("Weather intensity","weather_intensity",0.0,1.0,.01),("Visibility (m)","visibility",1.0,100000.0,10.0)});
        Toggle(parent,"Deterministic procedural weather",source.Get("procedural_weather").AsBool(),value=>Edit(owner,document,"Toggle procedural weather",next=>next.Set("procedural_weather",value)));
        Fields(owner,document,source,parent,new[]{("Weather seed","weather_seed",0.0,2147483647.0,1.0),("Weather interval (s)","weather_interval",1.0,86400.0,10.0),("Transition (s)","weather_transition",0.0,3600.0,1.0),("Storm probability","storm_probability",0.0,1.0,.01),("Rain probability","rain_probability",0.0,1.0,.01),("Snow probability","snow_probability",0.0,1.0,.01)});
        Heading(parent,"Wind");foreach(int axis in new[]{0,2})Number(parent,"Direction "+(axis==0?"X":"Z"),source.Get("wind_direction").AsVector3()[axis],-1,1,.01,value=>Edit(owner,document,"Change wind direction",next=>{var direction=next.Get("wind_direction").AsVector3();direction[axis]=(float)value;next.Set("wind_direction",direction);}));
        Fields(owner,document,source,parent,new[]{("Wind speed (m/s)","wind_speed",0.0,250.0,.1),("Gust strength","gust_strength",0.0,1.0,.01)});local_properties(owner,source);
    }
    public void local_properties(Control owner,Resource source)
    {
        var document=owner.Get("session").As<RefCounted>().Get("document").As<Resource>();var parent=owner.Get("properties").As<VBoxContainer>();Heading(parent,"Local weather regions");
        var add=new MenuButton {Text="＋ Add weather region"};parent.AddChild(add);foreach(string shape in new[]{"Sphere","Box","Ellipsoid"})add.GetPopup().AddItem(shape);
        add.GetPopup().IdPressed+=index=>Edit(owner,document,"Add weather region",next=>next.Get("regions").AsGodotArray().Add(new Settings {["id"]=Guid.NewGuid().ToString("N"),["name"]="Local weather",["enabled"]=true,["shape"]=new[]{"Sphere","Box","Ellipsoid"}[index],["center"]=owner.Get("canvas").As<Control>().Get("target"),["size"]=Vector3.One*80,["blend_distance"]=15.0,["priority"]=0,["overrides"]=new Settings {["weather"]="Rain",["weather_intensity"]=.7,["wind_velocity"]=next.Get("wind_direction").AsVector3().Normalized()*next.Get("wind_speed").AsSingle()}}));
        var regions=source.Get("regions").AsGodotArray();for(int i=0;i<regions.Count;i++)
        {
            int index=i;var region=regions[index].AsGodotDictionary();Settings Region(Resource next)=>next.Get("regions").AsGodotArray()[index].AsGodotDictionary();
            var row=new HBoxContainer();parent.AddChild(row);Toggle(row,"",Get(region,"enabled",true).AsBool(),value=>Edit(owner,document,"Toggle local weather",next=>Region(next)["enabled"]=value));
            var name=new LineEdit {Text=Get(region,"name","Weather region").AsString(),SizeFlagsHorizontal=Control.SizeFlags.ExpandFill};row.AddChild(name);name.TextSubmitted+=value=>Edit(owner,document,"Rename weather region",next=>Region(next)["name"]=value);
            var remove=new Button {Text="×"};row.AddChild(remove);remove.Pressed+=()=>Edit(owner,document,"Remove local weather",next=>next.Get("regions").AsGodotArray().RemoveAt(index));
            for(int axis=0;axis<3;axis++){int component=axis;Number(parent,"Center "+new[]{"X","Y","Z"}[axis],Get(region,"center",Vector3.Zero).AsVector3()[axis],-100000,100000,.1,value=>Edit(owner,document,"Move weather region",next=>{var center=Get(Region(next),"center",Vector3.Zero).AsVector3();center[component]=(float)value;Region(next)["center"]=center;}));}
            Number(parent,"Radius",Get(region,"size",Vector3.One*80).AsVector3().X*.5,1,100000,1,value=>Edit(owner,document,"Resize weather region",next=>Region(next)["size"]=Vector3.One*(float)value*2));
            Number(parent,"Blend distance",Get(region,"blend_distance",0.0).AsDouble(),0,100000,1,value=>Edit(owner,document,"Blend local weather",next=>Region(next)["blend_distance"]=value));
            var overrides=Get(region,"overrides",new Settings()).AsGodotDictionary();
            Settings Overrides(Resource next){var target=Region(next);if(!target.ContainsKey("overrides"))target["overrides"]=new Settings();return target["overrides"].AsGodotDictionary();}
            Choice(parent,Weather,Math.Max(0,Array.IndexOf(Weather,Get(overrides,"weather","Clear").AsString())),which=>Edit(owner,document,"Change local weather",next=>Overrides(next)["weather"]=Weather[which]));
            Number(parent,"Local intensity",Get(overrides,"weather_intensity",1.0).AsDouble(),0,1,.01,value=>Edit(owner,document,"Change local weather intensity",next=>Overrides(next)["weather_intensity"]=value));
        }
    }
}

