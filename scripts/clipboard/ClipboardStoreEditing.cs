using Godot;
using System;
using System.Linq;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

public partial class ClipboardStoreOperations
{
    private static RefCounted Snapshot(RefCounted owner)
    {
        var snapshot = GD.Load<GDScript>("res://scripts/clipboard/clipboard_snapshot.gd").New().As<RefCounted>(); snapshot.Set("root", Root(owner)); return snapshot;
    }
    public string save(RefCounted owner, Variant value, string name, string folder)
    {
        if (owner.Get("read_only").AsBool()) return ""; owner.Set("error", "");
        if (!folder_valid(owner, folder)) { Fail(owner, "Choose an existing clipboard folder."); return ""; }
        string id = _data.new_id(), directory = Root(owner).PathJoin("objects").PathJoin(id); DirAccess.MakeDirRecursiveAbsolute(directory);
        string extension = value.VariantType == Variant.Type.String ? value.AsString().GetExtension().ToLowerInvariant() : "tres";
        var bridge = GD.Load<GDScript>("res://scripts/clipboard/clipboard_snapshot.gd");
        Resource? resource = value.VariantType == Variant.Type.Object ? value.AsGodotObject() as Resource : null;
        if (!bridge.GetScriptConstantMap()["RAW"].AsGodotArray().Contains(extension) && !bridge.Get("adapters").AsGodotDictionary().ContainsKey(extension)) extension = resource is Shader || extension == "gdshader" ? "gdshader" : "tres";
        string path = directory.PathJoin("resource." + extension); var snapshot = Snapshot(owner);
        if (!snapshot.Call("capture", value, path).AsBool()) { owner.Set("error", snapshot.Get("error")); return ""; }
        bool objectData = ActorDataOperations.ScriptIs(resource, "res://scripts/actors/core/actor_object_data.gd");
        string nativeType = objectData ? resource!.Get("type_id").AsString() : resource?.GetClass() ?? extension;
        if (resource != null && !objectData && resource.GetScript().As<Script>() is Script script && !script.GetGlobalName().IsEmpty) nativeType = script.GetGlobalName().ToString();
        var next = Data(owner).Duplicate(true); var nativeTypes = new GArray(); foreach (string type in snapshot.Get("native_types").AsStringArray()) nativeTypes.Add(type);
        string objectType = snapshot.Get("object_type").AsString();
        Map(next, "entries")[id] = new Settings { ["name"] = unique_name(owner, name, folder, ""), ["folder"] = folder, ["id"] = id, ["path"] = path[(Root(owner).Length + 1)..], ["type"] = objectType != "" ? objectType : nativeType, ["native_types"] = nativeTypes, ["object_type"] = objectType, ["extension"] = extension, ["original"] = resource != null ? resource.ResourcePath : value.ToString(), ["dependencies"] = snapshot.Get("dependencies"), ["created"] = Time.GetUnixTimeFromSystem(), ["deleted"] = false }; next["default_slot"] = id;
        return commit(owner, "Save to Super Clipboard", next) ? id : "";
    }
    public string entry_path(RefCounted owner, string id, bool includeDeleted)
    {
        if (!Identifier.IsMatch(id)) return "";
        var entries = Map(Data(owner), "entries"); if (Get(entries, id).VariantType != Variant.Type.Dictionary) return "";
        var entry = Map(entries, id); if (entry.Count == 0 || (Deleted(entry) && !includeDeleted)) return "";
        string path = Root(owner).PathJoin(Text(entry, "path")).SimplifyPath();
        return _files.is_path_inside(Root(owner).PathJoin("objects"), path) && FileAccess.FileExists(path) ? path : "";
    }
    private static string Filename(string name)
    {
        using var expression = new Expression(); expression.Parse("name.validate_filename()", new[] { "name" }); return expression.Execute(new GArray { name }).AsString();
    }
    public string materialize(RefCounted owner, string id, string projectRoot)
    {
        owner.Set("error", ""); string source = entry_path(owner, id, false);
        if (source == "") { Fail(owner, "Stored resource data is missing."); return ""; }
        if (projectRoot == "" || !DirAccess.DirExistsAbsolute(projectRoot)) { Fail(owner, "Open a project before using a clipboard resource."); return ""; }
        string folder = projectRoot.PathJoin("Super Clipboard").PathJoin(id);
        if (!_files.is_path_inside(projectRoot, folder)) { Fail(owner, "Invalid clipboard identifier."); return ""; }
        var entry = Map(Map(Data(owner), "entries"), id);
        string path = folder.PathJoin(Filename(Text(entry, "name")) + "." + Text(entry, "extension")), marker = folder.PathJoin("import.json");
        if (FileAccess.FileExists(marker))
        {
            var imported = Json.ParseString(FileAccess.GetFileAsString(marker));
            if (imported.VariantType == Variant.Type.Dictionary)
            {
                string previous = folder.PathJoin(Text(imported.AsGodotDictionary(), "file")).SimplifyPath();
                if (_files.is_path_inside(folder, previous) && FileAccess.FileExists(previous)) return previous;
            }
        }
        DirAccess.MakeDirRecursiveAbsolute(folder); path = _files.get_unique_name(path);
        var snapshot = Snapshot(owner); snapshot.Set("destination_root", folder);
        if (!snapshot.Call("capture", source, path).AsBool()) { owner.Set("error", snapshot.Get("error")); return ""; }
        using var file = FileAccess.Open(marker, FileAccess.ModeFlags.Write);
        if (file == null) { Fail(owner, "Cannot record the project import."); return ""; }
        file.StoreString(Json.Stringify(new Settings { ["id"] = id, ["file"] = path.GetFile() })); file.Close();
        var files = GD.Load<GDScript>("res://scripts/Globals/local_project_filesystem.gd"); if (files.Get("node").VariantType == Variant.Type.Object && GodotObject.IsInstanceValid(files.Get("node").AsGodotObject())) files.Call("update_root_folder"); return path;
    }
    public string create_folder(RefCounted owner, string name, string parent)
    {
        if (parent != "" && !folder_valid(owner, parent)) { Fail(owner, "Invalid parent folder."); return ""; }
        string id = _data.new_id(); var next = Data(owner).Duplicate(true); Map(next, "folders")[id] = new Settings { ["name"] = unique_name(owner, name, parent, ""), ["parent"] = parent, ["deleted"] = false };
        return commit(owner, "Create clipboard folder", next) ? id : "";
    }
    public bool rename(RefCounted owner, string id, string name)
    {
        if (id == "default") return Fail(owner, "Default is the built-in quick-save folder.");
        string collection = Map(Data(owner), "entries").ContainsKey(id) ? "entries" : "folders";
        if (!Map(Data(owner), collection).ContainsKey(id)) return false;
        var next = Data(owner).Duplicate(true); var entry = Map(Map(next, collection), id); entry["name"] = unique_name(owner, name, Text(entry, "folder", Text(entry, "parent")), id);
        return commit(owner, "Rename clipboard item", next);
    }
    public bool move(RefCounted owner, string[] ids, string folder, bool duplicate)
    {
        if (!folder_valid(owner, folder)) return Fail(owner, "Invalid destination folder.");
        var next = Data(owner).Duplicate(true);
        foreach (string id in ids)
        {
            if (id == "default") continue;
            string collection = Map(Data(owner), "entries").ContainsKey(id) ? "entries" : "folders"; if (!Map(next, collection).ContainsKey(id)) continue;
            if (collection == "folders")
            {
                string ancestor = folder; var visited = new System.Collections.Generic.HashSet<string>();
                while (ancestor != "" && visited.Add(ancestor)) { if (ancestor == id) return Fail(owner, "A folder cannot be moved inside itself."); ancestor = Get(Map(next, "folders"), ancestor).VariantType == Variant.Type.Dictionary ? Text(Map(Map(next, "folders"), ancestor), "parent") : ""; }
            }
            var item = Map(Map(next, collection), id);
            if (duplicate)
            {
                if (collection == "folders") { duplicate_folder(owner, next, id, folder); continue; }
                string newId = _data.new_id(); item = item.Duplicate(true); item["id"] = newId; Map(next, "entries")[newId] = item;
            }
            item[collection == "entries" ? "folder" : "parent"] = folder;
            item["name"] = unique_in(owner, next, Text(item, "name"), folder, Text(item, "id", id));
        }
        return commit(owner, duplicate ? "Duplicate clipboard items" : "Move clipboard items", next);
    }
    public void duplicate_folder(RefCounted owner, Settings next, string id, string parent)
    {
        var data = Data(owner); string copy = _data.new_id(); var copied = Map(Map(data, "folders"), id).Duplicate(true); Map(next, "folders")[copy] = copied; copied["parent"] = parent; copied["name"] = unique_in(owner, next, Text(copied, "name"), parent, copy);
        foreach (var pair in Map(data, "entries"))
        {
            var original = pair.Value.AsGodotDictionary(); if (Text(original, "folder") != id || Deleted(original)) continue;
            string entry = _data.new_id(); var item = original.Duplicate(true); Map(next, "entries")[entry] = item; item["id"] = entry; item["folder"] = copy;
        }
        foreach (var pair in Map(data, "folders")) { var item = pair.Value.AsGodotDictionary(); if (Text(item, "parent") == id && !Deleted(item)) duplicate_folder(owner, next, pair.Key.AsString(), copy); }
    }
    public bool delete(RefCounted owner, string[] ids, bool restore)
    {
        var next = Data(owner).Duplicate(true);
        foreach (string id in ids)
        {
            if (id == "default") continue;
            string collection = Map(next, "entries").ContainsKey(id) ? "entries" : "folders"; if (!Map(next, collection).ContainsKey(id)) continue;
            var item = Map(Map(next, collection), id); item["deleted"] = !restore;
            if (restore) { string key = collection == "entries" ? "folder" : "parent", parent = Text(item, key); if (parent != "" && !folder_valid(owner, parent)) item[key] = "default"; }
            if (collection == "folders") delete_children(next, id, !restore, new Settings());
            if (Text(next, "default_slot") == id && !restore) next["default_slot"] = "";
        }
        string slot = Text(next, "default_slot"); if (Map(next, "entries").ContainsKey(slot) && Deleted(Map(Map(next, "entries"), slot))) next["default_slot"] = "";
        return commit(owner, restore ? "Restore clipboard items" : "Move clipboard items to Trash", next);
    }
    public void delete_children(Settings next, string id, bool deleted, Settings visited)
    {
        if (visited.ContainsKey(id)) return; visited[id] = true;
        foreach (var value in Map(next, "entries").Values) { var entry = value.AsGodotDictionary(); if (Text(entry, "folder") == id) entry["deleted"] = deleted; }
        foreach (var pair in Map(next, "folders")) { var item = pair.Value.AsGodotDictionary(); if (Text(item, "parent") == id) { item["deleted"] = deleted; delete_children(next, pair.Key.AsString(), deleted, visited); } }
    }
    public bool set_default(RefCounted owner, string id)
    {
        if (entry_path(owner, id, false) == "") return false; var next = Data(owner).Duplicate(true); next["default_slot"] = id; return commit(owner, "Set clipboard Default Slot", next);
    }
    public void save_ui(RefCounted owner, Settings state)
    {
        var next = Data(owner).Duplicate(true); next["ui"] = state.Duplicate(true); if (write(owner, next)) Data(owner)["ui"] = next["ui"];
    }
    public Texture2D icon(RefCounted owner, string id)
    {
        var entries = Map(Data(owner), "entries"); var entry = Get(entries, id, new Settings()).AsGodotDictionary(); string extension = Text(entry, "extension"), objectType = Text(entry, "object_type"); var types = Get(entry, "native_types", new GArray()).AsGodotArray();
        string name = "";
        if (extension == "gdshader" || types.Contains("Shader")) name = "Shader";
        else if (new[] { "wav", "mp3", "ogg", "flac", "m4a", "aac" }.Contains(extension) || types.Contains("AudioStream") || types.Contains("KiwiAudioDocument")) return GD.Load<Texture2D>("uid://dcqki3r6v5dxo");
        else if (extension == "glb" || new[] { "Mesh", "KiwiModelDocument", "KiwiRigPreset", "RigPreset" }.Any(type => types.Contains(type))) return GD.Load<Texture2D>("uid://bw47linn7yref");
        else if (new[] { "png", "jpg", "jpeg", "webp", "svg", "bmp", "exr", "hdr" }.Contains(extension) || types.Contains("Texture2D") || types.Contains("KiwiImageDocument") || objectType is "image" or "noise_image") name = "Image2D";
        else if (ActorVideo.extensions().Contains(extension)) name = "Video";
        else if (types.Contains("ActorSceneData")) name = "Camera3D";
        else if (types.Contains("KiwiTransformationImage2D")) name = "Transformation2D";
        else if (objectType == "text_settings") name = "TextSettings";
        else if (objectType is "material" or "shader_material" or "natural_material" || types.Contains("Material")) name = "Sphere";
        return GD.Load<Texture2D>(name == "" ? "uid://mwmlqweqemfk" : "res://resources/Images/ActorIcons/" + name + ".svg");
    }
}
