using Godot;
using System;
public partial class ImageWorkspaceOperations
{
    private static void Invoke(Control owner,Variant setter,Variant value)=>owner.Call("_invoke_value",setter,value);
    public void number(Control owner,Node parent,string label,double value,Variant setter,double minimum,double maximum,double step)
    {
        var row=new HBoxContainer();parent.AddChild(row);row.AddChild(new Label{Text=label,SizeFlagsHorizontal=Control.SizeFlags.ExpandFill});var input=new DragNumber();input.MinValue=minimum;input.MaxValue=maximum;input.Step=step;input.Value=value;input.CustomMinimumSize=new Vector2(114,0);row.AddChild(input);input.Connect("interaction_started",Callable.From(()=>begin(owner)));input.Connect("preview_changed",Callable.From<double>(next=>{Invoke(owner,setter,next);preview(owner);}));input.Connect("drag_committed",Callable.From<double>(_=>commit(owner)));input.Connect("drag_cancelled",Callable.From(()=>cancel(owner)));input.ValueChanged+=next=>{if(input.Get("dragging").AsBool())return;begin(owner);Invoke(owner,setter,next);preview(owner);commit(owner);};
    }
    public void slider(Control owner,Node parent,string label,double value,double minimum,double maximum,Variant setter)
    {
        var row=new HBoxContainer();parent.AddChild(row);row.AddChild(new Label{Text=label,CustomMinimumSize=new Vector2(80,0)});var slider=new HSlider{MinValue=minimum,MaxValue=maximum,Step=.01,Value=value,SizeFlagsHorizontal=Control.SizeFlags.ExpandFill};row.AddChild(slider);var amount=new Label{Text=value.ToString("F2",System.Globalization.CultureInfo.InvariantCulture),CustomMinimumSize=new Vector2(40,0)};row.AddChild(amount);slider.DragStarted+=()=>begin(owner);slider.ValueChanged+=next=>{begin(owner);Invoke(owner,setter,next);amount.Text=next.ToString("F2",System.Globalization.CultureInfo.InvariantCulture);preview(owner);};slider.DragEnded+=_=>commit(owner);slider.FocusExited+=()=>commit(owner);
    }
    public void color(Control owner,Node parent,string label,Color value,Variant setter)
    {
        var row=new HBoxContainer();parent.AddChild(row);row.AddChild(new Label{Text=label,SizeFlagsHorizontal=Control.SizeFlags.ExpandFill});var input=new LiveColorPickerButton();input.Color=value;input.CustomMinimumSize=new Vector2(108,28);row.AddChild(input);input.Connect("interaction_started",Callable.From(()=>begin(owner)));input.Connect("preview_changed",Callable.From<Color>(next=>{begin(owner);Invoke(owner,setter,next);preview(owner);}));input.Connect("drag_committed",Callable.From<Color,Color>((from,to)=>commit(owner)));input.Connect("drag_cancelled",Callable.From<Color>(_=>cancel(owner)));
    }
    public void check(Control owner,Node parent,string label,bool value,Variant setter){var input=new CheckButton{Text=label,ButtonPressed=value};parent.AddChild(input);input.Toggled+=next=>Action(owner,()=>Invoke(owner,setter,next));}
    public VBoxContainer section(Control owner,string label)
    {
        var collapsed=owner.Get("_collapsed").AsGodotDictionary();bool closed=Get(collapsed,label,false).AsBool();var toggle=new Button{Text=(closed?"▸  ":"▾  ")+label.ToUpperInvariant(),Alignment=HorizontalAlignment.Left,Flat=true};toggle.AddThemeFontSizeOverride("font_size",11);toggle.AddThemeColorOverride("font_color",new Color("85a1b6"));var inspector=Field(owner,"inspector");inspector.AddChild(toggle);var fields=new VBoxContainer{Visible=!closed};fields.AddThemeConstantOverride("separation",4);inspector.AddChild(fields);toggle.Pressed+=()=>{fields.Visible=!fields.Visible;collapsed[label]=!fields.Visible;toggle.Text=(fields.Visible?"▾  ":"▸  ")+label.ToUpperInvariant();};return fields;
    }
    public void set_common(Control owner,string key,Variant value)
    {
        var document=Document(owner);foreach(var id in Canvas(owner).Get("selected").AsGodotArray())
        {
            var layer=_documents.layer_for_id(document,id.AsString());if(layer==null||layer.Get("locked").AsBool())continue;var properties=layer.Get("properties").AsGodotDictionary();switch(key)
            {
                case "position_x":var position=layer.Get("position").AsVector2();position.X=value.AsSingle();layer.Set("position",position);break;
                case "position_y":position=layer.Get("position").AsVector2();position.Y=value.AsSingle();layer.Set("position",position);break;
                case "width":case "height":
                    owner.Set("_sizing_preview",true);var dimensions=layer.Get("dimensions").AsVector2();var center=layer.Get("position").AsVector2()+dimensions*.5f;double amount=value.AsDouble(),ratio=Math.Abs(amount)/Math.Max(1,key=="width"?dimensions.X:dimensions.Y);properties[key=="width"?"flip_x":"flip_y"]=amount<0;bool keep=Get(properties,"keep_aspect",false).AsBool();var resized=key=="width"?new Vector2((float)Math.Max(1,Math.Abs(amount)),keep?dimensions.Y*(float)ratio:dimensions.Y):new Vector2(keep?dimensions.X*(float)ratio:dimensions.X,(float)Math.Max(1,Math.Abs(amount)));_documents.resize_layer(document,layer,resized);layer.Set("position",center-layer.Get("dimensions").AsVector2()*.5f);break;
                case "keep_aspect":properties[key]=value.AsBool();break;case "yaw_up_down":case "yaw_left_right":properties[key]=value;break;default:layer.Set(key,value);break;
            }
        }
    }
}
