using Godot;
using System;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;
public partial class ImageWorkspaceOperations
{
    public void copy_style(Control owner){var layer=main_layer(owner);if(layer==null)return;owner.Set("_style_clipboard",new Settings{["properties"]=layer.Get("properties").AsGodotDictionary().Duplicate(true),["effects"]=_layers.copy_layer(layer).Get("effects"),["opacity"]=layer.Get("opacity"),["blend"]=layer.Get("blend")});owner.Get("status").As<Label>().Text="Style copied";}
    public void paste_style(Control owner)
    {
        var style=owner.Get("_style_clipboard").AsGodotDictionary();if(style.Count==0)return;Action(owner,()=>{foreach(var id in Canvas(owner).Get("selected").AsGodotArray()){var layer=_documents.layer_for_id(Document(owner),id.AsString());if(layer==null)continue;var properties=layer.Get("properties").AsGodotDictionary();var saved=style["properties"].AsGodotDictionary();foreach(string key in new[]{"color","color_end","stroke","stroke_color","radius","font","font_size","bold","outline","outline_color"})if(saved.ContainsKey(key))properties[key]=saved[key];var effects=layer.Get("effects").AsGodotArray();Assign(effects,style["effects"].AsGodotArray().Duplicate(true));foreach(var value in effects){var effect=value.AsGodotDictionary();if(Get(effect,"curve").VariantType==Variant.Type.Object&&Get(effect,"curve").AsGodotObject() is Curve curve)effect["curve"]=curve.Duplicate();}layer.Set("opacity",style["opacity"]);layer.Set("blend",style["blend"]);}});
    }
    public void save_style(Control owner)
    {
        var layer=main_layer(owner);if(layer==null)return;var dialog=new ConfirmationDialog{Title="Save reusable style"};owner.AddChild(dialog);var name=new LineEdit{Text=layer.Get("label").AsString()+" style",CustomMinimumSize=new Vector2(280,0)};dialog.AddChild(name);dialog.Confirmed+=()=>{string label=name.Text.Trim();if(label.Length==0)return;copy_style(owner);var presets=owner.Get("_presets").AsGodotDictionary();presets[label]=owner.Get("_style_clipboard").AsGodotDictionary().Duplicate(true);using var library=new Resource();library.SetMeta("styles",presets);var error=ResourceSaver.Save(library,"user://image_studio_styles.tres");owner.Get("status").As<Label>().Text=error==Error.Ok?"Style saved for all image documents":"Could not save style library";refresh_inspector(owner);};dialog.Confirmed+=dialog.QueueFree;dialog.Canceled+=dialog.QueueFree;dialog.CloseRequested+=dialog.QueueFree;dialog.PopupCentered(new Vector2I(360,130));name.GrabFocus();name.SelectAll();
    }
    public void apply_style_preset(Control owner,string name,bool linked)
    {
        var presets=owner.Get("_presets").AsGodotDictionary();if(!presets.ContainsKey(name))return;owner.Set("_style_clipboard",presets[name].AsGodotDictionary().Duplicate(true));paste_style(owner);Action(owner,()=>{foreach(var id in Canvas(owner).Get("selected").AsGodotArray()){var layer=_documents.layer_for_id(Document(owner),id.AsString());if(layer==null)continue;var properties=layer.Get("properties").AsGodotDictionary();if(linked)properties["linked_style"]=name;else properties.Remove("linked_style");}});
    }
}
