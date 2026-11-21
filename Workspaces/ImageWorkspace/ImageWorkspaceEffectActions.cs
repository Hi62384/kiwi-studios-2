using Godot;
using System;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;
public partial class ImageWorkspaceOperations
{
    public Settings new_effect(string kind)
    {
        double amount=kind=="brightness"?0:kind is "blur" or "outline" or "shadow" or "glow" or "wave" or "chromatic" or "halftone"?8:kind is "pixelate" or "posterize"?6:1;amount=kind switch{"motion_blur"=>12,"radial_blur"=>8,"kaleidoscope"=>6,"ripple"=>8,"scanlines"=>.35,_=>amount};
        return new Settings{["id"]=NewId(),["type"]=kind,["enabled"]=true,["amount"]=amount,["color"]=kind is "outline" or "glow"?Colors.White:new Color(0,0,0,.65f),["offset"]=new Vector2(8,8),["color2"]=Colors.White,["mirror_side"]=0,["mirror_position"]=.5,["curve"]=kind=="curves"?GD.Load<GDScript>("res://Workspaces/SceneWorkspace/scripts/Timeline/actor_value_curve.gd").Call("preset","Linear"):default(Variant),["angle"]=0.0,["spacing"]=kind=="scanlines"?6.0:12.0};
    }
    public void add_effect(Control owner,string kind)
    {
        var canvas=Canvas(owner);if(canvas.Get("selected").AsGodotArray().Count==0)return;Action(owner,()=>{foreach(var id in canvas.Get("selected").AsGodotArray()){var layer=_documents.layer_for_id(Document(owner),id.AsString());if(layer!=null&&!layer.Get("locked").AsBool())layer.Get("effects").AsGodotArray().Add(new_effect(kind));}});
    }
    public void move_effect(Control owner,int index,int direction){var layer=main_layer(owner);if(layer==null)return;var effects=layer.Get("effects").AsGodotArray();if(index<0||index>=effects.Count)return;int target=Math.Clamp(index+direction,0,effects.Count-1);Action(owner,()=>{var effect=effects[index];effects.RemoveAt(index);effects.Insert(target,effect);});}
    public void mirror_fields(Control owner,Node fields,Settings effect)
    {
        var side=new OptionButton();foreach(string label in new[]{"Mirror from left","Mirror from right","Mirror from top","Mirror from bottom"})side.AddItem(label);side.Select(Get(effect,"mirror_side",0).AsInt32());fields.AddChild(side);side.ItemSelected+=value=>Action(owner,()=>effect["mirror_side"]=value);slider(owner,fields,"Mirror line",Get(effect,"mirror_position",.5).AsDouble(),0,1,Callable.From<double>(value=>effect["mirror_position"]=value));
    }
    public void open_stack_editor(Control owner,bool adjustments)
    {
        var layer=main_layer(owner);if(layer==null){owner.Get("status").As<Label>().Text="Select a layer first.";return;}finish_pending(owner);var editor=GD.Load<GDScript>("res://Workspaces/ImageWorkspace/image_stack_editor.gd").New().As<Window>();editor.Set("workspace",owner);editor.Set("layer_id",layer.Get("id"));editor.Set("adjustments",adjustments);owner.AddChild(editor);editor.PopupCentered();
    }
    public Settings prepare_apply_effect(Control owner,Resource? layer,int index)
    {
        var document=Document(owner);if(layer==null||!_documents.can_edit(document,layer))return new Settings();var effects=layer.Get("effects").AsGodotArray();if(index<0||index>=effects.Count)return new Settings();if(layer.Get("kind").AsString()=="group"){owner.Get("status").As<Label>().Text="Merge the group before applying its effects.";return new Settings();}
        var temporary=NewDocument();Assign(temporary.Get("live_materials").AsGodotArray(),document.Get("live_materials").AsGodotArray());temporary.Set("canvas_size",new Vector2I((int)Math.Ceiling(layer.Get("dimensions").AsVector2().X),(int)Math.Ceiling(layer.Get("dimensions").AsVector2().Y)).Max(Vector2I.One));var source=_layers.copy_layer(layer);source.Set("parent_id","");source.Set("position",Vector2.Zero);source.Set("rotation",0.0);_layers.set_linear_basis(source,Transform2D.Identity);source.Set("visible",true);source.Set("isolated",false);source.Set("opacity",1.0);source.Set("blend",0);source.Set("clip_to_below",false);var properties=source.Get("properties").AsGodotDictionary();foreach(var key in properties.Keys){string name=key.AsString();if(name is "yaw_up_down" or "yaw_left_right"||name.StartsWith("value_",StringComparison.Ordinal)||name.StartsWith("values_",StringComparison.Ordinal))properties.Remove(key);}var prefix=new GArray();var sourceEffects=source.Get("effects").AsGodotArray();for(int i=0;i<=index;i++)prefix.Add(sourceEffects[i]);Assign(sourceEffects,prefix);temporary.Get("layers").AsGodotArray().Add(source);var baker=GD.Load<GDScript>("res://Workspaces/ImageWorkspace/image_renderer.gd").New().As<Node>();owner.AddChild(baker);_renderer.sync(baker,temporary);return new Settings{["original"]=document,["version"]=owner.Get("_edit_version"),["baker"]=baker,["layer"]=layer,["index"]=index};
    }
    public void complete_apply_effect(Control owner,Settings request,Image? pixels)
    {
        request["baker"].As<Node>().QueueFree();var layer=request["layer"].As<Resource>();var document=Document(owner);if(request["original"].AsGodotObject()!=document||_documents.layer_for_id(document,layer.Get("id").AsString())!=layer||request["version"].AsInt64()!=owner.Get("_edit_version").AsInt64()||pixels==null)return;pixels.Convert(Image.Format.Rgba8);var texture=ImageTexture.CreateFromImage(pixels);int index=request["index"].AsInt32();Action(owner,()=>{layer.Set("kind","basic");layer.Set("texture",texture);layer.Set("paint_base",texture);layer.Set("mask",default(Variant));layer.Get("live_paint").AsGodotArray().Clear();var effects=layer.Get("effects").AsGodotArray();for(int i=0;i<=index;i++)effects.RemoveAt(0);layer.Get("properties").AsGodotDictionary().Remove("linked_style");});owner.Get("status").As<Label>().Text="Applied effects to layer pixels · Ctrl+Z to undo";
    }
    public void effect_selection_control(Control owner,Node parent,Resource layer)
    {
        var properties=layer.Get("properties").AsGodotDictionary();var toggle=new CheckBox{Text="Affect selected pixels only",ButtonPressed=Get(properties,"effects_selection_only",false).AsBool(),TooltipText="Limit this layer's effects to the current pixel selection. Toggle again to capture a new selection."};parent.AddChild(toggle);toggle.Toggled+=enabled=>{var mask=enabled?_canvas.capture_layer_selection(Canvas(owner),layer):null;Action(owner,()=>{properties["effects_selection_only"]=enabled;if(enabled)properties["effects_selection"]=mask!=null?Variant.From(mask):default;});};
    }
    public void invert_layer_masks(Control owner)
    {
        Action(owner,()=>{foreach(var id in Canvas(owner).Get("selected").AsGodotArray()){var layer=_documents.layer_for_id(Document(owner),id.AsString());if(layer==null||layer.Get("mask").As<Texture2D>() is not Texture2D mask)continue;using var source=mask.GetImage();using var bitmap=(Image)source.Duplicate();for(int y=0;y<bitmap.GetHeight();y++)for(int x=0;x<bitmap.GetWidth();x++){float value=1-bitmap.GetPixel(x,y).R;bitmap.SetPixel(x,y,new Color(value,value,value,value));}layer.Set("mask",ImageTexture.CreateFromImage(bitmap));}});
    }

}
