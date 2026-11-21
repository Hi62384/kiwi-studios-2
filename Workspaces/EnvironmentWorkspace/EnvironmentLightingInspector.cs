using Godot;
using System;
using Settings=Godot.Collections.Dictionary;

public partial class EnvironmentLightingInspector : RefCounted
{
    private static Settings Sun(Resource document)=>document.Get("sunlight").AsGodotDictionary();
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private static void Edit(Control owner,Resource document,string label,Action change)
    {if(!GodotObject.IsInstanceValid(owner)||!owner.IsInsideTree())return;var session=owner.Get("session").As<RefCounted>();if(session.Get("document").As<Resource>()!=document)return;session.Call("begin");change();session.Call("commit",label);}
    private static void Number(Node parent,string title,double value,double low,double high,double step,Action<double> write)
    {var row=new HBoxContainer();parent.AddChild(row);row.AddChild(new Label {Text=title,SizeFlagsHorizontal=Control.SizeFlags.ExpandFill});var number=new DragNumber();number.MinValue=low;number.MaxValue=high;number.Step=step;number.CustomMinimumSize=new Vector2(85,0);number.SetValueNoSignal(value);row.AddChild(number);number.ValueChanged+=write.Invoke;number.Connect("drag_committed",Callable.From<double>(write));}
    public void properties(Control owner)
    {
        var document=owner.Get("session").As<RefCounted>().Get("document").As<Resource>();var parent=owner.Get("properties").As<VBoxContainer>();var heading=new Label {Text="Environment lighting"};heading.AddThemeColorOverride("font_color",new Color("7edbc4"));parent.AddChild(heading);
        var name=new LineEdit {Text=document.Get("title").AsString()};parent.AddChild(name);name.TextSubmitted+=value=>Edit(owner,document,"Rename environment",()=>document.Set("title",value));
        var enabled=new CheckButton {Text="Sun enabled",ButtonPressed=Get(Sun(document),"enabled",true).AsBool()};parent.AddChild(enabled);enabled.Toggled+=value=>Edit(owner,document,"Toggle environment sun",()=>Sun(document)["enabled"]=value);
        Number(parent,"Sun energy",Get(Sun(document),"energy",1.5).AsDouble(),0,100,.05,value=>Edit(owner,document,"Change sun energy",()=>Sun(document)["energy"]=value));
        var color=new ColorPickerButton {Color=Get(Sun(document),"color",Colors.White).AsColor()};parent.AddChild(color);Color original=color.Color;
        color.Pressed+=()=>original=Get(Sun(document),"color",Colors.White).AsColor();
        color.ColorChanged+=value=>{if(owner.Get("session").As<RefCounted>().Get("document").As<Resource>()!=document)return;Sun(document)["color"]=value;owner.Get("canvas").As<Control>().Call("request_sync");};
        color.PopupClosed+=()=>{if(owner.Get("session").As<RefCounted>().Get("document").As<Resource>()!=document)return;Sun(document)["color"]=original;if(color.Color!=original)Edit(owner,document,"Change sun color",()=>Sun(document)["color"]=color.Color);original=color.Color;};
        for(int axis=0;axis<3;axis++){int component=axis;Number(parent,"Sun rotation "+new[]{"X","Y","Z"}[axis],Get(Sun(document),"rotation",new Vector3(-45,-30,0)).AsVector3()[axis],-360,360,.1,value=>Edit(owner,document,"Rotate environment sun",()=>{var rotation=Get(Sun(document),"rotation",new Vector3(-45,-30,0)).AsVector3();rotation[component]=(float)value;Sun(document)["rotation"]=rotation;}));}
        var choose=new Button {Text="World / sky resource…"};parent.AddChild(choose);choose.Pressed+=()=>owner.Call("_choose_world");string path=document.Get("environment_source").AsString();
        if(path.Length>0){parent.AddChild(new Label {Text=path.GetFile(),TooltipText=path,TextOverrunBehavior=TextServer.OverrunBehavior.TrimEllipsis});var clear=new Button {Text="Use editor preview background"};parent.AddChild(clear);clear.Pressed+=()=>Edit(owner,document,"Clear world resource",()=>document.Set("environment_source",""));}
    }
}
