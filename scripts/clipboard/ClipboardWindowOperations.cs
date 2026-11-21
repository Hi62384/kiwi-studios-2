using Godot;
using System;
using System.Linq;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

public partial class ClipboardWindowOperations : RefCounted
{
    private readonly ClipboardStoreOperations _store = new();
    private readonly ClipboardSnapshotOperations _snapshot = new();
    private readonly SuperClipboardOperations _service = new();
    private static RefCounted Store(Control owner) => owner.Get("store").As<RefCounted>();
    private static Node Service(Control owner) => owner.Get("service").As<Node>();
    private static T Field<T>(Control owner, string name) where T : GodotObject => (T)owner.Get(name).AsGodotObject();
    private static Settings Data(Control owner) => Store(owner).Get("data").AsGodotDictionary();
    private static Settings Map(Settings data, string key) => data[key].AsGodotDictionary();
    private static string Folder(Control owner) => owner.Get("folder").AsString();
    private static bool Trash(Control owner) => owner.Get("trash").AsBool();
    private static Variant Get(Settings data, string key, Variant fallback = default) => data.TryGetValue(key, out var value) ? value : fallback;
    private static void Clear(Node parent) { foreach (Node child in parent.GetChildren()) { parent.RemoveChild(child); child.QueueFree(); } }
    public string[] selected(Control owner) => Field<ItemList>(owner, "files").GetSelectedItems().Select(i => Field<ItemList>(owner, "files").GetItemMetadata(i).AsString()).ToArray();
    public string[] selection(Control owner) { var ids = selected(owner); return ids.Length > 0 ? ids : new[] { Folder(owner) }; }
    public void refresh(Control owner)
    {
        if (Folder(owner) != "" && !_store.folder_valid(Store(owner), Folder(owner))) owner.Set("folder", "default");
        var tree = Field<Tree>(owner, "tree"); tree.Clear(); var root = tree.CreateItem(); root.SetText(0, "Super Clipboard"); root.SetMetadata(0, ""); folders(owner, root, "", new Settings()); owner.Call("_refresh_files");
    }
    public void folders(Control owner, TreeItem parent, string id, Settings visited)
    {
        if (visited.ContainsKey(id)) return; visited[id] = true;
        foreach (var pair in Map(Data(owner), "folders"))
        {
            var item = pair.Value.AsGodotDictionary(); if (item["parent"].AsString() != id || Get(item, "deleted", false).AsBool()) continue;
            var row = Field<Tree>(owner, "tree").CreateItem(parent); row.SetText(0, item["name"].AsString()); row.SetIcon(0, GD.Load<Texture2D>("uid://h5xgw3ns54ys")); row.SetIconMaxWidth(0, 18); row.SetMetadata(0, pair.Key);
            if (pair.Key.AsString() == Folder(owner)) row.Select(0); folders(owner, row, pair.Key.AsString(), visited);
        }
    }
    public Settings begin_listing(Control owner)
    {
        long token = owner.Get("_listing").AsInt64() + 1; owner.Set("_listing", token);
        var files = Field<ItemList>(owner, "files"); files.Clear(); Field<Button>(owner, "default_button").Disabled = true;
        bool grid = owner.Get("grid").AsBool(); files.MaxColumns = grid ? 0 : 1; files.IconMode = grid ? ItemList.IconModeEnum.Top : ItemList.IconModeEnum.Left; files.FixedIconSize = grid ? new Vector2I(72, 56) : new Vector2I(20, 20); files.FixedColumnWidth = grid ? 120 : 0;
        return new Settings { ["token"] = token, ["entries"] = Map(Data(owner), "entries").Duplicate(true), ["ids"] = new GArray(Map(Data(owner), "entries").Keys), ["index"] = 0, ["count"] = 0, ["query"] = Field<LineEdit>(owner, "search").Text.Trim().ToLowerInvariant(), ["trash"] = Trash(owner), ["folder"] = Folder(owner), ["default"] = Data(owner)["default_slot"] };
    }
    public bool continue_listing(Control owner, Settings state)
    {
        if (state["token"].AsInt64() != owner.Get("_listing").AsInt64()) return false;
        var ids = state["ids"].AsGodotArray(); var entries = state["entries"].AsGodotDictionary(); int index = state["index"].AsInt32(), count = state["count"].AsInt32(); string query = state["query"].AsString(), folder = state["folder"].AsString(); bool trash = state["trash"].AsBool(); var files = Field<ItemList>(owner, "files"); int added = 0;
        while (index < ids.Count)
        {
            string id = ids[index++].AsString(); var entry = entries[id].AsGodotDictionary(); if (Get(entry, "deleted", false).AsBool() != trash) continue;
            if (query == "" && folder != "" && entry["folder"].AsString() != folder && !trash) continue;
            if (query != "" && !(entry["name"].AsString() + " " + entry["type"].AsString()).ToLowerInvariant().Contains(query)) continue;
            files.AddItem((state["default"].AsString() == id ? "★ " : "") + entry["name"].AsString(), _store.icon(Store(owner), id)); files.SetItemMetadata(files.ItemCount - 1, id); files.SetItemTooltip(files.ItemCount - 1, entry["type"].AsString() + " · " + entry["name"].AsString()); count++; added++;
            if (added == 200) { state["index"] = index; state["count"] = count; return true; }
        }
        Field<Label>(owner, "status").Text = (trash ? "Trash · " : "") + count + " items"; owner.CallDeferred("_queue_thumbnails"); return false;
    }
    public void queue_thumbnails(Control owner)
    {
        if (!owner.Get("grid").AsBool() || !owner.Visible) return;
        var jobs = owner.Get("_thumbnail_jobs").AsGodotArray(); jobs.Clear(); var files = Field<ItemList>(owner, "files"); var thumbnails = owner.Get("_thumbnails").AsGodotDictionary();
        for (int index = 0; index < files.ItemCount; index++)
        {
            var rectangle = files.GetItemRect(index); rectangle.Position -= new Vector2(0, (float)files.GetVScrollBar().Value); if (!rectangle.Intersects(new Rect2(Vector2.Zero, files.Size))) continue;
            string id = files.GetItemMetadata(index).AsString(); if (thumbnails.TryGetValue(id, out var texture)) files.SetItemIcon(index, texture.As<Texture2D>()); else jobs.Add(new Settings { ["id"] = id, ["index"] = index, ["generation"] = owner.Get("_listing") });
        }
    }
    public void process(Control owner)
    {
        var jobs = owner.Get("_thumbnail_jobs").AsGodotArray(); if (!owner.Visible || owner.Get("_thumbnail_busy").AsBool() || jobs.Count == 0) return;
        owner.Set("_thumbnail_busy", true); var job = jobs[0]; jobs.RemoveAt(0); owner.Call("_thumbnail", job);
    }
    public string thumbnail_path(Control owner, Settings job)
    {
        string path = _store.entry_path(Store(owner), job["id"].AsString(), Trash(owner)); return path != "" && _snapshot.safe_resource(path, new Settings()) ? path : "";
    }
    public void finish_thumbnail(Control owner, Settings job, Texture2D? texture)
    {
        owner.Set("_thumbnail_busy", false); var files = Field<ItemList>(owner, "files"); if (texture == null || job["generation"].AsInt64() != owner.Get("_listing").AsInt64() || !GodotObject.IsInstanceValid(files)) return;
        if (Math.Max(texture.GetWidth(), texture.GetHeight()) > 128)
        {
            using var image = texture.GetImage(); if (image != null && !image.IsEmpty()) { float ratio = 128f / Math.Max(image.GetWidth(), image.GetHeight()); image.Resize(Math.Max(1, Mathf.RoundToInt(image.GetWidth() * ratio)), Math.Max(1, Mathf.RoundToInt(image.GetHeight() * ratio)), Image.Interpolation.Bilinear); texture = ImageTexture.CreateFromImage(image); }
        }
        var cache = owner.Get("_thumbnails").AsGodotDictionary(); cache[job["id"]] = texture; while (cache.Count > 128) cache.Remove(cache.Keys.First()); int index = job["index"].AsInt32(); if (index >= 0 && index < files.ItemCount && files.GetItemMetadata(index).AsString() == job["id"].AsString()) files.SetItemIcon(index, texture);
    }
    public Settings begin_preview(Control owner)
    {
        long token = owner.Get("_generation").AsInt64() + 1; owner.Set("_generation", token); var ids = selected(owner); Field<TextureRect>(owner, "preview").Texture = null; Field<Button>(owner, "default_button").Disabled = ids.Length != 1 || Trash(owner);
        if (ids.Length != 1) { Field<Label>(owner, "details").Text = ids.Length + " resources selected"; return new Settings(); }
        var entry = Map(Map(Data(owner), "entries"), ids[0]); Field<Label>(owner, "details").Text = entry["name"].AsString() + "\n" + entry["type"].AsString(); string path = _store.entry_path(Store(owner), ids[0], Trash(owner));
        return path != "" && _snapshot.safe_resource(path, new Settings()) ? new Settings { ["path"] = path, ["token"] = token } : new Settings();
    }
    public void finish_preview(Control owner, Settings plan, Texture2D? texture)
    {
        var preview = Field<TextureRect>(owner, "preview"); if (plan["token"].AsInt64() == owner.Get("_generation").AsInt64() && GodotObject.IsInstanceValid(preview)) preview.Texture = texture;
    }
}
