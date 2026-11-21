using Godot;
using System;
using System.Collections.Generic;
using GArray=Godot.Collections.Array;
using Settings=Godot.Collections.Dictionary;
public partial class ImageWorkspaceOperations
{
    private readonly PixelSelectionAlphaOperations _alpha=new();
    private static string NewId()=>ActorData.new_id();
    public Resource? main_layer(Control owner){var selected=Canvas(owner).Get("selected").AsGodotArray();return selected.Count>0?_documents.layer_for_id(Document(owner),selected[selected.Count-1].AsString()):null;}
    public void store_active_mask(Control owner)
    {
        var document=Document(owner);string id=document.Get("active_selection_mask").AsString();var masks=document.Get("selection_masks").AsGodotDictionary();if(id.Length==0||!masks.ContainsKey(id))return;var saved=masks[id].AsGodotDictionary();saved["texture"]=document.Get("pixel_selection");saved["owner"]=document.Get("pixel_selection_owner");var reference=document.Get("pixel_selection_reference").As<Resource>();saved["reference"]=reference==null?default(Variant):Variant.From(_layers.copy_layer(reference));saved["world"]=document.Get("pixel_selection_reference_world");
    }
    public void save_selection_mask(Control owner,bool empty,bool newMask)
    {
        finish_pending(owner);var document=Document(owner);var masks=document.Get("selection_masks").AsGodotDictionary();string active=document.Get("active_selection_mask").AsString();if(!empty&&!newMask&&masks.ContainsKey(active)){store_active_mask(owner);owner.Get("status").As<Label>().Text="Updated "+masks[active].AsGodotDictionary()["label"].AsString();return;}if(!empty&&document.Get("pixel_selection").AsGodotObject()==null){owner.Get("status").As<Label>().Text="Select some pixels first.";return;}
        Action(owner,()=>{string id=NewId();int number=masks.Count+1;var labels=new HashSet<string>();foreach(var value in masks.Values)labels.Add(value.AsGodotDictionary()["label"].AsString());while(labels.Contains("Mask "+number))number++;masks[id]=new Settings{["label"]="Mask "+number};document.Set("active_selection_mask",id);if(empty){var selected=Canvas(owner).Get("selected").AsGodotArray();document.Set("pixel_selection",default(Variant));document.Set("pixel_selection_owner",selected.Count>0?selected[selected.Count-1]:Variant.From(""));document.Set("pixel_selection_reference",default(Variant));document.Set("pixel_selection_reference_world",Transform2D.Identity);}});_canvas.sync_pixel_selection(Canvas(owner));owner.Call("_refresh_context");
    }
    public void activate_selection_mask(Control owner,string id)
    {
        finish_pending(owner);Action(owner,()=>{var document=Document(owner);document.Set("active_selection_mask",id);if(id.Length==0){document.Set("pixel_selection",default(Variant));document.Set("pixel_selection_reference",default(Variant));}else{var saved=document.Get("selection_masks").AsGodotDictionary()[id].AsGodotDictionary();document.Set("pixel_selection",Get(saved,"texture"));document.Set("pixel_selection_owner",Get(saved,"owner",""));document.Set("pixel_selection_reference",Get(saved,"reference"));document.Set("pixel_selection_reference_world",Get(saved,"world",Transform2D.Identity));var layer=_documents.layer_for_id(document,document.Get("pixel_selection_owner").AsString());if(layer!=null){var selected=Canvas(owner).Get("selected").AsGodotArray();selected.Clear();selected.Add(document.Get("pixel_selection_owner"));}}});_canvas.sync_pixel_selection(Canvas(owner));selection_changed(owner);
    }
    public void remove_selection_mask(Control owner){var document=Document(owner);string id=document.Get("active_selection_mask").AsString();if(id.Length==0)return;Action(owner,()=>{document.Get("selection_masks").AsGodotDictionary().Remove(id);document.Set("active_selection_mask","");});owner.Call("_refresh_context");}
    public void select_pixel_region(Control owner,bool invert)
    {
        var canvas=Canvas(owner);var source=canvas.Get("pixel_source").As<Image>();var selected=canvas.Get("selected").AsGodotArray();if(source==null||selected.Count==0)return;var document=Document(owner);var size=document.Get("canvas_size").AsVector2I();var bytes=new byte[size.X*size.Y*4];var sourceBytes=source.GetData();var selection=canvas.Get("selection").As<Image>();var previous=selection?.GetData()??Array.Empty<byte>();double selectionAlpha=canvas.Get("selection_alpha").AsDouble();var domain=canvas.Get("pixel_domain").AsRect2I();for(int y=domain.Position.Y;y<domain.End.Y;y++)for(int x=domain.Position.X;x<domain.End.X;x++){int offset=(y*size.X+x)*4;double coverage=invert?1-(previous.Length>0?previous[offset+3]/255.0:0):sourceBytes[offset+3]>0?selectionAlpha:0;for(int channel=0;channel<3;channel++)bytes[offset+channel]=255;bytes[offset+3]=(byte)Math.Clamp(Mathf.RoundToInt(coverage*255),0,255);}using var bitmap=Image.CreateFromData(size.X,size.Y,false,Image.Format.Rgba8,bytes);var mask=!invert&&canvas.Get("selection_falloff").AsDouble()>0?_alpha.feather(bitmap,canvas.Get("selection_falloff").AsDouble()):bitmap;
        try{Action(owner,()=>{document.Set("pixel_selection",ImageTexture.CreateFromImage(mask));document.Set("pixel_selection_owner",selected[selected.Count-1]);var layer=_documents.layer_for_id(document,selected[selected.Count-1].AsString());document.Set("pixel_selection_reference",layer!=null?Variant.From(_layers.copy_layer(layer)):default(Variant));document.Set("pixel_selection_reference_world",layer!=null?_documents.world_transform(document,layer):Transform2D.Identity);});_canvas.sync_pixel_selection(canvas);}finally{if(mask!=bitmap)mask.Dispose();}
    }
    public Settings prepare_adjustment_selection(Control owner,bool enabled)
    {
        finish_pending(owner);var layer=main_layer(owner);if(layer==null)return new Settings();if(enabled){var canvas=Canvas(owner);_canvas.sync_pixel_selection(canvas);var selection=canvas.Get("selection").As<Image>();if(selection==null||!selection.GetUsedRect().HasArea()){owner.Get("status").As<Label>().Text="Select pixels first, then enable Affect selected pixels only";owner.Call("_refresh_context");return new Settings();}}return new Settings{["document"]=Document(owner),["layer"]=layer,["enabled"]=enabled};
    }
    public void complete_adjustment_selection(Control owner,Settings request,Texture2D? mask)
    {
        bool enabled=request["enabled"].AsBool();if(enabled&&mask==null){owner.Call("_refresh_context");return;}var document=request["document"].As<Resource>();var layer=request["layer"].As<Resource>();if(Document(owner)!=document||_documents.layer_for_id(document,layer.Get("id").AsString())!=layer)return;Action(owner,()=>{var properties=layer.Get("properties").AsGodotDictionary();properties["values_selection_only"]=enabled;if(enabled){properties["values_selection"]=mask!;properties["values_selection_local"]=true;properties.Remove("values_selection_frame");properties.Remove("values_selection_dimensions");}});
    }
    public void sync_linked_styles(Control owner)
    {
        var presets=owner.Get("_presets").AsGodotDictionary();foreach(var value in Document(owner).Get("layers").AsGodotArray()){var layer=value.As<Resource>();var properties=layer.Get("properties").AsGodotDictionary();string name=Get(properties,"linked_style","").AsString();if(name.Length==0||!presets.ContainsKey(name))continue;var style=presets[name].AsGodotDictionary();var values=Get(style,"properties",new Settings()).AsGodotDictionary();foreach(string key in new[]{"color","color_end","stroke","stroke_color","radius","font","font_size","bold","outline","outline_color"})if(values.ContainsKey(key))properties[key]=values[key];Assign(layer.Get("effects").AsGodotArray(),Get(style,"effects",new GArray()).AsGodotArray().Duplicate(true));layer.Set("opacity",Get(style,"opacity",layer.Get("opacity")));layer.Set("blend",Get(style,"blend",layer.Get("blend")));}
    }
    public void selection_mask_controls(Control owner)
    {
        var document=Document(owner);var group=owner.Call("_toolbar_group","SAVED MASKS","mask").As<HBoxContainer>();var picker=new OptionButton{Name="SelectionMaskPicker",CustomMinimumSize=new Vector2(125,0)};picker.AddItem("Working selection");var ids=new System.Collections.Generic.List<string>{""};foreach(var pair in document.Get("selection_masks").AsGodotDictionary()){string id=pair.Key.AsString();ids.Add(id);picker.AddItem(pair.Value.AsGodotDictionary()["label"].AsString());if(id==document.Get("active_selection_mask").AsString())picker.Select(ids.Count-1);}group.AddChild(picker);picker.ItemSelected+=index=>activate_selection_mask(owner,ids[(int)index]);button(owner,group,"Save mask",Callable.From(()=>save_selection_mask(owner,false,false)),"Update the selected mask","save");button(owner,group,"Save new",Callable.From(()=>save_selection_mask(owner,false,true)),"Save the current selection as a new mask","plus");button(owner,group,"＋",Callable.From(()=>save_selection_mask(owner,true,false)),"Create a new empty mask","plus");var remove=button(owner,group,"",Callable.From(()=>remove_selection_mask(owner)),"Delete the active saved mask","trash");remove.Disabled=document.Get("active_selection_mask").AsString().Length==0;
    }

}
