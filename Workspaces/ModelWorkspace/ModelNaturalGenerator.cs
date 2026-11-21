using Godot;
using System;
using System.Linq;
using System.Collections.Generic;
using Settings = Godot.Collections.Dictionary;
using Topology = ModelGeometryOperations.Topology;

public partial class ModelNaturalGenerator : RefCounted
{
    private const int MaxVertices = 200000;
    private const long CacheBytes = 67108864;
    private static readonly object CacheLock = new();
    private static readonly Dictionary<long, (Settings Result, long Bytes)> Cache = new();
    private static long _cacheBytes;
    private readonly ModelNaturalSettings _settings = new();
    private readonly ModelMeshOperations _meshes = new();
    private sealed class Build
    {
        internal readonly Topology Mesh = new() { Smooth = true };
        internal readonly Godot.Collections.Array<Settings> Graph = new(), Leaves = new();
        internal readonly Func<bool> Cancel;
        internal Build(Func<bool> cancel) { Cancel = cancel; }
        internal bool Stop() => Mesh.Points.Count > MaxVertices || Cancel();
    }
    private static float F(Settings p, string key, float fallback = 0) => p.TryGetValue(key, out var value) ? value.AsSingle() : fallback;
    private static int I(Settings p, string key, int fallback = 0) => p.TryGetValue(key, out var value) ? value.AsInt32() : fallback;
    private static bool Conifer(string name) => name == "Pine" || name == "Spruce" || name == "Fir";
    private static Settings Cancelled() => new() { ["mesh"] = default(Variant), ["cancelled"] = true, ["error"] = "Generation cancelled." };
    private Settings Copy(Settings source) { var copy = source.Duplicate(true); copy["mesh"] = _meshes.copy_mesh(source["mesh"].As<Resource>()); return copy; }
    public static void ClearCache()
    {
        lock (CacheLock)
        {
            foreach (var entry in Cache.Values) { entry.Result.Clear(); entry.Result.Dispose(); }
            Cache.Clear(); _cacheBytes = 0;
        }
    }
    public Settings cache_info() { lock (CacheLock) return new Settings { ["bytes"] = _cacheBytes, ["entries"] = Cache.Count }; }
    public Settings generate(string kind, Settings settings, GodotObject? cancellation) => Generate(kind, settings, () => cancellation != null && cancellation.Call("cancelled").AsBool());
    internal Settings Generate(string kind, Settings settings, Func<bool> cancel)
    {
        var p = _settings.defaults(kind); p.Merge(settings, true); if (cancel()) return Cancelled();
        p["height"] = Math.Clamp(p["height"].AsDouble(), .02, 200); p["radius"] = Math.Clamp(p["radius"].AsDouble(), .005, 30);
        foreach (var (key, minimum, maximum) in new[] { ("segments", 4, 16), ("levels", 0, 3), ("branches", 1, 16), ("detail", 6, 32), ("roots", 0, 16) }) p[key] = Mathf.Clamp(I(p, key), minimum, maximum);
        long keyHash = GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/terrain/terrain_data_hash.gd").Call("value", new Godot.Collections.Array { kind, p }).AsInt64();
        lock (CacheLock) if (Cache.TryGetValue(keyHash, out var cached)) { var copy = Copy(cached.Result); return cancel() ? Cancelled() : copy; }
        using var rng = new RandomNumberGenerator { Seed = (ulong)p["seed"].AsInt64() }; var build = new Build(cancel); string name = kind.Contains(" / ") ? kind.Split(" / ")[1] : "";
        if (kind.StartsWith("Rock", StringComparison.Ordinal) || name == "Stalactite" || name == "Stalagmite") Rock(build, build.Mesh, name, p, rng);
        else if (kind.StartsWith("Plant", StringComparison.Ordinal)) Plant(build, name, p, rng); else Tree(build, name, p, rng);
        if (p.TryGetValue("_error", out var error)) return new Settings { ["mesh"] = default(Variant), ["cancelled"] = false, ["error"] = error };
        if (cancel()) return Cancelled(); if (build.Mesh.Points.Count > MaxVertices) return new Settings { ["mesh"] = default(Variant), ["cancelled"] = false, ["error"] = "Natural geometry budget exceeded. Reduce branch levels, density or detail." };
        var mesh = build.Mesh; for (int f = mesh.Faces.Count - 1; f >= 0; f--) if (mesh.Faces[f].Length == 0) { mesh.Faces.RemoveAt(f); mesh.Uv.RemoveAt(f); mesh.Materials.RemoveAt(f); }
        var result = new Settings { ["mesh"] = mesh.Build(), ["branches"] = build.Graph, ["attachments"] = build.Leaves, ["settings"] = p, ["signature"] = keyHash, ["version"] = 1 };
        long bytes = mesh.Points.Count * 12L + mesh.Materials.Count * 4L + build.Leaves.Count * 96L + build.Graph.Count * 512L + mesh.Faces.Sum(face => face.Length * 12L);
        if (bytes <= CacheBytes)
        {
            var stored = Copy(result); lock (CacheLock)
            {
                if (Cache.Remove(keyHash, out var old)) { _cacheBytes -= old.Bytes; old.Result.Clear(); old.Result.Dispose(); }
                while (Cache.Count > 0 && (_cacheBytes + bytes > CacheBytes || Cache.Count >= 24)) { long oldest = Cache.Keys.First(); var evicted = Cache[oldest]; _cacheBytes -= evicted.Bytes; Cache.Remove(oldest); evicted.Result.Clear(); evicted.Result.Dispose(); }
                Cache[keyHash] = (stored, bytes); _cacheBytes += bytes;
            }
        }
        return result;
    }
}
