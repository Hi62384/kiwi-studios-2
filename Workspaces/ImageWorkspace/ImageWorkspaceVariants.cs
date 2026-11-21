using Godot;
using System;
using Settings=Godot.Collections.Dictionary;
public partial class ImageWorkspaceOperations
{
    public void variants_panel(Control owner)
    {
        var ui=workflow_window(owner,"Variants & snapshots",new Vector2(650,460));var popup=ui["popup"].As<PopupPanel>();var body=ui["body"].As<VBoxContainer>();body.AddChild(new Label{Text="Save named alternatives instantly, then switch or compare without duplicating files.",AutowrapMode=TextServer.AutowrapMode.WordSmart});var actions=new HFlowContainer();body.AddChild(actions);button(owner,actions,"＋ Capture current",Callable.From(()=>{capture_variant(owner);popup.QueueFree();}),"","");var variants=owner.Get("_variants").AsGodotDictionary();if(variants.Count>0)button(owner,actions,"Compare current / variant…",Callable.From(()=>compare_variant(owner)),"","");var scroll=new ScrollContainer{SizeFlagsVertical=Control.SizeFlags.ExpandFill};body.AddChild(scroll);var list=new VBoxContainer{SizeFlagsHorizontal=Control.SizeFlags.ExpandFill};scroll.AddChild(list);foreach(var key in variants.Keys){string name=key.AsString();var row=new HBoxContainer();list.AddChild(row);row.AddChild(new Label{Text=name,SizeFlagsHorizontal=Control.SizeFlags.ExpandFill});button(owner,row,"Restore",Callable.From(()=>restore_variant(owner,name)),"","");button(owner,row,"×",Callable.From(()=>{variants.Remove(name);popup.QueueFree();variants_panel(owner);}),"","");}popup.PopupCentered();
    }
    public void capture_variant(Control owner)
    {
        var variants=owner.Get("_variants").AsGodotDictionary();var dialog=new ConfirmationDialog{Title="Capture variant"};owner.AddChild(dialog);var input=new LineEdit{Text="Variant "+(variants.Count+1),CustomMinimumSize=new Vector2(320,0)};dialog.AddChild(input);dialog.Confirmed+=()=>{string name=input.Text.Trim();if(name.Length>0){finish_pending(owner);var variant=_documents.snapshot(Document(owner));variant.Set("workspace_state",new Settings());using var preview=_renderer.texture(Renderer(owner)).GetImage();if(preview!=null&&!preview.IsEmpty()){preview.Resize(320,Math.Max(1,Mathf.RoundToInt(320.0*preview.GetHeight()/preview.GetWidth())),Image.Interpolation.Bilinear);variant.Set("preview",ImageTexture.CreateFromImage(preview));}variants[name]=variant;owner.Get("status").As<Label>().Text="Captured "+name;}dialog.QueueFree();};dialog.Canceled+=dialog.QueueFree;dialog.PopupCentered();input.GrabFocus();input.SelectAll();
    }
    public void restore_variant(Control owner,string name)
    {
        var variants=owner.Get("_variants").AsGodotDictionary();var variant=ResourceValue(Get(variants,name));if(!ImageDocument(variant))return;finish_pending(owner);owner.Get("_undo").AsGodotArray().Add(_documents.snapshot(Document(owner)));owner.Get("_redo").AsGodotArray().Clear();var document=_documents.snapshot(variant!);owner.Set("document",document);Canvas(owner).Set("document",document);restored(owner);owner.Get("status").As<Label>().Text="Restored variant · "+name;
    }
    public void compare_variant(Control owner)
    {
        var popup=new PopupPanel();owner.AddChild(popup);popup.AddThemeStyleboxOverride("panel",box(new Color("111c28"),new Color("426879"),10,10));var column=new VBoxContainer{CustomMinimumSize=new Vector2(900,560)};popup.AddChild(column);var select=new OptionButton();var variants=owner.Get("_variants").AsGodotDictionary();foreach(var key in variants.Keys)select.AddItem(key.AsString());column.AddChild(select);var split=new HSplitContainer{SizeFlagsVertical=Control.SizeFlags.ExpandFill};column.AddChild(split);split.AddChild(new TextureRect{Texture=_renderer.texture(Renderer(owner)),ExpandMode=TextureRect.ExpandModeEnum.IgnoreSize,StretchMode=TextureRect.StretchModeEnum.KeepAspectCentered});var view=new TextureRect{ExpandMode=TextureRect.ExpandModeEnum.IgnoreSize,StretchMode=TextureRect.StretchModeEnum.KeepAspectCentered};split.AddChild(view);void Update(long index){int at=0;foreach(var key in variants.Keys){if(at++!=index)continue;view.Texture=variants[key].As<Resource>().Get("preview").As<Texture2D>();return;}}select.ItemSelected+=Update;Update(0);popup.PopupHide+=popup.QueueFree;popup.PopupCentered();
    }
}
