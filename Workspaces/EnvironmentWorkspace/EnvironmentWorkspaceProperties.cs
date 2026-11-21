using Godot;
using System;
using Settings=Godot.Collections.Dictionary;

public partial class EnvironmentWorkspaceOperations
{
    private readonly BuildingUiOperations _buildingUi=new();
    private readonly BuildingSessionOperations _buildingSession=new();
    private readonly ModelNaturalSettings _naturalSettings=new();
    private readonly ModelNaturalUi _naturalUi=new();
    private readonly ModelNaturalCluster _naturalCluster=new();
    private readonly EnvironmentClimateInspector _climateUi=new();
    private readonly EnvironmentLightingInspector _lightingUi=new();
    private readonly EnvironmentScatterInspector _scatterUi=new();
    private static void Clear(Node node){foreach(Node child in node.GetChildren()){node.RemoveChild(child);child.QueueFree();}}
    private static void Heading(Node parent,string text){var label=new Label {Text=text};label.AddThemeColorOverride("font_color",new Color("7edbc4"));parent.AddChild(label);}
    private static Button Button(Node parent,string text,Action action){var button=new Button {Text=text};parent.AddChild(button);button.Pressed+=action;return button;}
    private static SpinBox Number(Node parent,string text,double value,double low,double high,double step,Action<double> write)
    {var row=new HBoxContainer();parent.AddChild(row);row.AddChild(new Label {Text=text,SizeFlagsHorizontal=Control.SizeFlags.ExpandFill});var number=new DragNumber();number.MinValue=low;number.MaxValue=high;number.Step=step;number.CustomMinimumSize=new Vector2(85,0);number.SetValueNoSignal(value);row.AddChild(number);number.ValueChanged+=write.Invoke;number.Connect("drag_committed",Callable.From<double>(write));return number;}
    public void restore_property_scroll(Control owner,string id)
    {if(id==owner.Get("_last_selection").AsString())owner.Get("_right").As<ScrollContainer>().ScrollVertical=Get(State(owner,"_property_scrolls"),id,0).AsInt32();}
    private void EditTerrain(Control owner,string id,Resource source,string label,Action edit)
    {var session=Session(owner);if(_documents.terrain(Document(session),id)!=source)return;session.Call("begin");edit();session.Call("commit",label);}
    public void refresh_properties(Control owner)
    {
        string last=owner.Get("_last_selection").AsString();if(last.Length>0)State(owner,"_property_scrolls")[last]=owner.Get("_right").As<ScrollContainer>().ScrollVertical;var parent=owner.Get("properties").As<VBoxContainer>();Clear(parent);State(owner,"_transform_inputs").Clear();var session=Session(owner);var document=Document(session);var item=session.Call("primary").As<Resource>();bool settings=owner.Get("_settings_mode").AsBool();string selection=settings?"@environment":item?.Get("id").AsString()??"";owner.Set("_last_selection",selection);owner.CallDeferred("_restore_property_scroll",selection);
        if(settings){if(owner.Get("_climate_mode").AsBool())_climateUi.properties(owner);else _lightingUi.properties(owner);return;}
        if(item==null){Heading(parent,"Build an environment");Button(parent,"＋ Add terrain",()=>Session(owner).Call("add_terrain"));Button(parent,"Browse model assets…",()=>owner.Call("choose_asset"));return;}
        string id=item.Get("id").AsString();_buildingUi.properties(owner,item,parent);GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/world/world_ui.gd").Call("properties",owner,item,parent);
        if(_buildingSession.source(item)!=null)Button(parent,"Save reusable building model…",()=>owner.Call("_save_component"));if(_naturalSettings.accepts(item.Get("generator").AsString())){_naturalUi.properties(owner,item,parent);Button(parent,"Save reusable natural model…",()=>owner.Call("_save_component"));}if(_naturalCluster.accepts(item)){_naturalCluster.properties(owner,item,parent);Button(parent,"Save reusable natural cluster…",()=>owner.Call("_save_component"));}
        Heading(parent,item.Get("title").AsString());foreach(string kind in new[]{"Position","Rotation","Scale"})for(int axis=0;axis<3;axis++){int component=axis;var input=Number(parent,kind+" "+new[]{"X","Y","Z"}[axis],transform_value(item,kind,axis),-100000,100000,.01,value=>edit_transform(owner,item,kind,component,value));State(owner,"_transform_inputs")[kind+":"+axis]=input;}
        var terrain=_documents.terrain(document,id);if(terrain!=null)TerrainProperties(owner,item,terrain,parent);
        var componentSettings=document.Get("component_settings").AsGodotDictionary();var values=Get(componentSettings,id,new Settings()).AsGodotDictionary();var scatter=Get(values,"scatter").As<Resource>();if(scatter!=null)_scatterUi.properties(owner,item,scatter);string source=Get(values,"source","").AsString();
        if(source.Length>0){Button(parent,"Edit source model ↗",()=>owner.Call("_open_model",source));var collision=new CheckButton {Text="Object collision",ButtonPressed=Get(values,"collision",false).AsBool()};parent.AddChild(collision);collision.Toggled+=value=>{if(Document(Session(owner))!=document)return;session.Call("begin");componentSettings[id].AsGodotDictionary()["collision"]=value;session.Call("commit","Toggle object collision");};}
    }
    private void TerrainProperties(Control owner,Resource item,Resource terrain,Node parent)
    {
        string id=item.Get("id").AsString();Heading(parent,"Terrain generator");var geology=new OptionButton {FitToLongestItem=false};parent.AddChild(geology);foreach(string text in new[]{"Mixed","Granite","Limestone","Sandstone","Basalt","Volcanic"})geology.AddItem(text);geology.Select(terrain.Get("geology").AsInt32());geology.ItemSelected+=index=>regenerate_terrain(owner,id,new Settings {["geology"]=index},false,false);
        foreach(string method in new[]{"_generation_properties","_erosion_properties","_cave_properties","_water_properties","_biome_properties"})owner.Call(method,item,terrain);
        Number(parent,"Width (m)",terrain.Get("dimensions").AsVector2().X,.1,100000,.1,value=>regenerate_terrain(owner,id,new Settings {["dimensions"]=new Vector2((float)value,terrain.Get("dimensions").AsVector2().Y)},false,false));Number(parent,"Length (m)",terrain.Get("dimensions").AsVector2().Y,.1,100000,.1,value=>regenerate_terrain(owner,id,new Settings {["dimensions"]=new Vector2(terrain.Get("dimensions").AsVector2().X,(float)value)},false,false));
        foreach(var spec in new[]{("Seed","seed",-100000.0,100000.0,1.0),("Base elevation","base_height",-10000.0,10000.0,.1),("Noise height","amplitude",0.0,10000.0,.1),("Noise frequency","frequency",.00001,10.0,.001)})Number(parent,spec.Item1,terrain.Get(spec.Item2).AsDouble(),spec.Item3,spec.Item4,spec.Item5,value=>regenerate_terrain(owner,id,new Settings {[spec.Item2]=spec.Item2=="seed"?Variant.From((long)value):Variant.From(value)},false,false));
        int[] resolutions={33,65,129,257,513,1025};var resolution=new OptionButton {FitToLongestItem=false};parent.AddChild(resolution);foreach(int count in resolutions){resolution.AddItem(count+" × "+count+" samples");resolution.SetItemMetadata(resolution.ItemCount-1,count);if(count==terrain.Get("resolution").AsInt32())resolution.Select(resolution.ItemCount-1);}resolution.ItemSelected+=index=>regenerate_terrain(owner,id,new Settings {["resolution"]=resolutions[index]},false,false);
        Button(parent,"Ground material…",()=>owner.Call("_choose_material",id,false));Button(parent,"Reset sculpt edits",()=>regenerate_terrain(owner,id,new Settings(),true,false));Button(parent,"Paint material…",()=>owner.Call("_choose_material",id,true));Button(parent,"Bake to editable model…",()=>owner.Call("_bake_terrain",id));Button(parent,"Paint terrain",()=>{var canvas=owner.Get("canvas").As<Control>();canvas.Set("environment_tool","Paint material");owner.Call("_refresh_context");canvas.GrabFocus();});Heading(parent,"Render detail");
        var lod=new CheckButton {Text="Automatic terrain LOD",ButtonPressed=terrain.Get("lod_enabled").AsBool()};parent.AddChild(lod);lod.Toggled+=value=>EditTerrain(owner,id,terrain,"Toggle terrain LOD",()=>terrain.Set("lod_enabled",value));Number(parent,"LOD detail bias",terrain.Get("lod_bias").AsDouble(),.1,4,.1,value=>EditTerrain(owner,id,terrain,"Change terrain LOD",()=>terrain.Set("lod_bias",value)));Number(parent,"Render distance (0 = all)",terrain.Get("render_distance").AsDouble(),0,100000,10,value=>EditTerrain(owner,id,terrain,"Change terrain render distance",()=>terrain.Set("render_distance",value)));
    }
}
