using Godot;
using System;
using System.Linq;
using System.Text;
using System.Security.Cryptography;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class ShaderBrowserOperations : RefCounted
{
    internal const string Cache="user://shader_library_previews/";
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private static T Node<[MustBeVariant] T>(Control owner,string key) where T:GodotObject=>owner.Get(key).As<T>();
    private static Settings Data(Control owner,string key)=>owner.Get(key).AsGodotDictionary();
    private static string[] Strings(Variant value)=>value.VariantType==Variant.Type.PackedStringArray?value.AsStringArray():value.VariantType==Variant.Type.Array?value.AsGodotArray().Select(item=>item.AsString()).ToArray():Array.Empty<string>();
    private static bool Fresh(Control owner,Node? node=null)=>GodotObject.IsInstanceValid(owner)&&owner.IsInsideTree()&&!owner.IsQueuedForDeletion()&&(node==null||GodotObject.IsInstanceValid(node)&&node.IsInsideTree()&&!node.IsQueuedForDeletion());
    private static void Status(Control owner,string text)=>Node<Label>(owner,"status").Text=text;
    private static ShaderSamplePreview Live(Control owner)=>Node<ShaderSamplePreview>(owner,"live");
    public bool matches(Settings entry,string query,string kind,string category,bool templates,int collection,string[] favorites,string[] recent)
    {
        string id=entry["id"].AsString();if(Get(entry,"template",false).AsBool()!=templates||kind.Length>0&&Get(entry,"shader_type","").AsString()!=kind||category.Length>0&&Get(entry,"category","").AsString()!=category||collection==1&&!favorites.Contains(id)||collection==2&&!recent.Contains(id))return false;
        string haystack=(Get(entry,"name","").AsString()+" "+Get(entry,"description","").AsString()+" "+Get(entry,"category","").AsString()+" "+string.Join(" ",Strings(Get(entry,"tags",new GArray())))).ToLowerInvariant();return query.ToLowerInvariant().Split(' ',StringSplitOptions.RemoveEmptyEntries).All(word=>haystack.Contains(word,StringComparison.Ordinal));
    }
    public string cache_key(Settings entry)
    {string text="6"+entry["id"].AsString()+new ShaderSampleCatalogOperations().get_code(entry)+Get(entry,"preview_mesh","").AsString()+RenderingServer.GetCurrentRenderingMethod();return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(text))).ToLowerInvariant();}
    public Error write_shader_copy(string path,string code)
    {
        if(path.GetExtension().ToLowerInvariant()!="gdshader")return Error.InvalidParameter;if(ProjectSettings.LocalizePath(path).StartsWith("res://Workspaces/ShaderWorkspace/library/",StringComparison.Ordinal))return Error.Unauthorized;using var file=FileAccess.Open(path,FileAccess.ModeFlags.Write);if(file==null)return FileAccess.GetOpenError();file.StoreString(code);file.Flush();return file.GetError();
    }
    public void load_preferences(Control owner)
    {using var config=new ConfigFile();if(config.Load(owner.Get("preferences_path").AsString())!=Error.Ok)return;owner.Set("favorites",Strings(config.GetValue("library","favorites",new GArray())));owner.Set("recent",Strings(config.GetValue("library","recent",new GArray())));}
    public void save_preferences(Control owner)
    {using var config=new ConfigFile();string path=owner.Get("preferences_path").AsString();config.Load(path);config.SetValue("library","favorites",owner.Get("favorites"));config.SetValue("library","recent",owner.Get("recent"));config.Save(path);}
    public void mark_used(Control owner)
    {load_preferences(owner);var selected=Data(owner,"selected");if(selected.Count==0)return;string id=selected["id"].AsString();var recent=Strings(owner.Get("recent")).Where(value=>value!=id).ToList();recent.Insert(0,id);if(recent.Count>32)recent.RemoveRange(32,recent.Count-32);owner.Set("recent",recent.ToArray());save_preferences(owner);}
    public void toggle_favorite(Control owner)
    {var selected=Data(owner,"selected");if(selected.Count==0)return;load_preferences(owner);string id=selected["id"].AsString();var favorites=Strings(owner.Get("favorites")).ToList();if(!favorites.Remove(id))favorites.Add(id);owner.Set("favorites",favorites.ToArray());Node<Button>(owner,"favorite").SetPressedNoSignal(favorites.Contains(id));save_preferences(owner);if(Node<OptionButton>(owner,"collection_filter").Selected==1)refresh(owner);}
    public void copy(Control owner)
    {var selected=Data(owner,"selected");if(selected.Count==0)return;DisplayServer.ClipboardSet(selected["source"].AsString());mark_used(owner);Status(owner,"Complete shader copied.");}
    public void open(Control owner)
    {var selected=Data(owner,"selected");if(selected.Count==0)return;mark_used(owner);owner.EmitSignal("open_requested",selected.Duplicate(true));}
    public void refresh_apply(Control owner)
    {
        var selected=Data(owner,"selected");var button=Node<Button>(owner,"apply");if(selected.Count==0){button.Disabled=true;return;}var target=new ShaderSampleApplicationOperations().target_for(owner.GetTree(),selected["shader_type"].AsString());button.Disabled=!target.ContainsKey("actor")||Live(owner).error_text.Length>0;button.TooltipText=target.ContainsKey("actor")?"Apply a new material copy to "+target["label"].AsString():Get(target,"reason","").AsString();
    }
    public void commit_apply(Control owner,Settings target,Settings entry)
    {string error=new ShaderSampleApplicationOperations().apply_to_target(target,entry["source"].AsString(),entry["name"].AsString());Status(owner,error.Length>0?error:"Applied to "+target["label"].AsString()+". Undo is available in the scene.");if(error.Length==0)mark_used(owner);}
    public void apply(Control owner)
    {
        var entry=Data(owner,"selected").Duplicate(true);if(entry.Count==0)return;var target=new ShaderSampleApplicationOperations().target_for(owner.GetTree(),entry["shader_type"].AsString());if(!target.ContainsKey("actor")){Status(owner,Get(target,"reason","No target selected.").AsString());return;}
        if(Get(target,"existing",false).AsBool()){var confirmation=new ConfirmationDialog {Title="Replace selected material?",DialogText="Apply "+entry["name"].AsString()+" to "+target["label"].AsString()+"?\nThe current slot will be replaced with a separate copy. Undo restores the previous material."};confirmation.Confirmed+=()=>{if(Fresh(owner))commit_apply(owner,target,entry);confirmation.QueueFree();};confirmation.Canceled+=confirmation.QueueFree;owner.AddChild(confirmation);confirmation.PopupCentered();}else commit_apply(owner,target,entry);
    }
    public void visibility_changed(Control owner)
    {var live=owner.Get("live").As<ShaderSamplePreview>();if(live!=null)live.set_active(owner.IsVisibleInTree()&&Data(owner,"selected").Count>0&&live.error_text.Length==0);var thumbnail=owner.Get("thumbnail").As<ShaderSamplePreview>();if(thumbnail!=null&&!owner.IsVisibleInTree())thumbnail.set_active(false);}
    public void preview_input(Control owner,InputEvent input)
    {var live=Live(owner);if(input is InputEventMouseMotion motion&&(motion.ButtonMask&MouseButtonMask.Left)!=0)live.orbit(motion.Relative);else if(input is InputEventMouseButton mouse&&mouse.Pressed){if(mouse.ButtonIndex==MouseButton.WheelUp)live.zoom(.9);else if(mouse.ButtonIndex==MouseButton.WheelDown)live.zoom(1.1);}}
}
