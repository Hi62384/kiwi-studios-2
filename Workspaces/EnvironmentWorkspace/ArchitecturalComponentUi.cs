using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;

public partial class ArchitecturalComponentUi : RefCounted
{
    private readonly ArchitecturalComponentOperations _components=new();
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    public bool properties(Control workspace,Resource item,Node parent)
    {
        string generator=item.Get("generator").AsString();if(!_components.accepts(generator))return false;parent.AddChild(new Label {Text="ARCHITECTURE · "+item.Get("title").AsString()});string kind=generator.Split(" / ")[1];var fields=new List<string>{"length","height","depth"};if(kind is "Door" or "Window" or "Arch")fields=new(){"width","height","depth","trim"};else if(kind is "Column" or "Pillar")fields=new(){"width","height","base","capital"};else if(kind is "Floor" or "Roof section" or "Foundation" or "Balcony" or "Porch" or "Stairs")fields=new(){"width","length","height","depth"};if(kind is "Railing" or "Balcony" or "Porch")fields.AddRange(new[]{"spacing","rails"});if(kind=="Stairs")fields.Add("steps");if(kind=="Door")fields.Add("angle");string id=item.Get("id").AsString();var parameters=item.Get("parameters").AsGodotDictionary();
        foreach(string field in fields)
        {
            var row=new HBoxContainer();parent.AddChild(row);row.AddChild(new Label {Text=field.Capitalize(),SizeFlagsHorizontal=Control.SizeFlags.ExpandFill});var number=new DragNumber();number.MinValue=field=="angle"?-170:field is "base" or "capital"?0:.01;number.MaxValue=field=="angle"?170:field=="steps"?80:field=="rails"?6:50;number.Step=field is "steps" or "rails"?1:.05;number.CustomMinimumSize=new Vector2(85,0);number.SetValueNoSignal(Get(parameters,field,0.0).AsDouble());row.AddChild(number);void Setter(double value)=>_components.set_parameter(workspace.Get("session").As<RefCounted>(),id,field,value);number.ValueChanged+=Setter;number.Connect("drag_committed",Callable.From<double>(Setter));
        }
        if(kind is "Column" or "Pillar"){var shape=new OptionButton();parent.AddChild(shape);foreach(string name in new[]{"Round","Square","Octagonal"})shape.AddItem(name);shape.Select(Get(parameters,"shape",0).AsInt32());shape.ItemSelected+=index=>_components.set_parameter(workspace.Get("session").As<RefCounted>(),id,"shape",index);}
        var editable=new Button {Text="Make editable mesh"};parent.AddChild(editable);editable.Pressed+=()=>{var session=workspace.Get("session").As<RefCounted>();using var documents=new ModelDocumentOperations();var current=documents.component(session.Get("document").As<Resource>(),id);if(current==null)return;session.Call("begin");current.Set("generator", "");session.Call("commit","Make architecture editable");};return true;
    }
}
