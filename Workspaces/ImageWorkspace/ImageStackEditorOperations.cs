using Godot;
using System;
using System.Collections.Generic;
using GArray=Godot.Collections.Array;
using Settings=Godot.Collections.Dictionary;
public partial class ImageStackEditorOperations:RefCounted
{
    private readonly ImageDocumentOperations _documents=new();private readonly ImageValueOperations _values=new();
    private static Control Workspace(Window owner)=>owner.Get("workspace").As<Control>();
    private static bool Adjustments(Window owner)=>owner.Get("adjustments").AsBool();
    private static Settings Constants=>GD.Load<GDScript>("res://Workspaces/ImageWorkspace/image_stack_editor.gd").GetScriptConstantMap();
    private static Settings MathConstants=>GD.Load<GDScript>("res://Workspaces/ImageWorkspace/image_values.gd").GetScriptConstantMap();
    private static Variant Get(Settings d,string key,Variant fallback=default)=>d.TryGetValue(key,out var value)?value:fallback;
    private static bool IsMath(string kind){foreach(var item in MathConstants["TYPES"].AsGodotArray())if(item.AsString()==kind)return true;return false;}
    private static void Action(Window owner,System.Action callback)=>Workspace(owner).Call("_action",Callable.From(callback));
    private static Button Button(Window owner,Node parent,string text,System.Action action,string tip="",string icon="")=>Workspace(owner).Call("_button",parent,text,Callable.From(action),tip,icon).As<Button>();
    private static void Clear(Window owner,Node parent)=>Workspace(owner).Call("_clear",parent);
    public Vector3 adjustment_range(string kind){var constants=Constants;return Get(constants["EXTRA_RANGES"].AsGodotDictionary(),kind,Get(constants["RANGES"].AsGodotDictionary(),kind,new Vector3(-16,64,1))).AsVector3();}
    public Resource? layer(Window owner)=>_documents.layer_for_id(Workspace(owner).Get("document").As<Resource>(),owner.Get("layer_id").AsString());
    public GArray entries(Window owner)
    {
        var item=layer(owner)!;if(!Adjustments(owner))return item.Get("effects").AsGodotArray();var properties=item.Get("properties").AsGodotDictionary();if(!properties.ContainsKey("value_operations"))properties["value_operations"]=new GArray();return properties["value_operations"].AsGodotArray();
    }
    public void add_entry(Window owner,string kind)
    {
        if(Adjustments(owner))Action(owner,()=>{var operation=IsMath(kind)?_values.new_operation(kind):new Settings{["type"]=kind,["amount"]=adjustment_range(kind).Z,["enabled"]=true};operation["id"]=NewId();entries(owner).Add(operation);});else Workspace(owner).Call("add_effect",kind);rebuild_stack(owner);
    }
    private static string NewId()=>ActorData.new_id();
    public void reset_entry(Window owner,int index)
    {
        Action(owner,()=>{var list=entries(owner);var op=list[index].AsGodotDictionary();string kind=op["type"].AsString();if(Adjustments(owner))list[index]=IsMath(kind)?_values.new_operation(kind):new Settings{["type"]=kind,["amount"]=adjustment_range(kind).Z,["enabled"]=true};else{var replacement=Workspace(owner).Call("_new_effect",kind).AsGodotDictionary();replacement["id"]=Get(op,"id",replacement["id"]);replacement["enabled"]=Get(op,"enabled",true);list[index]=replacement;}});rebuild_stack(owner);
    }
    public void move_entry(Window owner,int from,int to){if(from==to)return;Action(owner,()=>{var list=entries(owner);var item=list[from];list.RemoveAt(from);list.Insert(to,item);});rebuild_stack(owner);}
    public string signature(Window owner){var result=new System.Text.StringBuilder(Workspace(owner).Get("document").AsGodotObject().GetInstanceId().ToString());foreach(var item in entries(owner)){var op=item.AsGodotDictionary();result.Append(Get(op,"id","").AsString()).Append(op["type"].AsString()).Append(op.ContainsKey("a")?"true":"false");}return result.ToString();}
    public void process(Window owner)
    {
        if(layer(owner)==null){close_editor(owner);return;}if(signature(owner)!=owner.Get("_signature").AsString())rebuild_stack(owner);var renderer=Workspace(owner).Get("renderer").AsGodotObject();bool whole=owner.Get("whole").AsBool();renderer.Call("set_composition_preview_enabled",whole);var preview=owner.Get("preview").As<Control>();if(whole)preview.Set("texture",renderer.Call("composition_texture"));else{var views=renderer.Get("views").AsGodotDictionary();string id=owner.Get("layer_id").AsString();if(views.ContainsKey(id))preview.Set("texture",views[id].AsGodotDictionary()["output"].AsGodotObject().Get("texture"));}
    }
    public void close_editor(Window owner){var workspace=Workspace(owner);workspace.Get("renderer").AsGodotObject().Call("set_composition_preview_enabled",false);workspace.Call("_finish_pending");owner.QueueFree();}
    public void key_input(Window owner,InputEvent input)
    {
        if(input is not InputEventKey key||!key.Pressed||key.Echo)return;var workspace=Workspace(owner);if(key.CtrlPressed&&key.Keycode==Key.Z)workspace.Call(key.ShiftPressed?"redo":"undo");else if(key.CtrlPressed&&key.Keycode==Key.Y)workspace.Call("redo");else if(key.Keycode==Key.Escape)close_editor(owner);else return;owner.GetViewport().SetInputAsHandled();
    }
    public void rebuild_library(Window owner)
    {
        var library=owner.Get("library").As<VBoxContainer>();Clear(owner,library);var constants=Constants;var groups=constants[Adjustments(owner)?"CATEGORIES":"EFFECT_CATEGORIES"].AsGodotDictionary();var search=owner.Get("search").As<LineEdit>();string query=search.Text.ToLowerInvariant();var collapsed=owner.Get("_category_collapsed").AsGodotDictionary();
        if(groups.Count>0)
        {
            foreach(var pair in groups)
            {
                string category=pair.Key.AsString();var matches=new List<string>();foreach(var item in pair.Value.AsGodotArray()){string kind=item.AsString();if(query.Length==0||kind.Replace("_"," ").Contains(query,StringComparison.Ordinal)||category.ToLowerInvariant().Contains(query,StringComparison.Ordinal))matches.Add(kind);}if(matches.Count==0)continue;
                var section=new VBoxContainer();section.AddThemeConstantOverride("separation",3);library.AddChild(section);bool closed=Get(collapsed,category,false).AsBool();var header=Button(owner,section,category,()=>{collapsed[category]=!Get(collapsed,category,false).AsBool();rebuild_library(owner);},"Expand or collapse "+category);header.Alignment=HorizontalAlignment.Left;header.AddThemeColorOverride("font_color",new Color("80d9c4"));header.Text=(closed&&query.Length==0?"▸ ":"▾ ")+category;if(closed&&query.Length==0)continue;
                foreach(string kind in matches){string caption=kind=="shader"?"Canvas shader…":kind.Replace("_"," ").Capitalize();var button=Button(owner,section,caption,()=>{if(kind=="shader")Workspace(owner).Call("_choose_shader_effect");else add_entry(owner,kind);},"Add "+caption,kind);button.Alignment=HorizontalAlignment.Left;button.SizeFlagsHorizontal=Control.SizeFlags.ExpandFill;}
            }
            return;
        }
        foreach(var item in constants["EFFECTS"].AsGodotArray()){string kind=item.AsString(),caption=kind.Replace("_"," ").Capitalize();if(query.Length>0&&!caption.ToLowerInvariant().Contains(query,StringComparison.Ordinal))continue;var button=Button(owner,library,caption,()=>add_entry(owner,kind),"Add "+caption,kind);button.Alignment=HorizontalAlignment.Left;button.SizeFlagsHorizontal=Control.SizeFlags.ExpandFill;}
        if(!Adjustments(owner)&&(query.Length==0||"canvas shader".Contains(query,StringComparison.Ordinal)))Button(owner,library,"Canvas shader…",()=>Workspace(owner).Call("_choose_shader_effect"),"Load a canvas shader effect","shader");
    }
    public void rebuild_stack(Window owner)
    {
        var stack=owner.Get("stack").As<VBoxContainer>();Clear(owner,stack);var list=entries(owner);var workspace=Workspace(owner);
        for(int i=0;i<list.Count;i++)
        {
            int index=i;var op=list[i].AsGodotDictionary();string kind=op["type"].AsString();var card=new ImageOperationRow{index=i};card.reorder_requested+=(from,to)=>move_entry(owner,from,to);card.AddThemeStyleboxOverride("panel",workspace.Call("_box",new Color("172735"),new Color("355467"),6,7).As<StyleBoxFlat>());stack.AddChild(card);var fields=new VBoxContainer{MouseFilter=Control.MouseFilterEnum.Pass};card.AddChild(fields);var header=new HBoxContainer();fields.AddChild(header);
            var enabled=new CheckButton{Text="⠿ "+(i+1)+" · "+kind.Replace("_"," ").Capitalize(),Icon=workspace.Call("_icon",kind).As<Texture2D>(),ExpandIcon=true,ButtonPressed=Get(op,"enabled",true).AsBool(),SizeFlagsHorizontal=Control.SizeFlags.ExpandFill};enabled.AddThemeConstantOverride("icon_max_width",18);enabled.AddThemeFontSizeOverride("font_size",12);header.AddChild(enabled);enabled.Toggled+=value=>Action(owner,()=>op["enabled"]=value);Button(owner,header,"×",()=>Action(owner,()=>entries(owner).RemoveAt(index)),"Remove","trash");
            if(Adjustments(owner))
            {
                if(op.ContainsKey("a")){simple_math_fields(owner,fields,op);if(kind=="snap")workspace.Call("_check",fields,"Preserve hue",Get(op,"preserve_hue",true),Callable.From<bool>(value=>op["preserve_hue"]=value));}
                else{var limits=adjustment_range(kind);workspace.Call("_slider",fields,"Amount",Get(op,"amount",limits.Z),limits.X,limits.Y,Callable.From<double>(value=>op["amount"]=value));}
            }
            else workspace.Call("_effect_fields",fields,op);
            var actions=new HBoxContainer();fields.AddChild(actions);Button(owner,actions,"↑",()=>move_entry(owner,index,Math.Max(0,index-1)),"Earlier");Button(owner,actions,"↓",()=>move_entry(owner,index,Math.Min(entries(owner).Count-1,index+1)),"Later");Button(owner,actions,"Reset",()=>reset_entry(owner,index),"Reset parameters","reset");if(!Adjustments(owner))Button(owner,actions,"Apply",()=>workspace.Call("_apply_effect",layer(owner)!,index),"Bake effect into pixels","check");
        }
        if(list.Count==0)stack.AddChild(new Label{Text="Choose an item from the library.",AutowrapMode=TextServer.AutowrapMode.WordSmart});owner.Set("_signature",signature(owner));
    }
    public void simple_math_fields(Window owner,Node parent,Settings op)
    {
        string kind=op["type"].AsString();if(kind is "absolute" or "invert")return;var captions=new Settings{["add"]="Amount",["subtract"]="Amount",["multiply"]="Factor",["divide"]="Divisor",["power"]="Exponent",["snap"]="Step size",["minimum"]="Ceiling",["maximum"]="Floor",["clamp"]="Minimum",["smoothstep"]="Lower edge",["lerp"]="Target value"};var limits=kind is "divide" or "power"?new Vector2(.01f,8):kind=="snap"?new Vector2(.001f,1):new Vector2(-4,4);var b=Get(op,"b",new Settings()).AsGodotDictionary();double value=Get(b,"kind","").AsString()=="float"?Get(b,"value",1).AsDouble():_values.operand_value(b,Vector4.One).X;var workspace=Workspace(owner);
        if(kind=="lerp"){var rgba=_values.operand_value(b,Vector4.One);workspace.Call("_color",parent,"Target color",new Color(rgba.X,rgba.Y,rgba.Z,rgba.W),Callable.From<Color>(next=>{op["a"]=new Settings{["kind"]="pixel"};op["b"]=new Settings{["kind"]="vector",["channels"]=new GArray{next.R,next.G,next.B,next.A}};}));}
        else workspace.Call("_slider",parent,Get(captions,kind,"Amount"),value,limits.X,limits.Y,Callable.From<double>(next=>{op["a"]=new Settings{["kind"]="pixel"};op["b"]=new Settings{["kind"]="float",["value"]=next};}));
        if(kind is "clamp" or "smoothstep" or "lerp"){var c=Get(op,"c",new Settings{["kind"]="float",["value"]=1.0}).AsGodotDictionary();double second=Get(c,"kind","").AsString()=="float"?Get(c,"value",1).AsDouble():_values.operand_value(c,Vector4.One).X;workspace.Call("_slider",parent,kind=="lerp"?"Blend":kind=="clamp"?"Maximum":"Upper edge",second,kind=="lerp"?0:-4,kind=="lerp"?1:4,Callable.From<double>(next=>{op["a"]=new Settings{["kind"]="pixel"};op["c"]=new Settings{["kind"]="float",["value"]=next};}));}
    }
}
