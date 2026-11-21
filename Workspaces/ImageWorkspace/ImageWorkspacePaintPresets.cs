using Godot;
using System;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;
public partial class ImageWorkspaceOperations
{
    public Settings preset(string label,double size,double opacity,double hardness,Color color,double threshold)=>new(){["id"]=NewId(),["name"]=label,["size"]=size,["opacity"]=opacity,["hardness"]=hardness,["color"]=color,["threshold"]=threshold,["mode"]="freehand"};
    public Settings current_paint_preset(Control owner,string label)
    {
        var canvas=Canvas(owner);var result=preset(label,canvas.Get("brush_size").AsDouble(),canvas.Get("brush_opacity").AsDouble(),canvas.Get("hardness").AsDouble(),canvas.Get("color").AsColor(),canvas.Get("fill_threshold").AsDouble());
        if(canvas.Get("tool").AsString()=="brush")foreach(string key in new[]{"stroke_correct","correction_strength","correction_scale","brush_type","soften_strength"})result[key]=canvas.Get(key);
        result["mode"]=canvas.Get("brush_mode");result["painting_mode"]=canvas.Get("painting_mode");result["material_strength"]=canvas.Get("material_strength");result["selection_only"]=canvas.Get("paint_selection_only");result["new_layer"]=canvas.Get("paint_new_layer");
        if(canvas.Get("painting_mode").AsString()=="material")result["material"]=_materials.copy_material(canvas.Get("repair_tool").As<RefCounted>().Get("material").As<Resource>());return result;
    }
    public void persist_paint_presets(Control owner,string path)
    {
        using var library=new Resource();library.SetMeta("presets",owner.Get("_paint_presets"));var canvas=Canvas(owner);foreach(string key in new[]{"stroke_correct","correction_strength","correction_scale","brush_type","soften_strength"})library.SetMeta(key,canvas.Get(key));ResourceSaver.Save(library,path);
    }
    private static void PresetsChanged(Control owner,string message=""){owner.Call("_persist_paint_presets");owner.Call("_refresh_context");if(message.Length>0)owner.Get("status").As<Label>().Text=message;}
    public void save_paint_preset(Control owner,string kind,bool asNew)
    {
        var all=owner.Get("_paint_presets").AsGodotDictionary();var active=owner.Get("_active_preset").AsGodotDictionary();string id=Get(active,kind,"").AsString();var list=Get(all,kind,new GArray()).AsGodotArray();
        if(!asNew&&id.Length>0)for(int index=0;index<list.Count;index++){if(list[index].VariantType!=Variant.Type.Dictionary)continue;var previous=list[index].AsGodotDictionary();if(Get(previous,"id","").AsString()!=id)continue;var updated=current_paint_preset(owner,Get(previous,"name","Preset").AsString());updated["id"]=id;updated["favorite"]=Get(previous,"favorite",false);list[index]=updated;all[kind]=list;PresetsChanged(owner,"Preset updated");return;}
        var created=current_paint_preset(owner,kind.Capitalize()+" "+(list.Count+1));list.Add(created);all[kind]=list;active[kind]=created["id"];PresetsChanged(owner,"Preset saved");
    }
    public void delete_paint_preset(Control owner,string kind,string id)
    {
        var all=owner.Get("_paint_presets").AsGodotDictionary();var list=Get(all,kind,new GArray()).AsGodotArray();for(int i=list.Count-1;i>=0;i--)if(list[i].VariantType==Variant.Type.Dictionary&&Get(list[i].AsGodotDictionary(),"id","").AsString()==id)list.RemoveAt(i);all[kind]=list;var active=owner.Get("_active_preset").AsGodotDictionary();if(Get(active,kind,"").AsString()==id)active[kind]="";PresetsChanged(owner);
    }
    public void move_preset(Control owner,string kind,string source,string target)
    {
        var list=owner.Get("_paint_presets").AsGodotDictionary()[kind].AsGodotArray();int from=-1,to=-1;for(int i=0;i<list.Count;i++){var entry=list[i].AsGodotDictionary();string id=Get(entry,"id","").AsString();if(id==source)from=i;if(id==target)to=i;}if(from<0||to<0||from==to)return;var moved=list[from];list.RemoveAt(from);list.Insert(to,moved);PresetsChanged(owner);
    }
    public Texture2D? paint_preset_icon(Settings data,string kind)
    {
        var material=Get(data,"material");if(material.VariantType==Variant.Type.Object&&material.AsGodotObject()!=null)return null;
        using var bitmap=Image.CreateEmpty(64,40,false,Image.Format.Rgba8);bitmap.Fill(new Color("15212d"));var color=Get(data,"color",Colors.White).AsColor();if(kind=="fill"){for(int y=5;y<35;y++)for(int x=5;x<59;x++)bitmap.SetPixel(x,y,color);}else{float radius=Math.Clamp(Get(data,"size",28).AsSingle()/7,3,15),hard=Get(data,"hardness",1).AsSingle(),opacity=Get(data,"opacity",1).AsSingle();for(int y=0;y<40;y++)for(int x=0;x<64;x++){float distance=new Vector2(x-32,y-20).Length()/radius;if(distance>1)continue;var pixel=color;pixel.A=opacity*Math.Clamp((1-distance)/Math.Max(.001f,1-hard),0,1);bitmap.SetPixel(x,y,pixel);}}return ImageTexture.CreateFromImage(bitmap);
    }
    public void apply_paint_preset(Control owner,string kind,Settings data)
    {
        var canvas=Canvas(owner);if(canvas.Get("_material_busy").AsBool())return;_canvas.cancel_gesture(canvas);
        foreach(var pair in new[]{("size","brush_size"),("opacity","brush_opacity"),("hardness","hardness"),("threshold","fill_threshold"),("color","color"),("selection_only","paint_selection_only"),("new_layer","paint_new_layer")})canvas.Set(pair.Item2,Get(data,pair.Item1,canvas.Get(pair.Item2)));
        owner.Get("color_picker").As<ColorPickerButton>().Color=canvas.Get("color").AsColor();canvas.Set("painting_mode",Get(data,"painting_mode","color"));canvas.Set("material_strength",Get(data,"material_strength",1.0));var repair=canvas.Get("repair_tool").As<RefCounted>();var material=Get(data,"material");if(material.VariantType==Variant.Type.Object&&material.AsGodotObject() is Resource resource){repair.Set("material",_materials.copy_material(resource));Document(owner).Set("live_edit_enabled",false);}owner.GetNodeOrNull("MaterialBrowser")?.Call("set_material_value",repair.Get("material"));
        if(kind=="brush"){foreach(string key in new[]{"stroke_correct","brush_type"})canvas.Set(key,Get(data,key,canvas.Get(key)));foreach(string key in new[]{"soften_strength","correction_strength"})canvas.Set(key,Math.Clamp(Get(data,key,canvas.Get(key)).AsDouble(),0,1));canvas.Set("correction_scale",Math.Clamp(Get(data,"correction_scale",canvas.Get("correction_scale")).AsDouble(),.1,16));owner.Call("_persist_paint_presets");}owner.Get("_active_preset").AsGodotDictionary()[kind]=Get(data,"id","");owner.Call("_refresh_context");canvas.QueueRedraw();
    }
    public void load_paint_presets(Control owner,string path)
    {
        var canvas=Canvas(owner);var all=owner.Get("_paint_presets").AsGodotDictionary();if(FileAccess.FileExists(path)){var saved=ResourceLoader.Load<Resource>(path,"",ResourceLoader.CacheMode.Ignore);if(saved!=null){canvas.Set("stroke_correct",saved.GetMeta("stroke_correct",false));canvas.Set("brush_type",saved.GetMeta("brush_type",canvas.Get("brush_type")));foreach(string key in new[]{"soften_strength","correction_strength"})canvas.Set(key,Math.Clamp(saved.GetMeta(key,.5).AsDouble(),0,1));canvas.Set("correction_scale",Math.Clamp(saved.GetMeta("correction_scale",1.0).AsDouble(),.1,16));var stored=saved.GetMeta("presets",new Settings());if(stored.VariantType==Variant.Type.Dictionary){var data=stored.AsGodotDictionary();foreach(string key in new[]{"brush","eraser","fill"})if(data.ContainsKey(key)&&data[key].VariantType==Variant.Type.Array)all[key]=data[key];}}}
        var mint=new Color("62d9bc");if(all["brush"].AsGodotArray().Count==0){var list=new GArray{preset("Hard round",28,1,1,mint,.08),preset("Soft round",54,.5,.12,mint,.08),preset("Pencil",3,1,1,new Color("d7e8ef"),.08)};foreach(string id in new[]{"wood/oak","fabric/denim","stone/marble"}){var material=NaturalMaterialCatalog.create(id);var entry=preset(material.Get("label").AsString(),48,1,.8,Colors.White,.08);entry["painting_mode"]="material";entry["material"]=material;entry["material_strength"]=1.0;list.Add(entry);}all["brush"]=list;}
        if(all["eraser"].AsGodotArray().Count==0)all["eraser"]=new GArray{preset("Hard eraser",32,1,1,Colors.White,.08),preset("Soft eraser",70,.55,.08,Colors.White,.08)};if(all["fill"].AsGodotArray().Count==0)all["fill"]=new GArray{preset("Exact fill",1,1,1,mint,.01),preset("Soft range",1,1,1,mint,.14)};
    }
    public void paint_preset_controls(Control owner,string kind)
    {
        owner.Get("preset_panel").As<Control>().Visible=true;var host=owner.Get("preset_context").As<HBoxContainer>();var caption=new Label{Text=kind.Capitalize()+" presets",CustomMinimumSize=new Vector2(95,0)};caption.AddThemeColorOverride("font_color",new Color("7fcfbe"));host.AddChild(caption);var filter=new OptionButton{Name="PaintPresetFilter"};foreach(string name in new[]{"All","Color","Material"})filter.AddItem(name);string[] filters={"all","color","material"};filter.Select(Math.Max(0,Array.IndexOf(filters,owner.Get("_preset_filter").AsString())));host.AddChild(filter);filter.ItemSelected+=index=>{owner.Set("_preset_filter",filters[(int)index]);owner.Call("_refresh_context");};
        foreach(bool asNew in new[]{false,true}){var save=new Button{Text=asNew?"Save +":"Save",TooltipText=asNew?"Save these settings as a new preset":"Update the selected preset, or create one",CustomMinimumSize=new Vector2(0,32),FocusMode=Control.FocusModeEnum.None};host.AddChild(save);save.Pressed+=()=>save_paint_preset(owner,kind,asNew);}
        var scroll=new ScrollContainer{CustomMinimumSize=new Vector2(220,34),SizeFlagsHorizontal=Control.SizeFlags.ExpandFill,HorizontalScrollMode=ScrollContainer.ScrollMode.Auto,VerticalScrollMode=ScrollContainer.ScrollMode.Disabled};host.AddChild(scroll);var row=new HBoxContainer();row.AddThemeConstantOverride("separation",5);scroll.AddChild(row);int number=0;
        foreach(var value in owner.Get("_paint_presets").AsGodotDictionary()[kind].AsGodotArray()){if(value.VariantType!=Variant.Type.Dictionary)continue;var data=value.AsGodotDictionary();string selectedFilter=owner.Get("_preset_filter").AsString();if(selectedFilter!="all"&&Get(data,"painting_mode","color").AsString()!=selectedFilter)continue;string id=Get(data,"id","").AsString();var button=owner.Call("_new_preset_button",kind,id).As<Button>();bool favorite=Get(data,"favorite",false).AsBool();button.Text=(favorite?"*":"")+(number<10?number.ToString():"");button.Icon=paint_preset_icon(data,kind);button.ExpandIcon=true;button.CustomMinimumSize=new Vector2(64,32);button.TooltipText=(favorite?"Favorite / ":"")+Get(data,"name","Preset").AsString()+" · Drag to reorder · Right-click for Rename / Duplicate / Favorite / Delete"+(number<10?" · Key "+number:"");number++;if(Get(owner.Get("_active_preset").AsGodotDictionary(),kind,"").AsString()==id)button.AddThemeStyleboxOverride("normal",box(new Color("245d54"),new Color("79e5ce"),6,2));row.AddChild(button);button.Pressed+=()=>apply_paint_preset(owner,kind,data);var material=Get(data,"material");if(material.VariantType==Variant.Type.Object&&material.AsGodotObject()!=null)owner.Call("_material_icon_for",button,material);button.GuiInput+=input=>{if(input is InputEventMouseButton mouse&&mouse.ButtonIndex==MouseButton.Right&&mouse.Pressed)owner.Call("_paint_preset_menu",kind,data);};}
    }

