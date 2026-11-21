using Godot;
using System;
using System.Collections.Generic;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

public partial class SurfaceGrowthGeometry
{
    private const int MaxVertices = 1000000;
    private const Mesh.ArrayFormat GrowthFormat = (Mesh.ArrayFormat)((ulong)Mesh.ArrayCustomFormat.RgbaFloat << (int)Mesh.ArrayFormat.FormatCustom0Shift | (ulong)Mesh.ArrayCustomFormat.RgbaFloat << (int)Mesh.ArrayFormat.FormatCustom1Shift | (ulong)Mesh.ArrayCustomFormat.RgbaFloat << (int)Mesh.ArrayFormat.FormatCustom2Shift);
    private Settings ResolvedSettings(GodotObject data, Settings root)
    {
        var index = Get(Dict(data, "root_regions"), root["id"], -1);
        return Get(Dict(data, "region_settings"), index, data.Get("base_cache")).AsGodotDictionary();
    }
    // Callers preparing a whole buffer validate region/style caches once, then
    // use these helpers without hashing the same settings for every strand.
    internal Settings PreparedSettings(GodotObject data, Settings root) => ResolvedSettings(data, root);
    internal Settings PreparedStyle(GodotObject data, Settings root) => Style(data, root, ResolvedSettings(data, root));
    public ArrayMesh render_roots(GodotObject data, Vector3[] positions, int first, int last, int region)
    {
        _settings.prepare_regions(data);
        return RenderRoots(data, positions, first, last, region, data.Get("source_points").AsVector3Array());
    }
    private ArrayMesh RenderRoots(GodotObject data, Vector3[] positions, int first, int last, int region, Vector3[] source)
    {
        var vertices = new List<Vector3>(); var normals = new List<Vector3>(); var uv = new List<Vector2>(); var colors = new List<Color>(); var indices = new List<int>();
        var tangents = new List<float>(); var attributes = new List<float>(); var centers = new List<float>(); var attachments = new List<float>();
        var roots = data.Get("roots").AsGodotArray(); var rootRegions = Dict(data, "root_regions");
        bool feather = Get(Dict(data, "base_cache"), "type", 0).AsInt32() == 2;
        float lodUpper = data.Get("lod_upper").AsSingle();
        void Four(List<float> buffer, Vector3 vector, float fourth) { buffer.Add(vector.X); buffer.Add(vector.Y); buffer.Add(vector.Z); buffer.Add(fourth); }
        void Quad(int a, int b, int c, int d) { indices.Add(a); indices.Add(b); indices.Add(c); indices.Add(c); indices.Add(b); indices.Add(d); }
        for (int index = first; index < last; index++)
        {
            var root = roots[index].AsGodotDictionary(); if (Get(rootRegions, root["id"], -1).AsInt32() != region) continue;
            var settings = ResolvedSettings(data, root); Vector4 random = root["random"].AsVector4(); if (random.Z > lodUpper) continue;
            var edit = Style(data, root, settings);
            if (root["density_rank"].AsDouble() > edit["density"].AsDouble() || edit["length"].AsDouble() < .0001) continue;
            float S(string key, double fallback) => Get(settings, key, fallback).AsSingle();
            float E(string key, double fallback) => Get(edit, key, fallback).AsSingle();
            var frame = point_frame(data, root, positions); var points = Curve(data, root, -1, settings, edit, source);
            float width = feather ? E("width", S("width", .14)) : E("thickness", S("thickness", .012)); width *= Mathf.Lerp(.8f, 1.2f, random.W);
            if (feather) { width *= 1 + S("overlap", .3); if ((int)S("feather_type", 1) == 0) width *= 1.3f; }
            int offset = vertices.Count, section = (int)S("cross_section", 0), sides = feather || section == 0 ? 2 : section == 1 ? 4 : section == 2 ? 6 : 8;
            Vector3 sideDirection = Vector3.Right; Color color = Get(edit, "color", Colors.White).AsColor(); Vector3 rootPosition = root["position"].AsVector3(), bary = root["bary"].AsVector3();
            for (int i = 0; i < points.Length; i++)
            {
                float t = (float)i / (points.Length - 1), tipRatio = S("tip_thickness", -1) / Math.Max(.00001f, width);
                if (tipRatio < 0) tipRatio = 1 - S("taper", .9);
                float profile = feather ? Mathf.Pow(Math.Max(0, Mathf.Sin(Mathf.Pow(t, .65f) * Mathf.Pi)), S("feather_tip", 1)) * .5f : Math.Max(.001f, Mathf.Lerp(1, tipRatio, t)) * .5f;
                Vector3 tangent = (points[Math.Min(i + 1, points.Length - 1)] - points[Math.Max(0, i - 1)]).Normalized();
                sideDirection -= tangent * sideDirection.Dot(tangent);
                if (sideDirection.LengthSquared() < .00001f) sideDirection = Vector3.Forward - tangent * tangent.Z;
                sideDirection = sideDirection.Normalized();
                Vector3 rotatedSide = sideDirection.Rotated(tangent, S("twist", 0) * t + Mathf.DegToRad(E("roll", 0))), binormal = rotatedSide.Cross(tangent).Normalized();
                Vector3 side = rotatedSide * width * Math.Max(.01f, profile), worldTangent = (frame.Basis * tangent).Normalized(), normal = (frame.Basis * sideDirection.Cross(tangent)).Normalized(), center = frame * points[i];
                for (int edge = 0; edge < sides; edge++)
                {
                    float sign = edge == 0 ? -1 : 1; Vector3 radial = rotatedSide * Mathf.Cos((float)edge / sides * Mathf.Tau) + binormal * Mathf.Sin((float)edge / sides * Mathf.Tau) * S("flatten", .6);
                    Vector3 displacement = sides == 2 ? side * sign * (1 + sign * S("feather_asymmetry", 0)) : radial * width * Math.Max(.01f, profile);
                    vertices.Add(frame * (points[i] + displacement)); normals.Add(sides == 2 ? normal : (frame.Basis * radial).Normalized()); uv.Add(new Vector2((float)edge / Math.Max(1, sides - 1), t)); colors.Add(color);
                    Four(tangents, worldTangent, 1); Four(attributes, rootPosition, random.Z + (feather ? 1 : 0)); Four(centers, center, 1); Four(attachments, bary, index);
                }
            }
            for (int i = 0; i < points.Length - 1; i++)
                for (int edge = 0; edge < (sides == 2 ? 1 : sides); edge++)
                {
                    int at = offset + i * sides + edge, next = offset + i * sides + (edge + 1) % sides; Quad(at, at + sides, next, next + sides);
                }
            if (feather)
            {
                int shaft = vertices.Count;
                for (int i = 0; i < points.Length; i++)
                {
                    Vector3 tangent = (frame.Basis * (points[Math.Min(i + 1, points.Length - 1)] - points[Math.Max(0, i - 1)])).Normalized(), center = frame * points[i];
                    foreach (float sign in new[] { -1f, 1f })
                    {
                        vertices.Add(frame * (points[i] + new Vector3(sign * width * .025f, 0, .002f))); normals.Add(frame.Basis.Z); uv.Add(new Vector2((sign + 1) * .5f, (float)i / (points.Length - 1))); colors.Add(Colors.White);
                        Four(tangents, tangent, 1); Four(attributes, rootPosition, -1 - random.Z); Four(centers, center, 1); Four(attachments, bary, index);
                    }
                }
                for (int i = 0; i < points.Length - 1; i++) { int at = shaft + i * 2; Quad(at, at + 2, at + 1, at + 3); }
            }
            if (vertices.Count > MaxVertices) { data.Set("error", "Growth exceeded the one-million-vertex budget. Reduce quality or density."); return new ArrayMesh(); }
        }
        var result = new ArrayMesh(); if (vertices.Count == 0) return result;
        var arrays = new GArray(); arrays.Resize((int)Mesh.ArrayType.Max);
        arrays[(int)Mesh.ArrayType.Vertex] = vertices.ToArray(); arrays[(int)Mesh.ArrayType.Normal] = normals.ToArray(); arrays[(int)Mesh.ArrayType.Tangent] = tangents.ToArray();
        arrays[(int)Mesh.ArrayType.Custom0] = attributes.ToArray(); arrays[(int)Mesh.ArrayType.Custom1] = centers.ToArray(); arrays[(int)Mesh.ArrayType.Custom2] = attachments.ToArray();
        arrays[(int)Mesh.ArrayType.TexUV] = uv.ToArray(); arrays[(int)Mesh.ArrayType.Color] = colors.ToArray(); arrays[(int)Mesh.ArrayType.Index] = indices.ToArray();
        result.AddSurfaceFromArrays(Mesh.PrimitiveType.Triangles, arrays, flags: GrowthFormat); return result;
    }
    public ArrayMesh render_chunk(GodotObject data, Vector3[] positions, int first, int last)
    {
        _settings.prepare_regions(data);
        return RenderChunk(data, positions, first, last, data.Get("source_points").AsVector3Array());
    }
    private ArrayMesh RenderChunk(GodotObject data, Vector3[] positions, int first, int last, Vector3[] source)
    {
        var groups = new HashSet<int>(); var roots = data.Get("roots").AsGodotArray(); var rootRegions = Dict(data, "root_regions");
        for (int i = first; i < last; i++) groups.Add(Get(rootRegions, roots[i].AsGodotDictionary()["id"], -1).AsInt32());
        var result = new ArrayMesh(); var regions = new List<int>();
        foreach (int region in groups)
        {
            var geometry = RenderRoots(data, positions, first, last, region, source);
            if (groups.Count == 1) { geometry.SetMeta("growth_regions", new[] { region }); return geometry; }
            if (geometry.GetSurfaceCount() == 0) continue;
            result.AddSurfaceFromArrays(Mesh.PrimitiveType.Triangles, geometry.SurfaceGetArrays(0), flags: GrowthFormat);
            result.SurfaceSetMaterial(result.GetSurfaceCount() - 1, _settings.region_material(data, region)); regions.Add(region);
        }
        result.SetMeta("growth_regions", regions.ToArray()); return result;
    }
    public ArrayMesh render(GodotObject data, Vector3[] positions)
    {
        if (!data.Get("source_valid").AsBool()) return new ArrayMesh();
        var appearance = data.Get("appearance").AsGodotObject();
        if (appearance == null)
        {
            appearance = new KiwiGrowthMaterial();
            Color color = Get(Dict(data, "settings"), "color", new Color(.28f, .12f, .055f)).AsColor();
            appearance.Set("root_color", color); appearance.Set("tip_color", color.Lightened(.15f)); data.Set("appearance", appearance);
        }
        data.Set("material", appearance.Call("material")); _settings.prepare_regions(data);
        foreach (var row in data.Get("regions").AsGodotArray())
        {
            var material = Get(row.AsGodotDictionary(), "material").AsGodotObject(); if (material != null && material.HasMethod("material")) material.Call("material");
        }
        var cached = data.Get("render_cache").As<ArrayMesh>();
        if (cached != null)
            for (int surface = 0; surface < cached.GetSurfaceCount(); surface++) cached.SurfaceSetMaterial(surface, _settings.region_material(data, Get(Dict(data, "surface_regions"), surface, -1).AsInt32()));
        var geometrySettings = _settings.base_settings(data).Duplicate(); geometrySettings.Remove("color");
        var motion = data.Get("gpu_motion").AsBool() ? new Settings() : Dict(data, "motion_guides");
        var keyInputs = new GArray { data.Get("generation_key"), geometrySettings, data.Get("region_signature"), data.Get("revision"), data.Get("groom_enabled"), data.Get("guides"), motion, data.Get("gpu_motion"), data.Get("lod_upper"), data.Get("lod_detail"), data.Get("render_final") };
        long key = unchecked((uint)GD.Hash(keyInputs));
        if (positions.Length == 0 && cached != null && data.Get("render_key").AsInt64() == key) return cached;
        bool deformed = positions.Length != 0; Vector3[] source = data.Get("source_points").AsVector3Array(); if (!deformed) positions = source;
        var baseInputs = new GArray { data.Get("generation_key"), geometrySettings, data.Get("region_signature"), data.Get("groom_enabled"), data.Get("guides"), motion, data.Get("gpu_motion"), data.Get("lod_upper"), data.Get("lod_detail"), data.Get("render_final"), positions };
        long signature = unchecked((uint)GD.Hash(baseInputs));
        var dirty = Dict(data, "dirty_chunks"); var chunks = Dict(data, "chunks"); var surfaceChunks = Dict(data, "surface_chunks");
        bool rebuild = deformed || cached == null || data.Get("chunk_signature").AsInt64() != signature || (data.Get("chunk_revision").AsInt64() != data.Get("revision").AsInt64() && dirty.Count == 0);
        if (rebuild) { chunks.Clear(); surfaceChunks.Clear(); Dict(data, "surface_regions").Clear(); }
        data.Set("chunk_signature", signature); var result = rebuild ? new ArrayMesh() : cached!; int vertices = 0, rootCount = data.Get("roots").AsGodotArray().Count;
        for (int chunk = 0; chunk < (rootCount + 127) / 128; chunk++)
        {
            bool changed = !chunks.ContainsKey(chunk) || dirty.ContainsKey(chunk);
            if (changed)
            {
                data.Set("chunk_builds", data.Get("chunk_builds").AsInt64() + 1);
                chunks[chunk] = RenderChunk(data, positions, chunk * 128, Math.Min((chunk + 1) * 128, rootCount), source);
                if (surfaceChunks.ContainsKey(chunk))
                {
                    var removals = new List<int>(); foreach (var index in surfaceChunks[chunk].AsGodotArray()) removals.Add(index.AsInt32()); removals.Sort(); removals.Reverse(); surfaceChunks.Remove(chunk);
                    foreach (int removed in removals)
                    {
                        result.SurfaceRemove(removed);
                        foreach (var pair in surfaceChunks)
                        {
                            var surfaces = pair.Value.AsGodotArray(); for (int i = 0; i < surfaces.Count; i++) if (surfaces[i].AsInt32() > removed) surfaces[i] = surfaces[i].AsInt32() - 1;
                        }
                        var shifted = new Settings(); foreach (var pair in Dict(data, "surface_regions")) { int index = pair.Key.AsInt32(); if (index != removed) shifted[index > removed ? index - 1 : index] = pair.Value; } data.Set("surface_regions", shifted);
                    }
                }
            }
            var mesh = chunks[chunk].As<ArrayMesh>(); if (mesh.GetSurfaceCount() == 0) continue;
            for (int surface = 0; surface < mesh.GetSurfaceCount(); surface++) vertices += mesh.SurfaceGetArrayLen(surface);
            if (vertices > MaxVertices) { data.Set("error", "Growth exceeds the one-million-vertex budget. Reduce quality/density."); return new ArrayMesh(); }
            if (changed)
            {
                var surfaces = new GArray(); surfaceChunks[chunk] = surfaces; int[] regions = mesh.GetMeta("growth_regions").AsInt32Array();
                for (int surface = 0; surface < mesh.GetSurfaceCount(); surface++)
                {
                    int index = result.GetSurfaceCount(), region = regions[surface]; surfaces.Add(index); Dict(data, "surface_regions")[index] = region;
                    result.AddSurfaceFromArrays(Mesh.PrimitiveType.Triangles, mesh.SurfaceGetArrays(surface), flags: GrowthFormat); result.SurfaceSetMaterial(index, _settings.region_material(data, region));
                }
            }
        }
        dirty.Clear(); data.Set("chunk_revision", data.Get("revision")); if (!deformed) { data.Set("render_cache", result); data.Set("render_key", key); } return result;
    }
}
