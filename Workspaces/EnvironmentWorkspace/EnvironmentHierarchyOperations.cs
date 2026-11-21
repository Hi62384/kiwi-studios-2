using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;

public partial class EnvironmentHierarchyOperations : RefCounted
{
    private readonly ModelDocumentOperations _models=new();
    private static RefCounted Session(Control owner)=>owner.Get("session").As<RefCounted>();
    private static Settings Collapsed(Control owner)=>owner.Get("_collapsed").AsGodotDictionary();
    public void store_collapsed(Control owner,TreeItem? root)
    {
        if(root==null)return;var pending=new Stack<TreeItem>();pending.Push(root);
        while(pending.Count>0){var row=pending.Pop();var id=row.GetMetadata(0);if(id.VariantType==Variant.Type.String)Collapsed(owner)[id]=row.Collapsed;for(var child=row.GetFirstChild();child!=null;child=child.GetNext())pending.Push(child);}
    }
    public void refresh(Control owner)
    {
        var hierarchy=owner.Get("hierarchy").As<Tree>();store_collapsed(owner,hierarchy.GetRoot());owner.Set("_building",true);
        try
        {
            var session=Session(owner);var document=session.Get("document").As<Resource>();hierarchy.Set("session",session);hierarchy.Clear();var root=hierarchy.CreateItem();var rows=new Dictionary<string,TreeItem>(StringComparer.Ordinal);var pending=new List<Resource>();var shown=new HashSet<string>(StringComparer.Ordinal);string filter=owner.Get("search").As<LineEdit>().Text.ToLowerInvariant();
            foreach(var value in document.Get("components").AsGodotArray())
            {
                var item=value.As<Resource>();pending.Add(item);if(filter.Length>0&&!item.Get("title").AsString().ToLowerInvariant().Contains(filter,StringComparison.Ordinal))continue;
                shown.Add(item.Get("id").AsString());var parent=_models.component(document,item.Get("parent_id").AsString());var visited=new HashSet<string>(StringComparer.Ordinal);
                while(parent!=null&&visited.Add(parent.Get("id").AsString())){shown.Add(parent.Get("id").AsString());parent=_models.component(document,parent.Get("parent_id").AsString());}
            }
            var selected=session.Get("selected").AsGodotArray();var selectedIds=new HashSet<string>(StringComparer.Ordinal);foreach(var id in selected)selectedIds.Add(id.AsString());var collapsed=Collapsed(owner);
            int passes=pending.Count+1;for(int pass=0;pass<passes&&pending.Count>0;pass++)
            {
                bool removed=false;for(int index=pending.Count-1;index>=0;index--)
                {
                    var item=pending[index];string id=item.Get("id").AsString(),parentId=item.Get("parent_id").AsString();if(!shown.Contains(id)){pending.RemoveAt(index);removed=true;continue;}
                    if(parentId.Length>0&&!rows.ContainsKey(parentId))continue;var row=hierarchy.CreateItem(rows.TryGetValue(parentId,out var parent)?parent:root);row.SetText(0,item.Get("title").AsString());row.SetMetadata(0,id);row.SetEditable(0,true);row.Collapsed=filter.Length==0&&collapsed.TryGetValue(id,out var isCollapsed)&&isCollapsed.AsBool();
                    for(int column=1;column<=2;column++){row.SetCellMode(column,TreeItem.TreeCellMode.Check);row.SetEditable(column,true);}row.SetChecked(1,item.Get("visible").AsBool());row.SetChecked(2,item.Get("locked").AsBool());rows[id]=row;if(selectedIds.Contains(id))row.Select(0);pending.RemoveAt(index);removed=true;
                }
                if(!removed)break;
            }
        }
        finally{owner.Set("_building",false);}
    }
    public void selected(Control owner,TreeItem row,int column,bool enabled)
    {
        if(owner.Get("_building").AsBool()||column!=0)return;var session=Session(owner);var selection=session.Get("selected").AsGodotArray();string id=row.GetMetadata(0).AsString();int found=-1;for(int i=0;i<selection.Count;i++)if(selection[i].AsString()==id){found=i;break;}if(enabled&&found<0)selection.Add(id);else if(!enabled&&found>=0)selection.RemoveAt(found);session.EmitSignal("changed");
    }
    public void edited(Control owner)
    {
        if(owner.Get("_building").AsBool())return;var tree=owner.Get("hierarchy").As<Tree>();var row=tree.GetEdited();if(row==null)return;var session=Session(owner);var item=_models.component(session.Get("document").As<Resource>(),row.GetMetadata(0).AsString());if(item==null)return;int column=tree.GetEditedColumn();session.Call("begin");if(column==0)item.Set("title",row.GetText(0));else item.Set(column==1?"visible":"locked",row.IsChecked(column));session.Call("commit","Change environment component");
    }
}
