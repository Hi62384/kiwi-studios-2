using Godot;
using System;
using GArray=Godot.Collections.Array;
using Settings=Godot.Collections.Dictionary;
public partial class ImageStackEditorOperations
{
    public void ready(Window owner)
    {
        var workspace=Workspace(owner);bool adjustments=Adjustments(owner);owner.Title=(adjustments?"Color Adjustments":"Effects & Styles")+" · "+layer(owner)!.Get("label").AsString();owner.Name=adjustments?"AdjustmentStackEditor":"EffectStackEditor";owner.Transient=true;owner.Exclusive=true;var available=(Vector2I)workspace.GetViewportRect().Size-new Vector2I(48,80);owner.Size=new Vector2I(1250,700).Min(available);owner.MinSize=new Vector2I(680,380).Min(available);
        var panel=new PanelContainer();panel.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);panel.AddThemeStyleboxOverride("panel",workspace.Call("_box",new Color("111b26"),new Color("3a5969"),9,12).As<StyleBoxFlat>());owner.AddChild(panel);var root=new VBoxContainer();root.AddThemeConstantOverride("separation",10);panel.AddChild(root);var header=new HBoxContainer();root.AddChild(header);var heading=new Label{Text=adjustments?"COLOR ADJUSTMENTS":"EFFECTS & STYLES",SizeFlagsHorizontal=Control.SizeFlags.ExpandFill};heading.AddThemeColorOverride("font_color",new Color("7fe3cd"));header.AddChild(heading);
        var preview=owner.Get("preview").As<Control>();void Fit(){preview.Set("pan",Vector2.Zero);preview.Set("zoom",1.0);}
        var mode=new OptionButton();mode.AddItem("View layer only");mode.AddItem("View whole viewport");header.AddChild(mode);mode.ItemSelected+=index=>{owner.Set("whole",index==1);Fit();};Button(owner,header,"Fit",Fit,"Fit preview","fit_layer");Button(owner,header,"Done",()=>close_editor(owner),"Keep changes and return to canvas","check");
        var split=new HSplitContainer{SizeFlagsVertical=Control.SizeFlags.ExpandFill};root.AddChild(split);var left=new VBoxContainer{CustomMinimumSize=new Vector2(190,0)};split.AddChild(left);var search=owner.Get("search").As<LineEdit>();search.PlaceholderText=adjustments?"Search adjustments…":"Search effects…";search.ClearButtonEnabled=true;left.AddChild(search);var browser=new ScrollContainer{SizeFlagsVertical=Control.SizeFlags.ExpandFill,HorizontalScrollMode=ScrollContainer.ScrollMode.Disabled};left.AddChild(browser);var library=owner.Get("library").As<VBoxContainer>();library.SizeFlagsHorizontal=Control.SizeFlags.ExpandFill;library.AddThemeConstantOverride("separation",4);browser.AddChild(library);search.TextChanged+=_=>rebuild_library(owner);
        var rightSplit=new HSplitContainer{SizeFlagsHorizontal=Control.SizeFlags.ExpandFill};split.AddChild(rightSplit);preview.CustomMinimumSize=new Vector2(180,160);preview.SizeFlagsHorizontal=Control.SizeFlags.ExpandFill;rightSplit.AddChild(preview);var right=new VBoxContainer{CustomMinimumSize=new Vector2(300,0)};rightSplit.AddChild(right);var label=new Label{Text="APPLIED IN ORDER"};label.AddThemeFontSizeOverride("font_size",11);label.AddThemeColorOverride("font_color",new Color("9ab2c1"));right.AddChild(label);var scroller=new ScrollContainer{SizeFlagsVertical=Control.SizeFlags.ExpandFill,HorizontalScrollMode=ScrollContainer.ScrollMode.Disabled};right.AddChild(scroller);var stack=owner.Get("stack").As<VBoxContainer>();stack.SizeFlagsHorizontal=Control.SizeFlags.ExpandFill;stack.AddThemeConstantOverride("separation",8);scroller.AddChild(stack);
        if(!adjustments)
        {
            var styles=new GArray{new GArray{"Copy style",new Callable(workspace,"copy_style")},new GArray{"Paste style",new Callable(workspace,"paste_style")},new GArray{"Save current style…",new Callable(workspace,"_save_style")}};
            foreach(var preset in workspace.Get("_presets").AsGodotDictionary().Keys){string name=preset.AsString();styles.Add(new GArray{name,Callable.From(()=>workspace.Call("_apply_style_preset",name,false))});}workspace.Call("_menu",right,"Style presets",styles);
        }
        owner.CloseRequested+=()=>close_editor(owner);MigrateLegacy(owner);rebuild_library(owner);rebuild_stack(owner);
    }
    private void MigrateLegacy(Window owner)
    {
        if(!Adjustments(owner))return;bool legacy=false;foreach(var value in entries(owner)){var op=value.AsGodotDictionary();if(!op.ContainsKey("a")&&IsMath(op["type"].AsString())){legacy=true;break;}}
        if(legacy)Action(owner,()=>{var old=entries(owner);for(int i=0;i<old.Count;i++){var op=old[i].AsGodotDictionary();string kind=op["type"].AsString();if(op.ContainsKey("a")||!IsMath(kind))continue;var replacement=_values.new_operation(kind);double amount=Get(op,"amount",1).AsDouble();replacement["b"].AsGodotDictionary()["value"]=kind=="snap"?1/Math.Max(1,amount):amount;replacement["preserve_hue"]=false;replacement["enabled"]=Get(op,"enabled",true);old[i]=replacement;}});
        var properties=layer(owner)!.Get("properties").AsGodotDictionary();if(Get(properties,"value_basics",new Settings()).AsGodotDictionary().Count>0)Action(owner,()=>{var basics=properties["value_basics"].AsGodotDictionary();foreach(var pair in MathConstants["BASICS"].AsGodotDictionary()){double amount=Get(basics,pair.Key.AsString(),pair.Value).AsDouble();if(!Mathf.IsEqualApprox(amount,pair.Value.AsDouble()))entries(owner).Add(new Settings{["type"]=pair.Key,["amount"]=amount,["enabled"]=true,["id"]=NewId()});}properties.Remove("value_basics");});
    }
}
