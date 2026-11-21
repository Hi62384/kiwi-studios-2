using Godot;
using System.Linq;
using Settings=Godot.Collections.Dictionary;

public partial class ModelHierarchy : Tree
{
    public RefCounted? session {get;set;}
    public override void _ExitTree() => session=null;
    public override Variant _GetDragData(Vector2 position)
    {
        var row=GetItemAtPosition(position);if(row==null||session==null||GetColumnAtPosition(position)!=0)return default;
        string id=row.GetMetadata(0).AsString();var selected=session.Get("selected").AsGodotArray<string>();var ids=selected.Contains(id)?new Godot.Collections.Array<string>(selected):new Godot.Collections.Array<string>{id};
        SetDragPreview(new Label{Text="↳ "+ids.Count+" component(s)"});return new Settings{["kiwi_model_tree"]=GetInstanceId(),["ids"]=ids};
    }
    public override bool _CanDropData(Vector2 position,Variant data)
    {
        DropModeFlags=(int)DropModeFlagsEnum.OnItem;if(data.VariantType!=Variant.Type.Dictionary||session==null)return false;var payload=data.AsGodotDictionary();
        if(!payload.TryGetValue("kiwi_model_tree",out var origin)||origin.AsUInt64()!=GetInstanceId()||!payload.ContainsKey("ids"))return false;
        var row=GetItemAtPosition(position);string parent=row==null?"":row.GetMetadata(0).AsString();return session.Call("can_reparent",payload["ids"],parent).AsBool();
    }
    public override void _DropData(Vector2 position,Variant data)
    {
        if(!_CanDropData(position,data)||session==null)return;var row=GetItemAtPosition(position);session.Call("reparent_components",data.AsGodotDictionary()["ids"],row==null?"":row.GetMetadata(0).AsString());
    }
}
