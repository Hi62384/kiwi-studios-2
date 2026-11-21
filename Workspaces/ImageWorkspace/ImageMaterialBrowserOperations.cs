using Godot;
using System;
using System.Collections.Generic;
using GArray=Godot.Collections.Array;
using Settings=Godot.Collections.Dictionary;
public partial class ImageMaterialBrowserOperations:RefCounted
{
    private readonly ImageMaterialResourceOperations _resources=new();private readonly NaturalMaterialDefinitionOperations _definitions=new();private readonly NaturalMaterialPresetOperations _presets=new();private readonly NaturalMaterialEngineOperations _engine=new();private readonly ImageTextureMaterialRendererOperations _renderer=new();private readonly ImageDocumentOperations _documents=new();
    private const string History="user://natural_material_browser.tres";
    private static GDScript Bridge=>GD.Load<GDScript>("res://Workspaces/ImageWorkspace/texture_material_browser.gd");
    private static Variant Get(Settings d,string key,Variant fallback=default)=>d.TryGetValue(key,out var value)?value:fallback;
    private static Resource Value(Control owner)=>owner.Get("value").As<Resource>();
    private static Control? Studio(Control owner)=>owner.Get("studio").As<Control>();
    private static void Commit(Control owner)=>owner.EmitSignal("edit_committed");
    private static Button Button(Node parent,string text,System.Action callback){var button=new Button{Text=text};button.AddThemeFontSizeOverride("font_size",11);parent.AddChild(button);button.Pressed+=callback;return button;}
    private static void Clear(Node parent){foreach(var child in parent.GetChildren()){parent.RemoveChild(child);child.QueueFree();}}
    public void set_material_value(Control owner,Resource next){var value=_resources.copy_material(next);value.Set("coverage",default(Variant));value.Set("source",default(Variant));owner.Set("value",value);owner.Set("_original_value",_resources.copy_material(value));if(owner.IsNodeReady()){rebuild_fields(owner);update_preview(owner);}}
    public void refresh_from_layer(Control owner)
    {
        var studio=Studio(owner);if(studio==null)return;var document=studio.Get("document").As<Resource>();var active=_documents.live_material_for_id(document,document.Get("active_live_material_id").AsString());var tool=studio.Get("canvas").AsGodotObject().Get("repair_tool").AsGodotObject();if(document.Get("live_edit_enabled").AsBool()&&active!=null)tool.Set("material",_resources.copy_material(active.Get("material").As<Resource>()));set_material_value(owner,tool.Get("material").As<Resource>());
    }
    public void changed(Control owner){var studio=Studio(owner);if(studio!=null&&studio.Get("canvas").AsGodotObject().Get("_material_busy").AsBool()){set_material_value(owner,studio.Get("canvas").AsGodotObject().Get("repair_tool").AsGodotObject().Get("material").As<Resource>());return;}owner.EmitSignal("material_changed",_resources.copy_material(Value(owner)));update_preview(owner);}
    public void update_preview(Control owner)
    {
        var viewport=owner.Get("preview_viewport").As<SubViewport>();if(viewport==null)return;var original=owner.Get("_original_value").As<Resource>();using var copy=_resources.copy_material(owner.Get("_comparing").AsBool()&&original!=null?original:Value(owner));copy.Set("coverage",default(Variant));copy.Set("source",default(Variant));copy.Set("blending","replace");var shader=_renderer.material(copy,(Vector2)viewport.Size/owner.Get("preview_zoom").AsSingle(),Transform2D.Identity,true);shader.SetShaderParameter("origin",owner.Get("preview_pan"));viewport.GetChild<Control>(0).Material=shader;viewport.RenderTargetUpdateMode=SubViewport.UpdateMode.Once;
    }
    public void reload_shared_presets(Control owner){var custom=owner.Get("custom_materials").AsGodotDictionary();foreach(var item in _presets.list_presets()){string id=item.AsGodotDictionary()["id"].AsString();var saved=_presets.load_material(id);if(saved!=null)custom[id]=saved;}}
    public void load_history(Control owner){if(!FileAccess.FileExists(History))return;var saved=ResourceLoader.Load(History,"",ResourceLoader.CacheMode.Ignore);if(saved==null)return;owner.Set("favorites",saved.GetMeta("favorites",Array.Empty<string>()));owner.Set("recent",saved.GetMeta("recent",Array.Empty<string>()));owner.Set("custom_materials",saved.GetMeta("custom",new Settings()).AsGodotDictionary().Duplicate());}
    public void save_history(Control owner){using var saved=new Resource();saved.SetMeta("favorites",owner.Get("favorites"));saved.SetMeta("recent",owner.Get("recent"));saved.SetMeta("custom",owner.Get("custom_materials"));ResourceSaver.Save(saved,History);}
    public void save_material(Control owner,bool asNew){string id=_presets.save_material(Value(owner),asNew?"":owner.Get("active_path").AsString());if(id.Length==0)return;owner.Set("active_path",id);owner.Get("custom_materials").AsGodotDictionary()[id]=_resources.copy_material(Value(owner));save_history(owner);owner.Call("refresh_grid");}
    public void complete_load(Control owner,string path)
    {
        var loaded=ResourceLoader.Load(path,"",ResourceLoader.CacheMode.Ignore);if(loaded is not KiwiTextureMaterial)return;string id=_presets.import_file(path);owner.Set("active_path",id);if(id.Length==0)return;owner.Get("custom_materials").AsGodotDictionary()[id]=_resources.copy_material(loaded);set_material_value(owner,loaded);changed(owner);Commit(owner);save_history(owner);owner.Call("refresh_grid");
    }
    public void complete_image(Control owner,string path){using var bitmap=Image.LoadFromFile(path);if(bitmap==null)return;bitmap.GenerateMipmaps();using var imported=_definitions.create("geometry/checkerboard");imported.Set("label",path.GetFile());imported.Set("image",ImageTexture.CreateFromImage(bitmap));owner.Set("active_path","");set_material_value(owner,imported);changed(owner);Commit(owner);}
    public bool begin_close(Control owner){if(owner.Get("_closed").AsBool())return false;if(owner.Get("_comparing").AsBool())compare(owner,false);owner.Set("_closed",true);owner.Set("_filter_generation",owner.Get("_filter_generation").AsInt64()+1);owner.Name="ClosingMaterialBrowser";owner.Hide();restore_sidebar(owner);Commit(owner);save_history(owner);return true;}
    public void restore_sidebar(Control owner){var studio=Studio(owner);double width=owner.Get("_sidebar_width").AsDouble();if(width>=0&&GodotObject.IsInstanceValid(studio)){var split=studio!.Get("_side_split").As<Control>();split.CustomMinimumSize=new Vector2((float)width,split.CustomMinimumSize.Y);owner.Set("_sidebar_width",-1.0);}}
    public void exit_tree(Control owner){owner.Set("_closed",true);owner.Set("_filter_generation",owner.Get("_filter_generation").AsInt64()+1);restore_sidebar(owner);}
    public void preview_input(Control owner,InputEvent input)
    {
        if(input is InputEventMouseButton button){if(button.ButtonIndex==MouseButton.Middle)owner.Set("preview_drag",button.Pressed);if(button.Pressed&&button.ButtonIndex is MouseButton.WheelUp or MouseButton.WheelDown){owner.Set("preview_zoom",Math.Clamp(owner.Get("preview_zoom").AsDouble()*(button.ButtonIndex==MouseButton.WheelUp?1.2:1/1.2),.1,16));update_preview(owner);}}
        if(input is InputEventMouseMotion motion&&owner.Get("preview_drag").AsBool()){owner.Set("preview_pan",owner.Get("preview_pan").AsVector2()-motion.Relative/owner.Get("preview_zoom").AsSingle());update_preview(owner);}
    }
    public void compare(Control owner,bool enabled)
    {
        owner.Set("_comparing",enabled);update_preview(owner);var studio=Studio(owner);if(studio==null)return;var document=studio.Get("document").As<Resource>();if(!document.Get("live_edit_enabled").AsBool())return;var renderer=studio.Get("renderer").AsGodotObject();var original=owner.Get("_original_value").As<Resource>();if(enabled&&original!=null){var comparison=_documents.snapshot(document);_documents.set_live_material(comparison,comparison.Get("active_live_material_id").AsString(),original);renderer.Call("sync",comparison);studio.Set("_refresh_pending",false);}else renderer.Call("sync",document);var canvas=studio.Get("canvas").As<Control>();canvas.Set("preview",renderer.Call("texture"));canvas.QueueRedraw();
    }
    public void show_catalog(Control owner,bool browse){owner.Get("catalog_panel").As<Control>().Visible=browse;owner.Get("settings_scroll").As<Control>().Visible=!browse;owner.Get("browse_tab").As<Button>().Disabled=browse;owner.Get("settings_tab").As<Button>().Disabled=!browse;if(browse)owner.Call("refresh_grid");else owner.Set("_filter_generation",owner.Get("_filter_generation").AsInt64()+1);}
    public Settings prepare_grid(Control owner)
    {
        long request=owner.Get("_filter_generation").AsInt64()+1;owner.Set("_filter_generation",request);if(!owner.Get("catalog_panel").As<Control>().Visible)return new Settings();var grid=owner.Get("grid").As<GridContainer>();Clear(grid);var builtin=_definitions.ids();var ids=builtin.Duplicate();var custom=owner.Get("custom_materials").AsGodotDictionary();string category=owner.Get("category").AsString();if(category is "All" or "Custom" or "Favorites")foreach(var id in custom.Keys)ids.Add(id);if(category=="Custom"){ids.Clear();foreach(var id in custom.Keys)ids.Add(id);}if(category=="Recent"){ids.Clear();foreach(var id in owner.Get("recent").AsStringArray())ids.Add(id);}var favorites=owner.Get("favorites").AsStringArray();string query=owner.Get("search").As<LineEdit>().Text.ToLowerInvariant();var jobs=new GArray();var thumbnails=Bridge.Get("thumbnails").AsGodotDictionary();
        foreach(var candidate in ids)
        {
            string id=candidate.AsString();bool isCustom=custom.ContainsKey(id);if(!isCustom&&!builtin.Contains(id))continue;if(category=="Favorites"&&Array.IndexOf(favorites,id)<0)continue;if(category is not ("All" or "Favorites" or "Recent" or "Custom")&&(isCustom||_definitions.category(id)!=category))continue;var sample=isCustom?custom[id].As<Resource>():_definitions.create(id);if(query.Length>0&&!(sample.Get("label").AsString()+" "+sample.Get("material_id").AsString()).ToLowerInvariant().Contains(query,StringComparison.Ordinal))continue;
            var card=new VBoxContainer{CustomMinimumSize=new Vector2(98,0)};grid.AddChild(card);var button=new Button{Text="",ClipText=true,CustomMinimumSize=new Vector2(100,74),ExpandIcon=true,TooltipText=sample.Get("label").AsString()+" / "+_definitions.category(sample.Get("material_id").AsString())};button.AddThemeConstantOverride("icon_max_width",78);card.AddChild(button);
            button.Pressed+=()=>{Commit(owner);owner.Set("active_path",isCustom?id:"");set_material_value(owner,sample);changed(owner);Commit(owner);show_catalog(owner,false);var recent=new List<string>(owner.Get("recent").AsStringArray());recent.Remove(id);recent.Insert(0,id);if(recent.Count>24)recent.RemoveRange(24,recent.Count-24);owner.Set("recent",recent.ToArray());save_history(owner);};
            var caption=new Label{Text=sample.Get("label").AsString(),CustomMinimumSize=new Vector2(98,0),TextOverrunBehavior=TextServer.OverrunBehavior.TrimEllipsis};caption.AddThemeFontSizeOverride("font_size",11);card.AddChild(caption);
            var star=Button(card,Array.IndexOf(favorites,id)>=0?"Favorite *":"Favorite",()=>{var list=new List<string>(owner.Get("favorites").AsStringArray());if(!list.Remove(id))list.Add(id);owner.Set("favorites",list.ToArray());save_history(owner);owner.Call("refresh_grid");});star.TooltipText="Favorite "+sample.Get("label").AsString();string key=GD.Hash(_engine.settings_from_material(sample)).ToString();if(thumbnails.ContainsKey(key))button.Icon=thumbnails[key].As<Texture2D>();else jobs.Add(new Settings{["sample"]=sample,["button"]=button,["key"]=key});
        }
        return new Settings{["request"]=request,["jobs"]=jobs};
    }
    public bool complete_thumbnail(Control owner,long request,Settings job,Image? bitmap)
    {
        if(owner.Get("_closed").AsBool()||request!=owner.Get("_filter_generation").AsInt64())return false;var button=job["button"].As<Button>();if(bitmap!=null&&GodotObject.IsInstanceValid(button)){var thumbnails=Bridge.Get("thumbnails").AsGodotDictionary();if(thumbnails.Count>192)thumbnails.Remove(thumbnails.Keys.GetEnumerator().First());var texture=ImageTexture.CreateFromImage(bitmap);thumbnails[job["key"]]=texture;button.Icon=texture;}return true;
    }
}
