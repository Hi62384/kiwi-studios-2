using Godot;
using GArray=Godot.Collections.Array;
public partial class ActorResourceSlotOperations:RefCounted
{
    public string normalize_path(string path)=>(path.StartsWith("res://",System.StringComparison.Ordinal)?ProjectSettings.GlobalizePath(path):path).SimplifyPath();
    private string CollectionPath(Variant value){if(value.VariantType==Variant.Type.PackedStringArray){var paths=value.AsStringArray();return paths.Length==1?normalize_path(paths[0]):"";}if(value.VariantType==Variant.Type.Array){var paths=value.AsGodotArray();return paths.Count==1?normalize_path(paths[0].ToString()):"";}return "";}
    public string path_from_drag(Variant data){if(data.VariantType==Variant.Type.String)return normalize_path(data.AsString());if(data.VariantType is Variant.Type.PackedStringArray or Variant.Type.Array)return CollectionPath(data);if(data.VariantType==Variant.Type.Dictionary){var values=data.AsGodotDictionary();foreach(string key in new[]{"paths","files"})if(values.TryGetValue(new StringName(key),out var paths)&&paths.VariantType is Variant.Type.PackedStringArray or Variant.Type.Array)return CollectionPath(paths);foreach(string key in new[]{"path","file"})if(values.TryGetValue(new StringName(key),out var path)&&path.ToString().Length>0)return normalize_path(path.ToString());}return "";}
    public bool can_drop(Button owner,Variant data){string path=path_from_drag(data);bool accepted=path.Length>0&&owner.Call("_accept_path",path).AsBool();owner.SelfModulate=accepted?new Color("b8fff0"):Colors.White;return accepted;}
    public void drop(Button owner,Variant data){owner.SelfModulate=Colors.White;string path=path_from_drag(data);if(path.Length>0&&owner.Call("_accept_path",path).AsBool())owner.EmitSignal("file_dropped",path);}
    public void drag_notification(Button owner,int what){if(what==Control.NotificationDragEnd)owner.SelfModulate=Colors.White;}
}
