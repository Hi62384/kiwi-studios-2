using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
public partial class FogPainterOperations:RefCounted
{
    private readonly FogFieldOperations _field=new();
    private static Control View(Window owner)=>owner.Get("view").As<Control>();private static Resource Field(Window owner)=>owner.Get("field").As<Resource>();private static GodotObject Model(Window owner)=>owner.Get("host").AsGodotObject().Get("model").AsGodotObject();private static Settings Paint(Window owner)=>Field(owner).Call("get_value",new StringName("paint"),new Settings()).AsGodotDictionary();private static void SetPaint(Window owner,Settings values)=>Field(owner).Call("set_value",new StringName("paint"),values);
    public void setup(Window owner,Control inspector,Resource actor,Resource field,Resource definition)
    {
        owner.Set("host",inspector);owner.Set("actor",actor);owner.Set("field",field);owner.Set("definition",definition);owner.Title="3D density · slice painter";owner.MinSize=new Vector2I(480,480);owner.CloseRequested+=()=>close(owner);owner.Set("grid_size",32);var column=new VBoxContainer();owner.AddChild(column);column.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);var toolbar=new HFlowContainer();column.AddChild(toolbar);var planes=new OptionButton();toolbar.AddChild(planes);foreach(string name in new[]{"YZ · X depth","XZ · Y depth","XY · Z depth"})planes.AddItem(name);planes.Select(owner.Get("axis").AsInt32());planes.ItemSelected+=value=>{owner.Set("axis",value);refresh(owner);};var tools=new OptionButton();toolbar.AddChild(tools);foreach(string name in new[]{"Add","Subtract","Set","Smooth","Reset"})tools.AddItem(name);tools.ItemSelected+=value=>owner.Set("paint_mode",value);foreach(var row in new[]{("Depth",0.0,1.0,.5,"depth"),("Radius",1.0,16.0,3.0,"radius"),("Strength",0.0,1.0,.5,"strength"),("Falloff",0.0,4.0,1.0,"falloff")}){toolbar.AddChild(new Label{Text=row.Item1});var slider=new HSlider{CustomMinimumSize=new Vector2(75,0),MinValue=row.Item2,MaxValue=row.Item3,Step=.01,Value=row.Item4};toolbar.AddChild(slider);slider.ValueChanged+=value=>{owner.Set(row.Item5,value);if(row.Item5=="depth")refresh(owner);};}var view=new Control{SizeFlagsVertical=Control.SizeFlags.ExpandFill,MouseFilter=Control.MouseFilterEnum.Stop};owner.Set("view",view);column.AddChild(view);view.Draw+=()=>draw(owner);view.GuiInput+=e=>input_slice(owner,e);view.Resized+=view.QueueRedraw;column.AddChild(new Label{Text="Paint in 3D through the chosen slice. Esc cancels the current stroke.",AutowrapMode=TextServer.AutowrapMode.WordSmart});refresh(owner);
    }
    public Vector3I point(Window owner,int x,int y){int n=owner.Get("grid_size").AsInt32();int z=Math.Clamp(Mathf.RoundToInt(owner.Get("depth").AsSingle()*(n-1)),0,n-1);return owner.Get("axis").AsInt32() switch{0=>new Vector3I(z,x,y),1=>new Vector3I(x,z,y),_=>new Vector3I(x,y,z)};}
    public void refresh(Window owner)
    {
        int n=owner.Get("grid_size").AsInt32();var image=Image.CreateEmpty(n,n,false,Image.Format.Rgba8);var voxels=Paint(owner);for(int y=0;y<n;y++)for(int x=0;x<n;x++){float value=voxels.GetValueOrDefault(point(owner,x,y),0.0).AsSingle();image.SetPixel(x,y,new Color(value*.4f,value*.85f,value,1));}owner.Set("image",image);owner.Set("texture",ImageTexture.CreateFromImage(image));View(owner).QueueRedraw();
    }
    public void draw(Window owner){var view=View(owner);view.DrawTextureRect(owner.Get("texture").As<Texture2D>(),new Rect2(Vector2.Zero,view.Size),false);view.DrawArc(owner.Get("cursor").AsVector2(),owner.Get("radius").AsSingle()*view.Size.X/owner.Get("grid_size").AsInt32(),0,Mathf.Tau,48,Colors.White,1.5f,true);}
    public void input_slice(Window owner,InputEvent e)
    {
        if(e is InputEventMouseMotion motion){owner.Set("cursor",motion.Position);View(owner).QueueRedraw();if(owner.Get("painting").AsBool())dab(owner,motion.Position);}if(e is InputEventMouseButton button&&button.ButtonIndex==MouseButton.Left){if(button.Pressed){owner.Set("before",Paint(owner).Duplicate());owner.Set("painting",true);owner.Set("last",Vector2.Inf);dab(owner,button.Position);}else commit(owner);}
    }
    public void unhandled_key_input(Window owner,InputEvent e){if(e is InputEventKey key&&key.Pressed&&key.Keycode==Key.Escape){if(owner.Get("painting").AsBool()){SetPaint(owner,owner.Get("before").AsGodotDictionary());owner.Set("painting",false);refresh(owner);Model(owner).EmitSignal("changed");}else close(owner);owner.SetInputAsHandled();}}
    public void dab(Window owner,Vector2 position)
    {
        var view=View(owner);int n=owner.Get("grid_size").AsInt32();var pixel=position/view.Size*n;var last=owner.Get("last").AsVector2();double radius=owner.Get("radius").AsDouble();if(last!=Vector2.Inf&&pixel.DistanceTo(last)<Math.Max(.5,radius*.15))return;owner.Set("last",pixel);var center=point(owner,Math.Clamp((int)pixel.X,0,n-1),Math.Clamp((int)pixel.Y,0,n-1));var voxels=_field.paint_dab(Paint(owner).Duplicate(),center,radius,owner.Get("strength").AsDouble(),owner.Get("falloff").AsDouble(),owner.Get("paint_mode").AsInt32());SetPaint(owner,voxels);Model(owner).EmitSignal("changed");refresh(owner);
    }
    public void commit(Window owner){if(!owner.Get("painting").AsBool())return;owner.Set("painting",false);var after=Paint(owner);SetPaint(owner,owner.Get("before").AsGodotDictionary());Model(owner).Call("edit_object_property",owner.Get("actor"),Field(owner),owner.Get("definition"),new StringName("paint"),after);}
    public void close(Window owner){commit(owner);owner.QueueFree();}
}
