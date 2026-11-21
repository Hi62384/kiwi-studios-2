using Godot;
using System;
using System.Linq;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;

public partial class ShaderBrowserOperations
{
    public void refresh(Control owner)
    {
        if(!owner.IsNodeReady())return;var grid=Node<GridContainer>(owner,"grid");foreach(var child in grid.GetChildren()){grid.RemoveChild(child);child.QueueFree();}Data(owner,"_cards").Clear();var kinds=new[]{"","canvas_item","spatial","sky","fog","particles"};var type=Node<OptionButton>(owner,"type_filter");var category=Node<OptionButton>(owner,"category_filter");int collection=Node<OptionButton>(owner,"collection_filter").Selected;string categoryName=category.Selected==0?"":category.GetItemText(category.Selected);var favorites=Strings(owner.Get("favorites"));var recent=Strings(owner.Get("recent"));var filtered=new List<Settings>();
        foreach(var value in owner.Get("entries").AsGodotArray()){var entry=value.AsGodotDictionary();if(matches(entry,Node<LineEdit>(owner,"search").Text,kinds[type.Selected],categoryName,owner.Get("templates_only").AsBool(),collection,favorites,recent))filtered.Add(entry);}if(collection==2)filtered.Sort((a,b)=>Array.IndexOf(recent,a["id"].AsString()).CompareTo(Array.IndexOf(recent,b["id"].AsString())));foreach(var entry in filtered)add_card(owner,entry);Node<Label>(owner,"count").Text=filtered.Count+" "+(owner.Get("templates_only").AsBool()?"templates":"samples");if(Data(owner,"selected").Count==0&&filtered.Count>0)select(owner,filtered[0]);else if(filtered.Count==0)Status(owner,"No matches. Try another category or search.");
    }
    public void add_card(Control owner,Settings entry)
    {
        var card=new Button {CustomMinimumSize=new Vector2(162,176),SizeFlagsHorizontal=Control.SizeFlags.ExpandFill,TooltipText=entry["description"].AsString(),ToggleMode=true};card.SetPressedNoSignal(Get(Data(owner,"selected"),"id","").AsString()==entry["id"].AsString());card.Pressed+=()=>{if(Fresh(owner,card))select(owner,entry);};Node<GridContainer>(owner,"grid").AddChild(card);var box=new VBoxContainer {MouseFilter=Control.MouseFilterEnum.Ignore};box.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect,Control.LayoutPresetMode.Minsize,7);card.AddChild(box);
        var image=new TextureRect {CustomMinimumSize=new Vector2(0,99),ExpandMode=TextureRect.ExpandModeEnum.IgnoreSize,StretchMode=TextureRect.StretchModeEnum.KeepAspectCentered,MouseFilter=Control.MouseFilterEnum.Ignore};box.AddChild(image);box.AddChild(new Label {Text=entry["name"].AsString(),TextOverrunBehavior=TextServer.OverrunBehavior.TrimEllipsis,MouseFilter=Control.MouseFilterEnum.Ignore});var caption=new Label {Text=entry["shader_type"].AsString().Replace("canvas_item","2D",StringComparison.Ordinal).Replace("spatial","3D",StringComparison.Ordinal)+" | "+entry["description"].AsString(),TextOverrunBehavior=TextServer.OverrunBehavior.TrimEllipsis,MouseFilter=Control.MouseFilterEnum.Ignore};caption.AddThemeFontSizeOverride("font_size",11);box.AddChild(caption);var message=new Label {Text="Preview queued",MouseFilter=Control.MouseFilterEnum.Ignore};message.AddThemeFontSizeOverride("font_size",10);box.AddChild(message);Data(owner,"_cards")[entry["id"].AsString()]=new Settings {["entry"]=entry,["card"]=card,["image"]=image,["message"]=message};string key=cache_key(entry);var textures=Data(owner,"_textures");var failures=Data(owner,"_failures");
        if(textures.TryGetValue(key,out var texture)){image.Texture=texture.As<Texture2D>();message.Text="Rendered preview";}else if(failures.TryGetValue(key,out var failure))message.Text=failure.AsString();else if(FileAccess.FileExists(Cache+key+".png")){using var cached=Image.LoadFromFile(Cache+key+".png");if(cached!=null&&!cached.IsEmpty()){image.Texture=ImageTexture.CreateFromImage(cached);textures[key]=image.Texture;message.Text="Rendered preview";}}
    }
    public void set_templates(Control owner,bool value)
    {owner.Set("templates_only",value);owner.Set("selected",new Settings());if(!owner.IsNodeReady())return;load_preferences(owner);Categories(owner);refresh(owner);}
    private static void Categories(Control owner)
    {var filter=Node<OptionButton>(owner,"category_filter");filter.Clear();filter.AddItem("All categories");var categories=new SortedSet<string>(StringComparer.Ordinal);foreach(var value in owner.Get("entries").AsGodotArray()){var entry=value.AsGodotDictionary();if(Get(entry,"template",false).AsBool()==owner.Get("templates_only").AsBool())categories.Add(entry["category"].AsString());}foreach(string category in categories)filter.AddItem(category);}
    public void select(Control owner,Settings entry)
    {if(entry.Count==0)return;var job=new ShaderBrowserJob();owner.AddChild(job);job.start(owner,"select",entry);}
    internal long BeginSelection(Control owner,Settings entry)
    {
        var selected=entry.Duplicate(true);owner.Set("selected",selected);foreach(var pair in Data(owner,"_cards"))pair.Value.AsGodotDictionary()["card"].As<Button>().SetPressedNoSignal(pair.Key.AsString()==entry["id"].AsString());selected["source"]=new ShaderSampleCatalogOperations().get_code(entry);long revision=owner.Get("_selection_revision").AsInt64()+1;owner.Set("_selection_revision",revision);owner.Set("_selection_busy",true);Node<Label>(owner,"heading").Text=entry["name"].AsString();Node<Label>(owner,"description").Text=entry["description"].AsString()+"\nSupports: "+Get(entry,"targets",entry["shader_type"]).AsString();Node<CodeEdit>(owner,"source").Text=selected["source"].AsString();Node<Button>(owner,"favorite").SetPressedNoSignal(Strings(owner.Get("favorites")).Contains(entry["id"].AsString()));var geometry=Node<OptionButton>(owner,"geometry");geometry.Visible=entry["shader_type"].AsString()=="spatial";geometry.Select(Math.Max(0,Array.IndexOf(new[]{"sphere","plane","cube"},Get(entry,"preview_mesh","sphere").AsString())));Node<Label>(owner,"preview_error").Hide();Node<TextureRect>(owner,"preview_display").Show();Status(owner,"");return revision;
    }
    internal void FinishSelection(Control owner)
    {var live=Live(owner);string error=live.check_errors();if(error.Length>0){var label=Node<Label>(owner,"preview_error");label.Text=error;label.Show();Node<TextureRect>(owner,"preview_display").Hide();}build_uniforms(owner);refresh_apply(owner);live.finish_compilation();owner.Set("_selection_busy",false);}
    public void process(Control owner,double delta)
    {
        if(!owner.IsNodeReady()||!owner.IsVisibleInTree())return;Node<GridContainer>(owner,"grid").Columns=Math.Max(1,(int)(Node<ScrollContainer>(owner,"card_scroll").Size.X/181));double timer=owner.Get("_apply_timer").AsDouble()+delta;if(timer>.7){timer=0;refresh_apply(owner);}owner.Set("_apply_timer",timer);if(owner.Get("_thumbnail_busy").AsBool()||owner.Get("_selection_busy").AsBool())return;var scroll=Node<ScrollContainer>(owner,"card_scroll").GetGlobalRect();foreach(var value in Data(owner,"_cards").Values){var info=value.AsGodotDictionary();if(info["image"].As<TextureRect>().Texture!=null||Data(owner,"_failures").ContainsKey(cache_key(info["entry"].AsGodotDictionary())))continue;if(info["card"].As<Button>().GetGlobalRect().Intersects(scroll)){render_thumbnail(owner,info["entry"].AsGodotDictionary());break;}}
    }
    public void render_thumbnail(Control owner,Settings entry)
    {var job=new ShaderBrowserJob();owner.AddChild(job);job.start(owner,"thumbnail",entry);}
    public void save_file(Control owner)
    {var selected=Data(owner,"selected");if(selected.Count==0)return;var job=new ShaderBrowserJob();owner.AddChild(job);job.start(owner,"save",selected.Duplicate(true));}
}
