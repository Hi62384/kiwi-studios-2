using Godot;
using System;
using System.Text;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class EnvironmentLibraryOperations : RefCounted
{
    private static T Field<[MustBeVariant] T>(Control owner,string key) where T:GodotObject=>owner.Get(key).As<T>();
    private static void EndDirectory(Control owner)
    {var directory=Field<DirAccess>(owner,"_directory");if(directory!=null){directory.ListDirEnd();owner.Set("_directory",default(Variant));directory.Dispose();}}
    public Variant drag_data(ItemList list,Vector2 point)
    {int index=list.GetItemAtPosition(point,true);if(index<0)return default;string path=list.GetItemMetadata(index).AsString();list.SetDragPreview(new Label {Text=path.GetFile()});return new Settings {["files"]=new GArray {path}};}
    public void ready(VBoxContainer owner)
    {
        var search=Field<LineEdit>(owner,"search");var category=Field<OptionButton>(owner,"category");var list=Field<ItemList>(owner,"list");var preview=Field<TextureRect>(owner,"preview");var info=Field<Label>(owner,"info");search.PlaceholderText="Find project assets…";owner.AddChild(search);search.TextChanged+=_=>refresh(owner);foreach(string text in new[]{"All assets","Models","Terrain Materials","Natural Objects","Structures","Miscellaneous Props"})category.AddItem(text);owner.AddChild(category);category.ItemSelected+=_=>refresh(owner);list.SizeFlagsVertical=Control.SizeFlags.ExpandFill;list.TextOverrunBehavior=TextServer.OverrunBehavior.TrimEllipsis;list.CustomMinimumSize=new Vector2(0,90);owner.AddChild(list);list.ItemSelected+=index=>owner.Call("_select",index);list.ItemActivated+=index=>owner.EmitSignal("asset_chosen",list.GetItemMetadata((int)index).AsString());preview.CustomMinimumSize=new Vector2(0,70);preview.ExpandMode=TextureRect.ExpandModeEnum.IgnoreSize;preview.StretchMode=TextureRect.StretchModeEnum.KeepAspectCentered;preview.MouseFilter=Control.MouseFilterEnum.Ignore;owner.AddChild(preview);info.TextOverrunBehavior=TextServer.OverrunBehavior.TrimEllipsis;owner.AddChild(info);var buttons=new HBoxContainer();owner.AddChild(buttons);foreach(string text in new[]{"Use","Open source","↻"}){string action=text;var button=new Button {Text=text};buttons.AddChild(button);button.Pressed+=()=>{if(action=="↻"){scan(owner);return;}string selected=owner.Get("_selected").AsString();if(selected.Length>0)owner.EmitSignal(action=="Use"?"asset_chosen":"source_requested",selected);};}scan(owner);
    }
    public void scan(Control owner)
    {string root=GD.Load<GDScript>("res://scripts/actors/core/actor_project_file_picker.gd").Call("root_directory").AsString();owner.Set("_root",root);EndDirectory(owner);var directories=owner.Get("_directories").AsGodotArray();directories.Clear();directories.Add(root);owner.Get("_files").AsGodotArray().Clear();owner.Set("_selected", "");Field<TextureRect>(owner,"preview").Texture=null;refresh(owner);}
    public void process(Control owner)
    {
        if(!owner.IsVisibleInTree())return;ulong started=Time.GetTicksUsec();bool changed=false;var directories=owner.Get("_directories").AsGodotArray();var files=owner.Get("_files").AsGodotArray();while(Time.GetTicksUsec()-started<2000)
        {
            var directory=Field<DirAccess>(owner,"_directory");if(directory==null){if(directories.Count==0)break;string path=directories[^1].AsString();directories.RemoveAt(directories.Count-1);directory=DirAccess.Open(path);if(directory==null)continue;owner.Set("_directory",directory);directory.ListDirBegin();}string name=directory.GetNext();if(name.Length==0){EndDirectory(owner);continue;}if(name.StartsWith(".",StringComparison.Ordinal))continue;string candidate=directory.GetCurrentDir().PathJoin(name);if(directory.CurrentIsDir()){if(!directory.IsLink(name))directories.Add(candidate);}else if(compatible(candidate)){files.Add(candidate);changed=true;}if(files.Count>=20000){directories.Clear();EndDirectory(owner);break;}
        }
        if(changed)owner.Set("_refresh_due",true);if(owner.Get("_refresh_due").AsBool()&&directories.Count==0&&Field<DirAccess>(owner,"_directory")==null){owner.Set("_refresh_due",false);refresh(owner);}
    }
    public bool compatible(string path)
    {
        string extension=path.GetExtension().ToLowerInvariant();if(extension is "glb" or "gltf" or "obj" or "mesh" or "png" or "jpg" or "jpeg" or "webp" or "res")return true;if(extension!="tres")return false;using var file=Godot.FileAccess.Open(path,Godot.FileAccess.ModeFlags.Read);if(file==null)return false;string header=Encoding.UTF8.GetString(file.GetBuffer((long)Math.Min(file.GetLength(),4096UL)));return header.Contains("environment_document.gd",StringComparison.Ordinal)||header.Contains("model_document.gd",StringComparison.Ordinal)||header.Contains("type=\"StandardMaterial3D\"",StringComparison.Ordinal)||header.Contains("type=\"ShaderMaterial\"",StringComparison.Ordinal)||header.Contains("actor_object_data.gd",StringComparison.Ordinal)||header.Contains("ActorObjectData.cs",StringComparison.Ordinal);
    }
    public void refresh(Control owner)
    {
        var list=Field<ItemList>(owner,"list");var category=Field<OptionButton>(owner,"category");list.Clear();string filter=Field<LineEdit>(owner,"search").Text.ToLowerInvariant(),selection=category.GetItemText(category.Selected);foreach(var value in owner.Get("_files").AsGodotArray()){string path=value.AsString(),lower=path.ToLowerInvariant(),extension=path.GetExtension().ToLowerInvariant();bool material=extension is "png" or "jpg" or "jpeg" or "webp"||lower.Contains("material",StringComparison.Ordinal);if(filter.Length>0&&!lower.Contains(filter,StringComparison.Ordinal))continue;if(selection=="Terrain Materials"&&!material)continue;if(selection=="Models"&&material)continue;if(selection=="Natural Objects"&&!(lower.Contains("tree",StringComparison.Ordinal)||lower.Contains("plant",StringComparison.Ordinal)||lower.Contains("rock",StringComparison.Ordinal)||lower.Contains("natural",StringComparison.Ordinal)))continue;if(selection=="Structures"&&!(lower.Contains("structure",StringComparison.Ordinal)||lower.Contains("building",StringComparison.Ordinal)||lower.Contains("wall",StringComparison.Ordinal)||lower.Contains("architecture",StringComparison.Ordinal)))continue;if(selection=="Miscellaneous Props"&&(material||lower.Contains("tree",StringComparison.Ordinal)||lower.Contains("structure",StringComparison.Ordinal)))continue;int index=list.AddItem(path.GetFile());list.SetItemMetadata(index,path);list.SetItemTooltip(index,path);}Field<Label>(owner,"info").Text=list.ItemCount+" project assets";
    }
    public string select(Control owner,int index)
    {string path=Field<ItemList>(owner,"list").GetItemMetadata(index).AsString();owner.Set("_selected",path);var info=Field<Label>(owner,"info");info.Text=path.GetFile();info.TooltipText=path;return path;}
    public void set_preview(Control owner,string path,Texture2D? texture)
    {if(owner.IsInsideTree()&&path==owner.Get("_selected").AsString())Field<TextureRect>(owner,"preview").Texture=texture;}
    public void release(Control owner)=>EndDirectory(owner);
}
