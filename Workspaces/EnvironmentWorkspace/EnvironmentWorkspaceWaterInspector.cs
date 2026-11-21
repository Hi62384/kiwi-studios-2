using Godot;
using System;
using Settings=Godot.Collections.Dictionary;

public partial class EnvironmentWorkspaceOperations
{
    private readonly TerrainHydrologyOperations _hydrology=new();
    internal void EditWater(Control owner,string id,Action<Resource> edit)
    {
        var session=Session(owner);var terrain=_documents.terrain(Document(session),id);if(terrain==null)return;var source=terrain.Get("hydrology").As<Resource>();var next=source?.Duplicate(true)??GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/terrain/terrain_hydrology.gd").New().As<Resource>();edit(next);
        if(source!=null&&_hydrology.geometry_signature(next)==_hydrology.geometry_signature(source)){session.Call("begin");terrain.Set("hydrology",next);session.Call("commit","Change water appearance");}else regenerate_terrain(owner,id,new Settings {["hydrology"]=next},false,false);
    }
    public void edit_water(Control owner,string id,Settings edit)=>EditWater(owner,id,next=>owner.Call("_invoke_source_edit",edit,next));
    public void water_properties(Control owner,Resource item,Resource terrain)
    {
        string id=item.Get("id").AsString();var parent=Field<VBoxContainer>(owner,"properties");Heading(parent,"Water & drainage");var source=terrain.Get("hydrology").As<Resource>();if(source==null){Button(parent,"Add rivers, lakes & ocean",()=>EditWater(owner,id,_=>{}));return;}
        void ToggleField(string title,string key)=>Toggle(parent,title,source.Get(key).AsBool(),value=>EditWater(owner,id,next=>next.Set(key,value)));
        void Fields((string Title,string Key,double Low,double High,double Step)[] specs){foreach(var spec in specs)Number(parent,spec.Title,source.Get(spec.Key).AsDouble(),spec.Low,spec.High,spec.Step,value=>EditWater(owner,id,next=>next.Set(spec.Key,spec.Key=="spray_per_fall"?Variant.From((long)value):Variant.From(value))));}
        ToggleField("Water affects physics actors","water_physics");Fields(new[]{("Water density (kg/m³)","water_density",.01,20000.0,1.0),("Water drag","water_drag",0.0,10.0,.1)});
        Button(parent,"Edit river paths in viewport",()=>{var canvas=Field<Control>(owner,"canvas");canvas.Set("environment_tool","Water paths");refresh_context(owner);canvas.GrabFocus();});foreach(var field in new[]{("Water enabled","enabled"),("Automatic rivers","automatic_rivers"),("Basin lakes","automatic_lakes"),("Ocean","ocean_enabled")})ToggleField(field.Item1,field.Item2);
        Fields(new[]{("Sea level","sea_level",-10000.0,10000.0,.1),("River catchment (m²)","catchment_threshold",.1,1000000.0,1.0),("River width","river_width",.1,100.0,.1),("Channel depth","river_depth",.01,100.0,.1),("Rainfall","rainfall",0.0,100.0,.1),("Lake minimum depth","lake_minimum_depth",.01,100.0,.1),("Flow speed","flow_speed",0.0,100.0,.1),("Wave height","wave_strength",0.0,10.0,.01),("Wave frequency","wave_scale",.01,10.0,.01)});
        var color=new ColorPickerButton {Color=source.Get("water_color").AsColor()};parent.AddChild(color);color.ColorChanged+=value=>EditWater(owner,id,next=>next.Set("water_color",value));ToggleField("Waterfall spray","waterfall_spray");Fields(new[]{("Spray amount","spray_per_fall",1.0,128.0,1.0),("Spray size","spray_size",.001,10.0,.01),("Spray lifetime","spray_lifetime",.01,10.0,.1),("Foam","foam_amount",0.0,1.0,.01)});
        Button(parent,"Water material…",()=>{var job=new EnvironmentWorkspaceFileJob();owner.AddChild(job);job.start(owner,"water",id,0);});var add=new HBoxContainer();parent.AddChild(add);
        Button(add,"+ River",()=>EditWater(owner,id,next=>next.Get("manual_rivers").AsGodotArray().Add(new Settings {["id"]=Guid.NewGuid().ToString("N"),["points"]=new[]{new Vector3(0,0,-terrain.Get("dimensions").AsVector2().Y*.4f),Vector3.Zero,new Vector3(0,0,terrain.Get("dimensions").AsVector2().Y*.4f)},["width"]=next.Get("river_width"),["depth"]=next.Get("river_depth"),["follow_terrain"]=true})));
        Button(add,"+ Lake",()=>EditWater(owner,id,next=>next.Get("manual_lakes").AsGodotArray().Add(new Settings {["center"]=Vector2.Zero,["level"]=terrain.Call("sample",Vector2.Zero).AsGodotDictionary()["height"].AsDouble()+1})));
        var rivers=source.Get("manual_rivers").AsGodotArray();for(int index=0;index<rivers.Count;index++)
        {
            int slot=index;var river=rivers[index].AsGodotDictionary();Settings River(Resource next)=>next.Get("manual_rivers").AsGodotArray()[slot].AsGodotDictionary();var row=new HBoxContainer();parent.AddChild(row);string riverId=river["id"].AsString();var points=river["points"].AsVector3Array();var expand=new Button {Text="River "+(index+1)+" · "+points.Length+" points",ToggleMode=true,ButtonPressed=Get(State(owner,"_expanded_landforms"),riverId,false).AsBool()};row.AddChild(expand);expand.Toggled+=value=>{State(owner,"_expanded_landforms")[riverId]=value;owner.Set("_refresh_pending",true);};Button(row,"×",()=>EditWater(owner,id,next=>next.Get("manual_rivers").AsGodotArray().RemoveAt(slot)));if(!expand.ButtonPressed)continue;
            foreach(var spec in new[]{("Width","width",.1,100.0,.1),("Depth","depth",.01,100.0,.1)})Number(parent,spec.Item1,Get(river,spec.Item2,1.0).AsDouble(),spec.Item3,spec.Item4,spec.Item5,value=>EditWater(owner,id,next=>River(next)[spec.Item2]=value));Toggle(parent,"Follow terrain downhill",Get(river,"follow_terrain",true).AsBool(),value=>EditWater(owner,id,next=>River(next)["follow_terrain"]=value));
            for(int point=0;point<points.Length;point++)for(int axis=0;axis<3;axis++){int sample=point,component=axis;Number(parent,"Point "+(point+1)+" "+new[]{"X","Y","Z"}[axis],points[point][axis],-100000,100000,.1,value=>EditWater(owner,id,next=>{var target=River(next);var values=target["points"].AsVector3Array();values[sample][component]=(float)value;target["points"]=values;}));}
        }
        var lakes=source.Get("manual_lakes").AsGodotArray();for(int index=0;index<lakes.Count;index++)
        {
            int slot=index;var lake=lakes[index].AsGodotDictionary();Settings Lake(Resource next)=>next.Get("manual_lakes").AsGodotArray()[slot].AsGodotDictionary();Heading(parent,"Lake "+(index+1));Number(parent,"Water level",Get(lake,"level",0.0).AsDouble(),-10000,10000,.1,value=>EditWater(owner,id,next=>Lake(next)["level"]=value));for(int axis=0;axis<2;axis++){int component=axis;Number(parent,"Center "+new[]{"X","Z"}[axis],Get(lake,"center",Vector2.Zero).AsVector2()[axis],-100000,100000,.1,value=>EditWater(owner,id,next=>{var target=Lake(next);var center=Get(target,"center",Vector2.Zero).AsVector2();center[component]=(float)value;target["center"]=center;}));}Button(parent,"Remove lake",()=>EditWater(owner,id,next=>next.Get("manual_lakes").AsGodotArray().RemoveAt(slot)));
        }
        Button(parent,"Remove water system",()=>regenerate_terrain(owner,id,new Settings {["hydrology"]=default},false,false));
    }
}
