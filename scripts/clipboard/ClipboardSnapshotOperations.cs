using Godot;
using System;
using System.Linq;
using System.Text.RegularExpressions;
using Settings = Godot.Collections.Dictionary;

public partial class ClipboardSnapshotOperations : RefCounted
{
    private readonly ActorDataOperations _data = new();
    private static GDScript Bridge => GD.Load<GDScript>("res://scripts/clipboard/clipboard_snapshot.gd");
    private static Settings Map(RefCounted owner, string key) => owner.Get(key).AsGodotDictionary();
    private static Godot.Collections.Array Dependencies(RefCounted owner) => owner.Get("dependencies").AsGodotArray();
    private static string ErrorText(RefCounted owner) => owner.Get("error").AsString();
    private static bool Fail(RefCounted owner, string message) { owner.Set("error", message); return false; }
    private static bool Is(Resource? value, string file) => ActorDataOperations.ScriptIs(value, file);
    public bool safe_resource(string path, Settings visited)
    {
        if (visited.ContainsKey(path)) return true; visited[path] = true;
        foreach (string dependency in ResourceLoader.GetDependencies(path))
        {
            string target = dependency.Split("::", StringSplitOptions.None)[^1], extension = target.GetExtension().ToLowerInvariant();
            if (extension is "gd" or "cs" or "gde" or "gdextension") { if (!target.StartsWith("res://", StringComparison.Ordinal) || !FileAccess.FileExists(target)) return false; }
            else if (extension is "tres" or "res" or "tscn" or "scn") { if (!safe_resource(target, visited)) return false; }
        }
        return true;
    }
    public bool capture(RefCounted owner, Variant value, string path)
    {
        var resource = value.VariantType == Variant.Type.Object ? value.AsGodotObject() as Resource : null;
        string sourcePath = value.VariantType == Variant.Type.String ? value.AsString() : resource?.ResourcePath ?? "";
        if (Is(resource, "res://scripts/actors/core/actor_object_reference.gd"))
        {
            if (resource!.Get("source").AsInt32() == 1)
            {
                string asset = resource.Get("asset_id").AsString();
                if (!safe_resource(asset, new Settings())) return Fail(owner, "Unsafe resource dependency.");
                resource = FileAccess.FileExists(asset) ? ResourceLoader.Load(asset, "", ResourceLoader.CacheMode.Ignore) : null;
            }
            else resource = resource!.Get("embedded").As<Resource>();
            value = resource == null ? default : Variant.From(resource);
        }
        if (value.VariantType == Variant.Type.String)
        {
            string file = value.AsString(); if (!FileAccess.FileExists(file)) return Fail(owner, "Source file is missing: " + file);
            string extension = file.GetExtension().ToLowerInvariant();
            if (Bridge.Get("adapters").AsGodotDictionary().ContainsKey(extension)) return owner.Call("_run_capture_adapter", extension, file, path).AsBool();
            if (Bridge.GetScriptConstantMap()["RAW"].AsGodotArray().Contains(extension))
            {
                if (extension == "glb" && !self_contained_glb(file)) return Fail(owner, "This GLB references external files. Save it as an editable Kiwi model first.");
                string copied = copy_file(owner, file); return ErrorText(owner) == "" && copy_bytes(owner, copied, path);
            }
            if (!new[] { "tres", "res", "mesh", "material", "gdshader", "gdshaderinc" }.Contains(extension)) return Fail(owner, "Unsupported file. Save an editable Kiwi resource or a self-contained media file first.");
            if (!safe_resource(file, new Settings())) return Fail(owner, "This resource contains an external executable script and cannot be stored safely.");
            resource = ResourceLoader.Load(file, "", ResourceLoader.CacheMode.Ignore);
        }
        if (resource == null) return Fail(owner, "Only resource objects or supported media files can be stored.");
        var types = owner.Get("native_types").AsStringArray().ToList(); string type = resource.GetClass();
        while (type != "") { types.Add(type); type = ClassDB.GetParentClass(type).ToString(); }
        if (resource.GetScript().As<Script>() is Script script) types.Add(script.GetGlobalName().ToString()); owner.Set("native_types", types.ToArray());
        if (Is(resource, "res://scripts/actors/core/actor_object_data.gd")) owner.Set("object_type", resource.Get("type_id"));
        if (Is(resource, "res://Workspaces/AudioWorkspace/KiwiAudioDocument.cs") && resource.Get("portable_media").AsGodotDictionary().Count > 0)
        {
            var copy = (Resource)new AudioDocumentOperations().snapshot(resource);
            var resolved = new AudioPortableOperations().resolve(copy, sourcePath != "" ? sourcePath : copy.Get("_portable_root").AsString().PathJoin("composition.res"), true);
            if (resolved["error"].AsString() != "" || resolved["missing_assets"].AsStringArray().Length > 0) return Fail(owner, "Cannot collect the composition's portable media. " + resolved["error"].AsString());
            copy.Set("portable_media", new Settings()); copy.Set("scene_binding", new Settings()); resource = copy;
        }
        var clone = clone_value(owner, resource, "");
        if (ErrorText(owner) != "" || clone.VariantType != Variant.Type.Object || clone.AsGodotObject() is not Resource copiedResource) return false;
        var result = ResourceSaver.Save(copiedResource, path, ResourceSaver.SaverFlags.RelativePaths);
        if (result != Error.Ok) return Fail(owner, "Unable to write the resource snapshot (error " + (int)result + ")."); return true;
    }
    public string destination(RefCounted owner, string path)
    {
        using var hash = new HashingContext(); hash.Start(HashingContext.HashType.Sha256);
        using var file = FileAccess.Open(path, FileAccess.ModeFlags.Read);
        if (file == null) { Fail(owner, "Cannot read dependency: " + path); return ""; }
        while (file.GetPosition() < file.GetLength())
        {
            var bytes = file.GetBuffer(1048576); if (bytes.Length == 0) { Fail(owner, "Cannot read dependency: " + path); return ""; } hash.Update(bytes);
        }
        string digest = Convert.ToHexString(hash.Finish()).ToLowerInvariant(), destinationRoot = owner.Get("destination_root").AsString();
        string directory = (destinationRoot == "" ? owner.Get("root").AsString() : destinationRoot).PathJoin("assets"); DirAccess.MakeDirRecursiveAbsolute(directory);
        return directory.PathJoin(digest + "." + path.GetExtension().ToLowerInvariant());
    }
    public string copy_file(RefCounted owner, string path)
    {
        var files = Map(owner, "files"); if (files.TryGetValue(path, out var cached)) return cached.AsString();
        string target = destination(owner, path); if (ErrorText(owner) != "") return "";
        if (!FileAccess.FileExists(target) && !copy_bytes(owner, path, target)) return "";
        files[path] = target; Dependencies(owner).Add(target); return target;
    }
    public bool copy_bytes(RefCounted owner, string from, string to)
    {
        if (ProjectSettings.GlobalizePath(from) == ProjectSettings.GlobalizePath(to)) return true;
        using (var source = FileAccess.Open(from, FileAccess.ModeFlags.Read))
        using (var target = FileAccess.Open(to + ".tmp", FileAccess.ModeFlags.Write))
        {
            if (source == null || target == null) return Fail(owner, "Cannot copy required file: " + from);
            while (source.GetPosition() < source.GetLength())
            {
                var bytes = source.GetBuffer(1048576); if (bytes.Length == 0) return Fail(owner, "Cannot read required file: " + from);
                target.StoreBuffer(bytes); if (target.GetError() != Error.Ok) return Fail(owner, "Storage is full or unavailable.");
            }
            target.Flush(); source.Close(); target.Close();
        }
        return DirAccess.RenameAbsolute(to + ".tmp", to) == Error.Ok || Fail(owner, "Cannot complete file copy: " + to);
    }
    public bool self_contained_glb(string path)
    {
        using var file = FileAccess.Open(path, FileAccess.ModeFlags.Read); if (file == null || file.GetLength() < 20 || file.Get32() != 0x46546c67) return false;
        file.Seek(12); uint length = file.Get32(), kind = file.Get32(); if (kind != 0x4e4f534a || length > 16777216 || length > file.GetLength() - 20) return false;
        using var json = new Json(); if (json.Parse(System.Text.Encoding.UTF8.GetString(file.GetBuffer(length))) != Error.Ok || json.Data.VariantType != Variant.Type.Dictionary) return false;
        var data = json.Data.AsGodotDictionary();
        foreach (string key in new[] { "buffers", "images" })
        {
            if (!data.TryGetValue(key, out var items)) continue; if (items.VariantType != Variant.Type.Array) return false;
            foreach (var value in items.AsGodotArray()) { if (value.VariantType != Variant.Type.Dictionary) return false; var item = value.AsGodotDictionary(); if (item.TryGetValue("uri", out var uri) && !uri.AsString().StartsWith("data:", StringComparison.Ordinal)) return false; }
        }
        return true;
    }
    private static readonly Regex Include = new("#include\\s+\"([^\"]+)\"", RegexOptions.CultureInvariant);
    public string inline_shader(RefCounted owner, string code, string baseDirectory, Settings visited)
    {
        string result = code;
        foreach (Match match in Include.Matches(code))
        {
            string path = match.Groups[1].Value; if (!path.IsAbsolutePath() && !path.StartsWith("res://", StringComparison.Ordinal)) path = baseDirectory.PathJoin(path);
            path = path.SimplifyPath();
            if (visited.ContainsKey(path)) { Fail(owner, "Circular shader include: " + path); return code; }
            if (!FileAccess.FileExists(path)) { Fail(owner, "Missing shader include: " + path); return code; }
            var seen = visited.Duplicate(); seen[path] = true; result = result.Replace(match.Value, inline_shader(owner, FileAccess.GetFileAsString(path), path.GetBaseDir(), seen), StringComparison.Ordinal);
        }
        return result;
    }
}