    public void name_dialog(Control owner,string title,string current,Variant callback)
    {
        var dialog=new ConfirmationDialog{Title=title};owner.AddChild(dialog);var entry=new LineEdit{Text=current,CustomMinimumSize=new Vector2(280,32)};dialog.AddChild(entry);dialog.Confirmed+=()=>{if(entry.Text.Trim().Length>0){Invoke(owner,callback,entry.Text.Trim());dialog.QueueFree();}};dialog.Canceled+=dialog.QueueFree;dialog.PopupCentered();entry.GrabFocus();entry.SelectAll();
    }
    public void paint_preset_menu(Control owner,string kind,Settings data)
    {
        var menu=new PopupMenu();owner.AddChild(menu);menu.AddItem("Rename",0);menu.AddItem("Duplicate",1);menu.AddCheckItem("Favorite",2);menu.SetItemChecked(2,Get(data,"favorite",false).AsBool());menu.AddItem("Delete",3);menu.IdPressed+=action=>{switch(action){case 0:name_dialog(owner,"Rename Brush Preset",Get(data,"name","Preset").AsString(),Callable.From<string>(text=>{data["name"]=text;PresetsChanged(owner);}));break;case 1:var copy=data.Duplicate(true);copy["id"]=NewId();copy["name"]=Get(data,"name","Preset").AsString()+" copy";var material=ResourceValue(Get(data,"material"));if(ScriptIs(material,"res://Workspaces/ImageWorkspace/texture_material.gd"))copy["material"]=_materials.copy_material(material!);owner.Get("_paint_presets").AsGodotDictionary()[kind].AsGodotArray().Add(copy);PresetsChanged(owner);break;case 2:data["favorite"]=!Get(data,"favorite",false).AsBool();PresetsChanged(owner);break;default:delete_paint_preset(owner,kind,Get(data,"id","").AsString());break;}};menu.PopupHide+=menu.QueueFree;menu.Position=(Vector2I)owner.GetGlobalMousePosition();menu.Popup();
    }

}
