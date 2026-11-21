using Godot;
using System;
using Settings = Godot.Collections.Dictionary;

public partial class EnvironmentDocumentOperations
{
    private static string Normalize(string path) => ProjectSettings.GlobalizePath(path).Replace('\\', '/').SimplifyPath();
    public bool references_asset(Resource source, string path)
    {
        string target = Normalize(path); var seen = new Settings();
        foreach (var value in source.Get("components").AsGodotArray())
        {
            var parameters = value.As<Resource>().Get("parameters").AsGodotDictionary(); if (Get(parameters, "module_linked", false).AsBool() && references(Get(parameters, "architecture_module_source", ""), target, seen, 0)) return true;
        }
        return references(source.Get("component_settings"), target, seen, 0) || references(source.Get("environment_source"), target, seen, 0) || references(source.Get("atmosphere"), target, seen, 0);
    }
    public bool references(Variant value, string target, Settings seen, int depth)
    {
        if (depth > 16 || seen.Count > 4096) return false;
        if (value.VariantType is Variant.Type.String or Variant.Type.StringName)
        {
            string path = value.AsString(); if (path.Length == 0 || !(path.IsAbsolutePath() || path.StartsWith("res://", StringComparison.Ordinal) || path.StartsWith("user://", StringComparison.Ordinal))) return false;
            if (Normalize(path) == target) return true; string extension = path.GetExtension().ToLowerInvariant(); if (seen.ContainsKey(path) || extension is not ("tres" or "res" or "mesh" or "material") || !ResourceLoader.Exists(path)) return false;
            seen[path] = true; return references(ResourceLoader.Load(path), target, seen, depth + 1);
        }
        if (value.VariantType == Variant.Type.Array) { foreach (var child in value.AsGodotArray()) if (references(child, target, seen, depth + 1)) return true; }
        else if (value.VariantType == Variant.Type.Dictionary) { foreach (var pair in value.AsGodotDictionary()) if (references(pair.Value, target, seen, depth + 1)) return true; }
        else if (value.VariantType == Variant.Type.Object && value.AsGodotObject() is Resource resource && resource is not Script)
        {
            ulong id = resource.GetInstanceId(); if (seen.ContainsKey(id)) return false; seen[id] = true; if (references(resource.ResourcePath, target, seen, depth + 1)) return true;
            foreach (var property in resource.GetPropertyList())
            {
                string name = property["name"].AsString(); if ((property["usage"].AsInt64() & (long)PropertyUsageFlags.Storage) == 0 || name is "script" or "code" or "text" or "title" or "label" or "resource_path") continue;
                if (references(resource.Get(name), target, seen, depth + 1)) return true;
            }
        }
        return false;
    }
}
