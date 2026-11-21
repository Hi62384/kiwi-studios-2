using Godot;
using System;
using System.Collections.Generic;
using System.Globalization;
using GArray=Godot.Collections.Array;
using Settings=Godot.Collections.Dictionary;
public partial class AudioLibraryOperations:RefCounted
{
    private const string ConfigPath="user://audio_workspace/library.cfg";
    private static Variant Get(Settings d,string key,Variant fallback=default)=>d.TryGetValue(key,out var v)?v:fallback;
    private static string S(Settings d,string key,string fallback="")=>Get(d,key,fallback).AsString();
    private static bool B(Settings d,string key)=>Get(d,key,false).AsBool();
    private static T Field<T>(GodotObject o,string key) where T:GodotObject=>(T)o.Get(key).AsGodotObject();
    private static GArray Items(GodotObject o,string key)=>o.Get(key).AsGodotArray();
    private static Settings Dict(GodotObject o,string key)=>o.Get(key).AsGodotDictionary();
    private static void Assign(GArray target,GArray source){target.Clear();foreach(var raw in source)target.Add(raw);}
    private static string[] Strings(Variant value)=>value.VariantType==Variant.Type.PackedStringArray?value.AsStringArray():Array.Empty<string>();
    private static bool PresetResource([System.Diagnostics.CodeAnalysis.NotNullWhen(true)] Resource? resource){if(resource==null)return false;var script=resource.GetScript().AsGodotObject() as Script;var expected=GD.Load<CSharpScript>("res://Workspaces/AudioWorkspace/KiwiAudioPreset.cs");while(script!=null){if(script==expected)return true;script=script.GetBaseScript();}return false;}
    public string[] clean_tags(Variant value)
    {
        var result=new List<string>();var seen=new HashSet<string>(StringComparer.OrdinalIgnoreCase);void Add(string text){string tag=text.Trim();if(tag.Length>0&&seen.Add(tag))result.Add(tag);}
        if(value.VariantType==Variant.Type.Array){foreach(var raw in value.AsGodotArray())if(raw.VariantType is Variant.Type.String or Variant.Type.StringName)Add(raw.AsString());}else if(value.VariantType==Variant.Type.PackedStringArray)foreach(string tag in value.AsStringArray())Add(tag);return result.ToArray();
    }
    public string[] preset_tags(Resource preset){if(preset==null)return Array.Empty<string>();var tags=clean_tags(preset.Get("tags"));return tags.Length>0?tags:clean_tags(Get(preset.Get("data").AsGodotDictionary(),"tags",new GArray()));}
    public void reload(Control o)
    {
        var entries=Items(o,"entries");entries.Clear();using var synth=new AudioSynthesisOperations();foreach(var preset in synth.presets()){var entry=preset.Duplicate(true);entry["kind"]="generator";entries.Add(entry);}using var instruments=new AudioInstrumentOperations();foreach(var preset in instruments.presets()){var entry=preset.Duplicate(true);entry["kind"]="instrument";entry["category"]="Instruments";entries.Add(entry);}using var templates=new AudioTemplateOperations();foreach(string label in templates.names())entries.Add(new Settings{["id"]="template_"+label,["label"]=label,["kind"]="template",["category"]="Templates"});
        var indexed=new Settings();foreach(var raw in Items(o,"_project_entries"))indexed[S(raw.AsGodotDictionary(),"id")]=raw;
        foreach(var raw in Items(o,"imported")){var entry=raw.AsGodotDictionary().Duplicate(true);entry["origin"]="imported";string id=S(entry,"id");if(indexed.ContainsKey(id)){entry["project_member"]=true;entry["description"]=S(entry,"description",S(entry,"source"))+"\nAlso included in the project index.";indexed.Remove(id);}entries.Add(entry);}foreach(var raw in indexed.Values)entries.Add(raw);
        using var directory=DirAccess.Open("user://audio_workspace/presets");if(directory!=null)foreach(string file in directory.GetFiles()){if(file.GetExtension()!="tres"||file.Contains(".tags-writing-"))continue;string path="user://audio_workspace/presets/"+file;var preset=ResourceLoader.Load(path,"",ResourceLoader.CacheMode.Ignore);if(!PresetResource(preset))continue;string folder=preset.Get("folder").AsString();entries.Add(new Settings{["id"]=preset.Get("id"),["label"]=preset.Get("label"),["kind"]="preset",["category"]="Presets"+(folder.Length>0?" / "+folder:""),["preset"]=preset,["path"]=path,["preset_kind"]=preset.Get("kind"),["tags"]=preset_tags(preset)});}
        o.Call("_update_tag_filter");refresh(o);
    }
    public void refresh(Control o)
    {
        string selectedId=S(Dict(o,"current"),"id");var list=Field<ItemList>(o,"list");list.Clear();string query=Field<LineEdit>(o,"search").Text.ToLowerInvariant().Trim();var category=Field<OptionButton>(o,"category");string filter=category.GetItemText(category.Selected);var kindControl=Field<OptionButton>(o,"_preset_kind_filter");var tagControl=Field<OptionButton>(o,"_tag_filter");string presetKind=kindControl.Selected>=0?kindControl.GetSelectedMetadata().AsString():"",tagFilter=tagControl.Selected>=0?tagControl.GetSelectedMetadata().AsString():"";var filtered=new List<Settings>();var favorites=Dict(o,"favorites");var recent=Items(o,"recent");
        foreach(var raw in Items(o,"entries"))
        {
            var entry=raw.AsGodotDictionary();string id=S(entry,"id"),kind=S(entry,"kind");var tags=kind=="preset"?Strings(Get(entry,"tags",Array.Empty<string>())):Array.Empty<string>();if(query.Length>0&&!(S(entry,"label")+" "+S(entry,"category")+" "+S(entry,"description")+" "+S(entry,"source")+" "+S(entry,"path")+" "+S(entry,"preset_kind")+" "+string.Join(" ",tags)).ToLowerInvariant().Contains(query))continue;if(presetKind.Length>0&&(kind!="preset"||S(entry,"preset_kind")!=presetKind))continue;
            if(tagFilter.Length>0){if(kind!="preset")continue;if(tagFilter=="untagged"&&tags.Length>0)continue;if(tagFilter.StartsWith("tag:")&&!Array.Exists(tags,tag=>tag.ToLowerInvariant()==tagFilter[4..]))continue;}
            if(filter=="Sound Effects"&&kind!="generator"||filter=="Instruments"&&kind!="instrument"||filter=="Imported"&&(kind!="asset"||S(entry,"origin","imported")!="imported")||filter=="Project"&&!B(entry,"project_indexed")&&!B(entry,"project_member")||filter=="Presets"&&kind!="preset"||filter=="Templates"&&kind!="template"||filter=="Favorites"&&!favorites.ContainsKey(id)||filter=="Recent"&&!recent.Contains(id))continue;filtered.Add(entry);
        }
        filtered.Sort((a,b)=>filter=="Recent"?recent.IndexOf(S(a,"id")).CompareTo(recent.IndexOf(S(b,"id"))):StringComparer.Ordinal.Compare(S(a,"category")+S(a,"label"),S(b,"category")+S(b,"label")));o.Set("current",new Settings());
        foreach(var entry in filtered)
        {
            string id=S(entry,"id"),label=S(entry,"label"),text=(favorites.ContainsKey(id)?"\u2605 ":"")+label,tooltip=S(entry,"category","Audio")+"\n"+S(entry,"description",label);if(S(entry,"kind")=="preset"){var tags=Strings(Get(entry,"tags",Array.Empty<string>()));text+=" · "+S(entry,"preset_kind","preset").Capitalize();tooltip+="\nPreset kind: "+S(entry,"preset_kind")+"\nTags: "+(tags.Length==0?"none":string.Join(", ",tags))+"\n"+S(entry,"path");}if(entry.ContainsKey("duration"))text+="  "+(B(entry,"duration_estimated")?"~":"")+entry["duration"].AsDouble().ToString("F2",CultureInfo.InvariantCulture)+"s";if(B(entry,"project_indexed")&&S(entry,"asset_state","unverified")!="available")text+=" · "+S(entry,"asset_state","unverified");int index=list.AddItem(text);list.SetItemMetadata(index,entry);list.SetItemTooltip(index,tooltip);if(id==selectedId){o.Set("current",entry);list.Select(index);}
        }
        update_actions(o);var current=Dict(o,"current");if(selectedId.Length>0&&(current.Count==0||B(current,"project_indexed")))o.EmitSignal("selected",current);
    }
    public void selected(Control o,int position){o.Set("current",Field<ItemList>(o,"list").GetItemMetadata(position));remember(o,S(Dict(o,"current"),"id"));update_actions(o);o.EmitSignal("selected",o.Get("current"));}
    public void update_actions(Control o){var current=Dict(o,"current");bool unavailable=current.Count==0||B(current,"project_indexed")&&S(current,"asset_state","unverified")!="available";Field<Button>(o,"_preview_button").Disabled=unavailable;Field<Button>(o,"_add_button").Disabled=unavailable;}
    public bool can_use_current(Control o){var current=Dict(o,"current");if(current.Count==0)return false;using var index=new AudioAssetIndexOperations();if(B(current,"project_indexed")&&!index.usable(current)){Field<Label>(o,"_scan_status").Text="Project asset is missing, unreadable or blocked. Refresh its folder.";return false;}return true;}
    public void remember(Control o,string id){var recent=Items(o,"recent");recent.Remove(id);recent.Insert(0,id);if(recent.Count>40)recent.Resize(40);save(o,"recent",id);}
    public void add_asset(Control o,Variant source,string label,double duration){if(source.VariantType!=Variant.Type.String)return;string id="asset_"+source.AsString().Sha256Text();foreach(var raw in Items(o,"imported"))if(S(raw.AsGodotDictionary(),"id")==id)return;Items(o,"imported").Add(new Settings{["id"]=id,["label"]=label,["kind"]="asset",["category"]="Imported",["source"]=source,["duration"]=duration});save(o,"imported",id);reload(o);}
    public void toggle_favorite(Control o){var current=Dict(o,"current");if(current.Count==0)return;string id=S(current,"id");var favorites=Dict(o,"favorites");if(favorites.ContainsKey(id))favorites.Remove(id);else favorites[id]=true;save(o,"favorites",id);refresh(o);}
    public void save(Control o,string field,string changedId)
    {
        using var config=new ConfigFile();var loaded=config.Load(ConfigPath);if(loaded!=Error.Ok&&loaded!=Error.FileNotFound){Field<Label>(o,"_scan_status").Text="Library settings could not be read; existing settings were not overwritten.";return;}
        switch(field)
        {
            case "favorites":{var saved=config.GetValue("library","favorites",new Settings());var merged=saved.VariantType==Variant.Type.Dictionary?saved.AsGodotDictionary().Duplicate(true):new Settings();if(Dict(o,"favorites").ContainsKey(changedId))merged[changedId]=true;else merged.Remove(changedId);o.Set("favorites",merged);config.SetValue("library","favorites",merged);break;}
            case "recent":{var saved=config.GetValue("library","recent",new GArray());var merged=new GArray{changedId};if(saved.VariantType==Variant.Type.Array)foreach(var raw in saved.AsGodotArray())if(raw.VariantType==Variant.Type.String&&merged.Count<40&&!merged.Contains(raw))merged.Add(raw);foreach(var raw in Items(o,"recent"))if(merged.Count<40&&!merged.Contains(raw))merged.Add(raw);Assign(Items(o,"recent"),merged);config.SetValue("library","recent",Items(o,"recent"));break;}
            case "imported":{var saved=config.GetValue("library","imported",new GArray());var merged=new GArray();if(saved.VariantType==Variant.Type.Array)foreach(var raw in saved.AsGodotArray())if(raw.VariantType==Variant.Type.Dictionary)merged.Add(raw.AsGodotDictionary().Duplicate(true));foreach(var raw in Items(o,"imported")){var entry=raw.AsGodotDictionary();bool exists=false;foreach(var other in merged)if(S(other.AsGodotDictionary(),"id")==S(entry,"id"))exists=true;if(!exists)merged.Add(entry.Duplicate(true));}Assign(Items(o,"imported"),merged);config.SetValue("library","imported",Items(o,"imported"));break;}
            case "project_index":config.SetValue("project_index",o.Get("_project_key").AsString(),o.Get("_project_roots"));break;
            default:return;
        }
        var error=DirAccess.MakeDirRecursiveAbsolute(ProjectSettings.GlobalizePath("user://audio_workspace"));if(error==Error.Ok)error=config.Save(ConfigPath);if(error!=Error.Ok)Field<Label>(o,"_scan_status").Text="Library settings could not be saved; session changes are still available.";
    }
    public Godot.Collections.Array<Settings> ranked_effects(Control o)
    {
        using var effects=new AudioEffectsOperations();var definitions=effects.catalog();var sorted=new List<Settings>();foreach(var entry in definitions)sorted.Add(entry);var recent=Items(o,"recent");sorted.Sort((a,b)=>{int ai=recent.IndexOf("effect_"+S(a,"id")),bi=recent.IndexOf("effect_"+S(b,"id"));if(ai<0)ai=100000;if(bi<0)bi=100000;return ai!=bi?ai.CompareTo(bi):StringComparer.Ordinal.Compare(S(a,"category")+S(a,"label"),S(b,"category")+S(b,"label"));});var result=new Godot.Collections.Array<Settings>();foreach(var entry in sorted)result.Add(entry);return result;
    }
    public bool valid_entry(Variant value)
    {
        if(value.VariantType!=Variant.Type.Dictionary)return false;var entry=value.AsGodotDictionary();switch(S(entry,"kind"))
        {
            case "generator":using(var synth=new AudioSynthesisOperations())return synth.preset(S(entry,"id")).Count>0;
            case "instrument":using(var instruments=new AudioInstrumentOperations()){foreach(var preset in instruments.presets())if(S(preset,"id")==S(entry,"id"))return true;return false;}
            case "asset":if(B(entry,"project_indexed")){using var index=new AudioAssetIndexOperations();return index.usable(entry);}var source=Get(entry,"source");return source.VariantType==Variant.Type.Object&&source.AsGodotObject() is AudioStream||source.VariantType==Variant.Type.String&&Array.IndexOf(new[]{"wav","mp3","ogg","flac"},source.AsString().GetExtension().ToLowerInvariant())>=0;
            case "template":using(var templates=new AudioTemplateOperations())return Array.IndexOf(templates.names(),S(entry,"label"))>=0;
            case "preset":var presetRaw=Get(entry,"preset");var presetObject=presetRaw.VariantType==Variant.Type.Object?presetRaw.AsGodotObject() as Resource:null;if(!PresetResource(presetObject))return false;string kind=presetObject.Get("kind").AsString();return Array.IndexOf(new[]{"generator","instrument","pattern","effects","composition","bundle"},kind)>=0&&(kind is not ("composition" or "bundle")||presetObject.Get("composition").AsGodotObject()!=null);
            default:return false;
        }
    }

    public Variant drag_data(ItemList list)
    {
        var indices=list.GetSelectedItems();if(indices.Length==0)return default;var entry=list.GetItemMetadata(indices[0]).AsGodotDictionary();using var index=new AudioAssetIndexOperations();if(B(entry,"project_indexed")&&!index.usable(entry))return default;list.SetDragPreview(new Label{Text=S(entry,"label","Audio")});if(S(entry,"kind")=="generator"){var library=list.GetParent();return library!=null&&library.HasMethod("_generator_drag_data")?library.Call("_generator_drag_data",entry):new Settings{["generator"]=entry.Duplicate(true)};}if(B(entry,"project_indexed"))return new Settings{["audio_library"]=entry.Duplicate(true)};if(entry.ContainsKey("source"))return new Settings{["audio_source"]=entry["source"],["label"]=Get(entry,"label","Audio")};return new Settings{["audio_library"]=entry};
    }
}
