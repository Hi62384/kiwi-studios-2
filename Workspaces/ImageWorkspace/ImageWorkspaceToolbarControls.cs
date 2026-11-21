using Godot;
using System;
public partial class ImageWorkspaceOperations
{
    public void paint_selection_toggle(Control owner)
    {
        var canvas=Canvas(owner);var toggle=new CheckButton{Text="Selection only",ButtonPressed=canvas.Get("paint_selection_only").AsBool(),TooltipText="Only paint selected pixels; show a subtle selection overlay."};toggle.AddThemeFontSizeOverride("font_size",12);owner.Get("_context_host").As<Container>().AddChild(toggle);toggle.Toggled+=enabled=>{canvas.Set("paint_selection_only",enabled);canvas.QueueRedraw();};
    }
    public void next_toolbar_row(Control owner)
    {
        var rows=owner.Get("context").As<Control>().GetNodeOrNull("ContextRows");if(rows==null)return;var line=new HBoxContainer{SizeFlagsHorizontal=Control.SizeFlags.ExpandFill};rows.AddChild(line);var scroll=new ScrollContainer{SizeFlagsHorizontal=Control.SizeFlags.ExpandFill,VerticalScrollMode=ScrollContainer.ScrollMode.Disabled,HorizontalScrollMode=ScrollContainer.ScrollMode.Auto};line.AddChild(scroll);var row=new HBoxContainer{SizeFlagsHorizontal=Control.SizeFlags.ExpandFill};row.AddThemeConstantOverride("separation",4);scroll.AddChild(row);owner.Set("_context_host",row);
    }
    public HBoxContainer toolbar_group(Control owner,string caption,string iconName)
    {
        var panel=new PanelContainer{TooltipText=caption.Capitalize()};panel.AddThemeStyleboxOverride("panel",box(new Color("131e2a"),new Color("304555"),6,3));owner.Get("_context_host").As<Container>().AddChild(panel);var compact=new Theme();foreach(string kind in new[]{"Button","OptionButton","ColorPickerButton"}){compact.SetFontSize("font_size",kind,12);compact.SetStylebox("normal",kind,box(new Color("202c3a"),new Color("344356"),5,4));compact.SetStylebox("hover",kind,box(new Color("2d4153"),new Color("5c7b91"),5,4));compact.SetStylebox("pressed",kind,box(new Color("21584f"),new Color("6ae2c3"),5,4));}compact.SetStylebox("normal","LineEdit",box(new Color("131e2a"),new Color("344356"),4,3));compact.SetFontSize("font_size","LineEdit",12);panel.Theme=compact;if(Canvas(owner).Get("tool").AsString()=="brush"){compact.SetFontSize("font_size","CheckButton",12);compact.SetFontSize("font_size","Label",12);}var row=new HBoxContainer();row.AddThemeConstantOverride("separation",5);panel.AddChild(row);row.AddChild(new TextureRect{Texture=icon(owner,iconName),TooltipText=caption.Capitalize(),CustomMinimumSize=new Vector2(15,15),ExpandMode=TextureRect.ExpandModeEnum.IgnoreSize,StretchMode=TextureRect.StretchModeEnum.KeepAspectCentered,SizeFlagsVertical=Control.SizeFlags.ShrinkCenter,Modulate=new Color("76cdbb")});var controls=new HBoxContainer();controls.SetMeta("compact_toolbar",true);controls.AddThemeConstantOverride("separation",4);row.AddChild(controls);return controls;
    }
    public void toolbar_toggle(Control owner,Node parent,string iconName,bool enabled,string tip,Variant changed)
    {
        var button=new Button{TooltipText=tip,Icon=icon(owner,iconName),ExpandIcon=true,CustomMinimumSize=new Vector2(34,parent.HasMeta("compact_toolbar")?28:32),FocusMode=Control.FocusModeEnum.None,ToggleMode=true,ButtonPressed=enabled};button.AddThemeConstantOverride("icon_max_width",18);parent.AddChild(button);button.Toggled+=value=>Invoke(owner,changed,value);
    }
    public SpinBox compact_number(Control owner,string caption,double value,Variant setter,double minimum,double maximum,Node? parent)
    {
        var field=new HBoxContainer();field.AddThemeConstantOverride("separation",4);(parent??owner.Get("context").As<Node>()).AddChild(field);var label=new Label{Text=caption};label.AddThemeFontSizeOverride("font_size",12);label.AddThemeColorOverride("font_color",new Color("87acae"));field.AddChild(label);var input=new DragNumber();input.MinValue=minimum;input.MaxValue=maximum;input.Step=.1;input.Value=value;input.CustomMinimumSize=new Vector2(60,0);field.AddChild(input);input.Connect("interaction_started",Callable.From(()=>begin(owner)));input.Connect("preview_changed",Callable.From<double>(next=>{Invoke(owner,setter,next);preview(owner);}));input.Connect("drag_committed",Callable.From<double>(_=>commit(owner)));input.Connect("drag_cancelled",Callable.From(()=>cancel(owner)));input.ValueChanged+=next=>{if(input.Get("dragging").AsBool())return;begin(owner);Invoke(owner,setter,next);preview(owner);commit(owner);};return input;
    }
    public void sync_context_values(Control owner)
    {
        var layer=main_layer(owner);var fields=owner.Get("_context_fields").AsGodotDictionary();if(layer==null||fields.Count==0)return;var position=layer.Get("position").AsVector2();var dimensions=layer.Get("dimensions").AsVector2();var properties=layer.Get("properties").AsGodotDictionary();foreach(var entry in new[]{("x",(double)position.X),("y",(double)position.Y),("width",dimensions.X*(Get(properties,"flip_x",false).AsBool()?-1.0:1.0)),("height",dimensions.Y*(Get(properties,"flip_y",false).AsBool()?-1.0:1.0)),("rotation",Mathf.RadToDeg(layer.Get("rotation").AsDouble())),("opacity",layer.Get("opacity").AsDouble())})if(fields.TryGetValue(entry.Item1,out var field)&&field.VariantType==Variant.Type.Object&&field.AsGodotObject() is SpinBox input)input.SetValueNoSignal(entry.Item2);
    }
    public void context_color(Control owner,string caption,Node? parent)
    {
        var canvas=Canvas(owner);var stored=owner.Get("color_picker").As<ColorPickerButton>();var picker=new ColorPickerButton{Color=stored.Color,CustomMinimumSize=new Vector2(canvas.Get("tool").AsString()=="brush"?56:72,32),TooltipText=caption};(parent??owner.Get("context").As<Node>()).AddChild(picker);picker.ColorChanged+=value=>{stored.Color=value;canvas.Set("color",value);};
    }
    public void crop_controls(Control owner)
    {
        var host=owner.Get("context").As<Node>();var scope=new CheckButton{Text="Crop entire image",ButtonPressed=owner.Get("_crop_canvas").AsBool()};host.AddChild(scope);scope.Toggled+=value=>{owner.Set("_crop_canvas",value);owner.Call("_refresh_context");};if(!scope.ButtonPressed){var mode=new OptionButton();foreach(string caption in new[]{"Extract + remove original","Copy to new layer","Remove only"})mode.AddItem(caption);mode.Select(owner.Get("_crop_action").AsInt32());host.AddChild(mode);mode.ItemSelected+=value=>owner.Set("_crop_action",value);}
    }

    public void pixel_threshold_control(Control owner,string caption,double value,Variant changed)
    {
        var group=toolbar_group(owner,caption,"hardness");group.AddChild(new Label{Text=caption});var slider=new HSlider{MinValue=0,MaxValue=100,Step=1,Value=value*100,Name=caption.Replace(" ",""),CustomMinimumSize=new Vector2(110,28),SizeFlagsVertical=Control.SizeFlags.ShrinkCenter};group.AddChild(slider);var amount=new Label{CustomMinimumSize=new Vector2(40,0),Text=((int)slider.Value)+"%"};group.AddChild(amount);slider.ValueChanged+=next=>{amount.Text=((int)next)+"%";Invoke(owner,changed,next/100);};
    }

}
