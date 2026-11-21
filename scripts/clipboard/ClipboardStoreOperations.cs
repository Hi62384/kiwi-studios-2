using Godot;
using System;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using Settings = Godot.Collections.Dictionary;

public partial class ClipboardStoreOperations : RefCounted
{
    private readonly FileOperationsNative _files = new();
    private readonly ActorDataOperations _data = new();
    private static Settings Data(RefCounted owner) => owner.Get("data").AsGodotDictionary();
    private static string Root(RefCounted owner) => owner.Get("root").AsString();
    private static Settings Map(Settings data, string key) => data[key].AsGodotDictionary();
    private static Variant Get(Settings data, string key, Variant fallback = default) => data.TryGetValue(key, out var value) ? value : fallback;
    private static string Text(Settings data, string key, string fallback = "") => Get(data, key, fallback).AsString();
    private static bool Deleted(Settings data) => Get(data, "deleted", false).AsBool();
    private static bool Fail(RefCounted owner, string message) { owner.Set("error", message); return false; }
    private static readonly Regex Identifier = new("^[0-9a-fA-F]{32}$", RegexOptions.CultureInvariant);
    public void initialize(RefCounted owner, string location)
    {
        string root = ProjectSettings.GlobalizePath(location).Replace('\\', '/').SimplifyPath(); owner.Set("root", root); DirAccess.MakeDirRecursiveAbsolute(root.PathJoin("objects"));
        var data = read(owner, root.PathJoin("index.json"));
        if (data.Count == 0 && !owner.Get("read_only").AsBool()) { data = read(owner, root.PathJoin("index.backup.json")); if (data.Count > 0) owner.Set("error", "Recovered Super Clipboard from its last valid index."); }
        if (data.Count == 0)
        {
            if (!owner.Get("read_only").AsBool() && FileAccess.FileExists(root.PathJoin("index.json"))) { DirAccess.CopyAbsolute(root.PathJoin("index.json"), root.PathJoin("index.corrupt-" + _data.new_id() + ".json")); owner.Set("error", "Clipboard metadata is damaged. Existing stored data and the damaged index were preserved."); }
            data = new Settings { ["version"] = 1, ["folders"] = new Settings { ["default"] = new Settings { ["name"] = "Default", ["parent"] = "", ["deleted"] = false } }, ["entries"] = new Settings(), ["default_slot"] = "", ["ui"] = new Settings() };
            if (!FileAccess.FileExists(root.PathJoin("index.json"))) write(owner, data);
        }
        owner.Set("data", data);
    }
    public Settings read(RefCounted owner, string path)
    {
        if (!FileAccess.FileExists(path)) return new Settings();
        using var parser = new Json();
        if (parser.Parse(FileAccess.GetFileAsString(path)) != Error.Ok) return new Settings();
        var envelopeValue = parser.Data;
        if (envelopeValue.VariantType != Variant.Type.Dictionary) return new Settings();
        var envelope = envelopeValue.AsGodotDictionary(); var payload = Get(envelope, "payload");
        if (payload.VariantType != Variant.Type.String || Text(envelope, "checksum") != payload.AsString().Sha256Text()) return new Settings();
        if (parser.Parse(payload.AsString()) != Error.Ok) return new Settings();
        var parsed = parser.Data; if (parsed.VariantType != Variant.Type.Dictionary) return new Settings();
        var data = parsed.AsGodotDictionary(); int version = Get(data, "version", 0).AsInt32();
        if (version > 1) { owner.Set("read_only", true); owner.Set("error", "This clipboard was created by a newer Kiwi version. It was left unchanged."); return new Settings(); }
        if (version != 1 || Get(data, "folders").VariantType != Variant.Type.Dictionary || Get(data, "entries").VariantType != Variant.Type.Dictionary || !valid_index(owner, data)) return new Settings();
        return data;
    }
    public bool valid_index(RefCounted owner, Settings data)
    {
        if (Get(data, "folders").VariantType != Variant.Type.Dictionary || Get(data, "entries").VariantType != Variant.Type.Dictionary) return false;
        var folders = Map(data, "folders");
        if (Get(folders, "default").VariantType != Variant.Type.Dictionary || Get(data, "default_slot").VariantType != Variant.Type.String || Get(data, "ui", new Settings()).VariantType != Variant.Type.Dictionary) return false;
        foreach (var pair in folders)
        {
            if (pair.Key.VariantType != Variant.Type.String) return false;
            string id = pair.Key.AsString(); if ((id != "default" && !Identifier.IsMatch(id)) || pair.Value.VariantType != Variant.Type.Dictionary) return false;
            var entry = pair.Value.AsGodotDictionary(); if (Get(entry, "name").VariantType != Variant.Type.String || Get(entry, "parent").VariantType != Variant.Type.String) return false;
            string parent = id; var seen = new System.Collections.Generic.HashSet<string>();
            while (parent != "")
            {
                if (seen.Contains(parent) || seen.Count > 64 || Get(folders, parent).VariantType != Variant.Type.Dictionary) return false;
                seen.Add(parent); parent = Text(Map(folders, parent), "parent");
            }
        }
        var entries = Map(data, "entries");
        foreach (var pair in entries)
        {
            if (pair.Key.VariantType != Variant.Type.String || !Identifier.IsMatch(pair.Key.AsString()) || pair.Value.VariantType != Variant.Type.Dictionary) return false;
            var entry = pair.Value.AsGodotDictionary();
            foreach (string key in new[] { "name", "folder", "path", "type", "extension" }) if (Get(entry, key).VariantType != Variant.Type.String) return false;
            if (!folders.ContainsKey(entry["folder"]) || Get(entry, "native_types", new Godot.Collections.Array()).VariantType != Variant.Type.Array) return false;
            string relative = Text(entry, "path"), path = Root(owner).PathJoin(relative).SimplifyPath();
            if (relative.IsAbsolutePath() || !_files.is_path_inside(Root(owner).PathJoin("objects"), path)) return false;
        }
        return Text(data, "default_slot") == "" || entries.ContainsKey(data["default_slot"]);
    }
    public bool write(RefCounted owner, Settings data)
    {
        if (owner.Get("read_only").AsBool()) return false;
        string payload = Json.Stringify(data), root = Root(owner), target = root.PathJoin("index.json"), temporary = root.PathJoin("index.pending.json"), backup = root.PathJoin("index.backup.json");
        using (var file = FileAccess.Open(temporary, FileAccess.ModeFlags.Write))
        {
            if (file == null) return Fail(owner, "Cannot write Super Clipboard metadata.");
            file.StoreString(Json.Stringify(new Settings { ["payload"] = payload, ["checksum"] = payload.Sha256Text() })); file.Flush(); file.Close();
        }
        if (read(owner, temporary).Count == 0) return Fail(owner, "Clipboard metadata validation failed. Nothing was replaced.");
        if (FileAccess.FileExists(target) && read(owner, target).Count > 0 && DirAccess.CopyAbsolute(target, backup) != Error.Ok) return Fail(owner, "Cannot back up Super Clipboard metadata.");
        if (owner.Get("read_only").AsBool()) return false;
        if (FileAccess.FileExists(target) && DirAccess.RemoveAbsolute(target) != Error.Ok) return Fail(owner, "Cannot replace clipboard metadata.");
        if (DirAccess.RenameAbsolute(temporary, target) != Error.Ok) return Fail(owner, "Metadata replacement failed; the backup remains available.");
        return true;
    }
    public void assign(RefCounted owner, Settings value)
    {
        value = value.Duplicate(true); value["ui"] = Get(Data(owner), "ui", new Settings()).AsGodotDictionary().Duplicate(true);
        if (write(owner, value)) { owner.Set("data", value.Duplicate(true)); owner.EmitSignal("changed"); }
    }
    public bool commit(RefCounted owner, string title, Settings next)
    {
        var before = Data(owner).Duplicate(true); if (!write(owner, next)) return false;
        var action = new ClipboardStoreRestoreAction(); action.initialize(owner, before, next.Duplicate(true));
        var history = owner.Get("history").As<UndoRedo>(); history.CreateAction(title); history.AddDoMethod(new Callable(action, "restore_after")); history.AddUndoMethod(new Callable(action, "restore_before")); history.AddDoReference(action); history.AddUndoReference(action); history.CommitAction(false);
        owner.Set("data", next.Duplicate(true)); owner.EmitSignal("changed"); return true;
    }
    public bool folder_valid(RefCounted owner, string id) => Get(Map(Data(owner), "folders"), id).VariantType == Variant.Type.Dictionary && !Deleted(Map(Map(Data(owner), "folders"), id));
    public bool name_exists(RefCounted owner, string name, string folder, string skip)
    {
        foreach (string kind in new[] { "entries", "folders" }) foreach (var pair in Map(Data(owner), kind))
        {
            var entry = pair.Value.AsGodotDictionary(); if (pair.Key.AsString() != skip && !Deleted(entry) && Text(entry, "folder", Text(entry, "parent")) == folder && string.Equals(Text(entry, "name"), name, StringComparison.OrdinalIgnoreCase)) return true;
        }
        return false;
    }
    public string unique_name(RefCounted owner, string name, string folder, string skip)
    {
        string basename = string.Concat(name.Trim().Replace('\n', ' ').EnumerateRunes().Take(120).Select(r => r.ToString())); if (basename == "") basename = "Untitled";
        string candidate = basename; int count = 2; while (name_exists(owner, candidate, folder, skip)) candidate = basename + " (" + count++ + ")"; return candidate;
    }
    public string unique_in(RefCounted owner, Settings next, string name, string folder, string skip)
    {
        var original = Data(owner); owner.Set("data", next); try { return unique_name(owner, name, folder, skip); } finally { owner.Set("data", original); }
    }
    public void close(RefCounted owner)
    {
        var history = owner.Get("history").As<UndoRedo>(); if (!GodotObject.IsInstanceValid(history)) return; history.ClearHistory(); history.Free(); owner.Set("history", default);
    }
}
