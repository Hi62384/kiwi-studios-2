using Godot;
using System;
using System.Linq;
using Settings = Godot.Collections.Dictionary;

public partial class ClipboardSnapshotOperations
{
    private Variant FailedValue(RefCounted owner, string message) { Fail(owner, message); return default; }
    public Variant clone_value(RefCounted owner, Variant value, string field)
    {
        var resource = value.VariantType == Variant.Type.Object ? value.AsGodotObject() as Resource : null;
        var resources = Map(owner, "resources");
        if (Is(resource, "res://scripts/actors/physics/destruction/physics_bake_cache.gd"))
        {
            long id = unchecked((long)resource!.GetInstanceId()); if (resources.TryGetValue(id, out var cached)) return cached;
            var clone = resource.Duplicate(false); resources[id] = clone;
            var childResources = resource.Get("resources").AsGodotArray().Duplicate(); childResources.Clear(); clone.Set("resources", childResources);
            foreach (var child in resource.Get("resources").AsGodotArray()) childResources.Add(clone_value(owner, child, ""));
            clone.Set("records", clone_value(owner, resource.Get("records"), ""));
            var chunks = resource.Get("chunks").AsGodotArray().Duplicate(); chunks.Clear(); clone.Set("chunks", chunks); clone.Set("storage_root", "");
            foreach (var valueChunk in resource.Get("chunks").AsGodotArray()) { var chunk = valueChunk.AsGodotDictionary().Duplicate(true); if (chunk.ContainsKey("file")) chunk["file"] = copy_file(owner, chunk["file"].AsString()); chunks.Add(chunk); }
            return clone;
        }
        if (Is(resource, "res://scripts/actors/core/actor_object_reference.gd") && resource!.Get("source").AsInt32() == 1)
        {
            string asset = resource.Get("asset_id").AsString();
            if (!FileAccess.FileExists(asset) || !safe_resource(asset, new Settings())) return FailedValue(owner, "Missing or unsafe resource dependency: " + asset);
            var embedded = ResourceLoader.Load(asset, "", ResourceLoader.CacheMode.Ignore);
            if (!Is(embedded, "res://scripts/actors/core/actor_object_data.gd")) return FailedValue(owner, "Invalid resource dependency: " + asset);
            var copy = clone_value(owner, embedded, "");
            return copy.VariantType == Variant.Type.Object && copy.AsGodotObject() is Resource objectCopy ? Variant.From(_data.from_object(objectCopy)) : default(Variant);
        }
        if (resource is Script script)
        {
            if (!script.ResourcePath.StartsWith("res://", StringComparison.Ordinal)) return FailedValue(owner, "External executable scripts are not supported."); return script;
        }
        if (resource is ImageTexture or CompressedTexture2D or ViewportTexture)
        {
            long id = unchecked((long)resource.GetInstanceId()); if (resources.TryGetValue(id, out var cached)) return cached;
            using var image = ((Texture2D)resource).GetImage();
            if (image == null || image.IsEmpty()) return FailedValue(owner, "The texture has no persistent image data.");
            if (image.IsCompressed() && image.Decompress() != Error.Ok) return FailedValue(owner, "The texture's compression cannot be decoded.");
            if (image.GetFormat() is Image.Format.Rf or Image.Format.Rgf or Image.Format.Rgbf or Image.Format.Rgbaf or Image.Format.Rh or Image.Format.Rgh or Image.Format.Rgbh or Image.Format.Rgbah or Image.Format.Rgbe9995)
            {
                var hdr = ImageTexture.CreateFromImage(image); resources[id] = hdr; return hdr;
            }
            var compact = new PortableCompressedTexture2D { KeepCompressedBuffer = true }; compact.CreateFromImage(image, PortableCompressedTexture2D.CompressionMode.Lossless); resources[id] = compact; return compact;
        }
        if (resource is AudioStreamMicrophone) return FailedValue(owner, "Live microphone streams must be recorded before storing them.");
        if (resource != null)
        {
            long id = unchecked((long)resource.GetInstanceId()); if (resources.TryGetValue(id, out var cached)) return cached;
            var result = resource.Duplicate(false); if (result == null) return FailedValue(owner, "Cannot copy " + resource.GetClass());
            resources[id] = result; result.ResourcePath = "";
            foreach (var property in resource.GetPropertyList())
            {
                string key = property["name"].AsString(); if ((property["usage"].AsInt64() & (long)PropertyUsageFlags.Storage) == 0 || key is "resource_path" or "resource_name" or "resource_local_to_scene") continue;
                if (key == "output_path") { result.Set(key, ""); continue; }
                if (Is(resource, "res://Workspaces/AudioWorkspace/KiwiAudioDocument.cs") && key == "scene_binding") { result.Set(key, new Settings()); continue; }
                result.Set(key, clone_value(owner, resource.Get(key), key));
            }
            if (result is Shader shader) shader.Code = inline_shader(owner, shader.Code, resource.ResourcePath.GetBaseDir(), new Settings()); return result;
        }
        if (value.VariantType == Variant.Type.Dictionary)
        {
            var original = value.AsGodotDictionary(); var result = original.Duplicate(); foreach (var key in result.Keys.ToArray()) result[key] = clone_value(owner, original[key], key.ToString()); return result;
        }
        if (value.VariantType == Variant.Type.Array)
        {
            var original = value.AsGodotArray(); var result = original.Duplicate(); for (int i = 0; i < result.Count; i++) result[i] = clone_value(owner, original[i], field); return result;
        }
        if (value.VariantType is Variant.Type.String or Variant.Type.StringName)
        {
            if (new[] { "code", "text", "label", "name", "display_name", "title", "description", "tooltip_text" }.Contains(field)) return value;
            string path = value.AsString(); if (path == "") return value;
            if (path.IsAbsolutePath() || path.StartsWith("res://", StringComparison.Ordinal) || path.StartsWith("user://", StringComparison.Ordinal))
            {
                if (path.StartsWith("res://", StringComparison.Ordinal) && path.GetExtension() is "gd" or "cs") return value;
                if (!FileAccess.FileExists(path)) { Fail(owner, "Missing dependency: " + path); return value; }
                if (new[] { "tres", "res", "mesh", "material", "gdshader" }.Contains(path.GetExtension().ToLowerInvariant()))
                {
                    var files = Map(owner, "files"); if (files.TryGetValue(path, out var copied)) return copied;
                    if (!safe_resource(path, new Settings())) { Fail(owner, "Unsafe resource dependency: " + path); return value; }
                    string target = destination(owner, path); if (ErrorText(owner) != "") return value; files[path] = target;
                    var original = ResourceLoader.Load(path, "", ResourceLoader.CacheMode.Ignore); var clone = clone_value(owner, original, "");
                    if (clone.VariantType != Variant.Type.Object || clone.AsGodotObject() is not Resource cloned || ResourceSaver.Save(cloned, target, ResourceSaver.SaverFlags.RelativePaths) != Error.Ok) Fail(owner, "Unable to package dependency: " + path);
                    Dependencies(owner).Add(target); return target;
                }
                return copy_file(owner, path);
            }
        }
        if (value.VariantType is Variant.Type.Object or Variant.Type.Callable or Variant.Type.Signal or Variant.Type.Rid) return FailedValue(owner, "Live objects and callbacks cannot be stored as reusable resources.");
        return value;
    }
}
