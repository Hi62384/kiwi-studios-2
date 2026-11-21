using Godot;
using System.Collections.Generic;

public partial class CompositeLayerTree : RefCounted
{
    public void refresh(Tree tree, Resource document, string selected)
    {
        tree.Clear(); var root = tree.CreateItem(); root.SetText(0, document.Get("title").AsString());
        var items = new Dictionary<string, TreeItem>(); var pending = new List<Resource>();
        foreach (Variant value in document.Get("layers").AsGodotArray()) { var layer = value.As<Resource>(); if (layer != null) pending.Add(layer); }
        while (pending.Count > 0)
        {
            bool progressed = false;
            for (int i = pending.Count - 1; i >= 0; i--)
            {
                var layer = pending[i]; string parentId = layer.Get("parent_id").AsString(), id = layer.Get("id").AsString();
                TreeItem parent = root;
                if (parentId.Length > 0 && !items.TryGetValue(parentId, out parent!)) continue;
                var item = tree.CreateItem(parent); string name = layer.Get("name").AsString();
                item.SetText(0, (layer.Get("locked").AsBool() ? "🔒 " : layer.Get("visible").AsBool() ? "◉ " : "○ ") + name);
                item.SetMetadata(0, id); item.SetSelectable(0, true); items[id] = item;
                if (id == selected) item.Select(0);
                pending.RemoveAt(i); progressed = true;
            }
            if (!progressed) break;
        }
    }

    public Godot.Collections.Array<string> selected_layers(Tree tree, Resource document, string fallback)
    {
        var result = new Godot.Collections.Array<string>(); using var rules = new CompositingDocument(); TreeItem? item = null;
        while ((item = tree.GetNextSelected(item)) != null)
        {
            string id = item.GetMetadata(0).AsString(); if (id.Length > 0 && rules.layer_resource(document, id) != null) result.Add(id);
        }
        if (result.Count == 0 && rules.layer_resource(document, fallback) != null) result.Add(fallback);
        return result;
    }
}
