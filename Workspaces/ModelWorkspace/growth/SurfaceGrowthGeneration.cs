using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

public partial class SurfaceGrowthGeometry
{
    private readonly record struct GeneratedRoot(Settings Data, Vector3I Cell, int Id);
    private readonly ModelModifiers _modifiers = new();
    private readonly ModelMeshOperations _meshes = new();
    private readonly ModelDocumentOperations _documents = new();
    private static long Hash(Variant value) => unchecked((uint)GD.Hash(value));
    private static Resource NewResource(string name) => name switch { "growth/surface_growth_data"=>new KiwiSurfaceGrowthData(), "growth/growth_material"=>new KiwiGrowthMaterial(), "model_component"=>new KiwiModelComponent(), "model_mesh"=>new KiwiModelMesh(), _=>throw new ArgumentException("Unknown growth resource: "+name) };
    private static Vector3I Quantize(Vector3 point) => (Vector3I)(point * 100000).Round();
    public string triangle_key(Vector3 a, Vector3 b, Vector3 c)
    {
        string[] keys = { Quantize(a).ToString(), Quantize(b).ToString(), Quantize(c).ToString() }; Array.Sort(keys, StringComparer.Ordinal); return string.Join(":", keys);
    }
    private Resource NewGrowthComponent(Resource source, int kind, RefCounted session)
    {
        var data = NewResource("growth/surface_growth_data"); data.Set("source_id", source.Get("id")); data.Set("settings", _settings.defaults(kind));
        data.Set("faces", session.Get("mode").AsString() == "Face" ? session.Get("elements").AsInt32Array() : Array.Empty<int>());
        var item = NewResource("model_component"); item.Set("id", Guid.NewGuid().ToString("N")); item.Set("parent_id", source.Get("id")); item.Set("title", new[] { "Hair", "Fur", "Feathers" }[kind]); item.Set("growth", data); item.Set("mesh", NewResource("model_mesh")); return item;
    }
    private static void AddTransaction(RefCounted session, Resource[] items, string title)
    {
        session.Call("begin");
        try
        {
            var document = session.Get("document").As<Resource>(); foreach (var item in items) document.Get("components").AsGodotArray().Add(item);
            var selected = session.Get("selected").AsGodotArray(); selected.Clear(); selected.Add(items[0].Get("id")); session.Set("mode", "Object"); session.Set("elements", Array.Empty<int>()); session.Call("commit", title);
        }
        catch { session.Call("cancel"); throw; }
    }
    public string add(RefCounted session, int kind)
    {
        var source = session.Call("primary").As<Resource>();
        if (source == null || source.Get("mesh").As<Resource>() == null || source.Get("growth").As<Resource>() != null) return "Select a source mesh, then optionally select its faces.";
        var item = NewGrowthComponent(source, kind, session); string error = prepare(session.Get("document").As<Resource>(), item, source); if (error.Length > 0) return error;
        AddTransaction(session, new[] { item }, "Generate " + new[] { "Hair", "Fur", "Feathers" }[kind]); return "";
    }
    public string add_layered_fur(RefCounted session)
    {
        var document = session.Get("document").As<Resource>(); var source = session.Call("primary").As<Resource>();
        if (source != null && source.Get("growth").As<Resource>() is Resource oldGrowth) source = document.Call("component", oldGrowth.Get("source_id")).As<Resource>();
        if (source == null || source.Get("mesh").As<Resource>() == null) return "Select a source mesh for the coat.";
        var layers = new Resource[2];
        for (int i = 0; i < 2; i++)
        {
            bool guard = i == 1; var item = NewGrowthComponent(source, 1, session); item.Set("title", guard ? "Guard hairs" : "Undercoat"); var data = item.Get("growth").As<Resource>();
            Dict(data, "settings").Merge(new Settings { ["density"] = guard ? 24.0 : 240.0, ["length"] = guard ? .22 : .07, ["thickness"] = guard ? .005 : .002, ["seed"] = guard ? 72 : 31, ["guard_hairs"] = 0.0, ["variation"] = .35 }, true);
            string error = prepare(document, item, source); if (error.Length > 0) return error;
            var appearance = data.Get("appearance").As<Resource>(); appearance.Set("root_color", new Color(.12f, .105f, .09f)); appearance.Set("tip_color", guard ? new Color(.22f, .19f, .15f) : new Color(.42f, .4f, .36f)); appearance.Set("roughness", guard ? .55 : .8); layers[i] = item;
        }
        AddTransaction(session, layers, "Generate layered fur coat"); return "";
    }
    public string prepare(Resource document, Resource item, Resource? source)
    {
        var data = item.Get("growth").As<Resource>(); if (data == null) return "Missing growth definition.";
        var settings = Dict(data, "settings");
        if (data.Get("appearance").AsGodotObject() == null)
        {
            var material = NewResource("growth/growth_material"); Color color = Get(settings, "color", new Color(.28f, .12f, .055f)).AsColor(); material.Set("root_color", color); material.Set("tip_color", color.Lightened(.15f)); data.Set("appearance", material);
        }
        if (source == null || source == item || source.Get("growth").AsGodotObject() != null) { data.Set("source_valid", false); return "The source mesh is missing or is another growth system."; }
        Transform3D world = _documents.world_transform(document, source);
        if (Get(settings, "direction_mode", 0).AsInt32() == 1 && data.Get("source_to_rig").AsTransform3D() != world) { data.Set("source_to_rig", world); data.Set("revision", data.Get("revision").AsInt64() + 1); data.Set("render_cache", default(Variant)); }
        ulong start = Time.GetTicksUsec(); Resource editableResource = _modifiers.evaluate(source), meshResource = editableResource;
        var binding = source.Get("binding").As<Resource>(); Mesh? skinMesh = source.Get("skin_mesh").As<Mesh>() ?? binding?.Get("source_mesh").As<Mesh>();
        if (skinMesh != null) meshResource = _meshes.from_mesh(skinMesh);
        var mesh = new ModelMeshOperations.Snapshot(meshResource);
        if (mesh.Faces.Length > 100000 || mesh.Vertices.Length > 100000) return "Growth sources support up to 100,000 vertices/faces. Use a lower-resolution surface.";
        int[] selectedFaces = data.Get("faces").AsInt32Array();
        long signature = Hash(new GArray { meshResource.Get("faces"), mesh.Vertices.Length });
        long key = Hash(new GArray { signature, selectedFaces, Get(settings, "density"), Get(settings, "seed"), Get(settings, "spacing"), Get(settings, "arrangement"), Get(settings, "rows"), Get(settings, "candidate_multiplier"), source.Get("skin_mesh"), binding != null ? binding.Get("revision") : 0 });
        var existing = data.Get("roots").AsGodotArray();
        if (key == data.Get("generation_key").AsInt64() && existing.Count > 0)
        {
            data.Set("source_valid", true); data.Set("error", "");
            if (!data.Get("source_points").AsVector3Array().SequenceEqual(mesh.Vertices))
            {
                data.Set("source_points", mesh.Vertices); data.Set("render_cache", default(Variant)); Dict(data, "candidate_grid").Clear(); data.Set("revision", data.Get("revision").AsInt64() + 1);
                foreach (var row in existing) { var root = row.AsGodotDictionary(); var frame = point_frame(data, root, mesh.Vertices); root["position"] = frame.Origin; root["normal"] = frame.Basis.Y; }
            }
            return "";
        }
        if (data.Get("topology").AsInt64() != 0 && data.Get("topology").AsInt64() != signature)
        { data.Set("source_valid", false); return "Source topology changed. Regenerate to reset old attachments/groom, then choose the new face region. Existing data is preserved until you confirm regeneration."; }
        var mapping = new Dictionary<int, int>();
        if (skinMesh != null && selectedFaces.Length > 0)
        {
            var editable = new ModelMeshOperations.Snapshot(editableResource); var lookup = new Dictionary<string, int>();
            Transform3D transform = binding != null && binding.Get("rigid_bone_id").AsString().Length == 0 ? binding.Get("mesh_to_rig").AsTransform3D() : Transform3D.Identity;
            for (int f = 0; f < editable.Faces.Length; f++)
            {
                int[] corners = editable.Triangles(f), face = editable.Faces[f]; for (int i = 0; i < corners.Length; i += 3) lookup[triangle_key(transform * editable.Vertices[face[corners[i]]], transform * editable.Vertices[face[corners[i + 1]]], transform * editable.Vertices[face[corners[i + 2]]])] = f;
            }
            for (int f = 0; f < mesh.Faces.Length; f++) { int[] face = mesh.Faces[f]; mapping[f] = lookup.GetValueOrDefault(triangle_key(mesh.Vertices[face[0]], mesh.Vertices[face[1]], mesh.Vertices[face[2]]), -1); }
        }
        var triangles = new Godot.Collections.Array<Settings>(); var cumulative = new List<double>(); double area = 0; var faceMask = new HashSet<int>(selectedFaces);
        for (int f = 0; f < mesh.Faces.Length; f++)
        {
            int faceId = mapping.GetValueOrDefault(f, f); if (selectedFaces.Length > 0 && !faceMask.Contains(faceId)) continue;
            int[] corners = mesh.Triangles(f), face = mesh.Faces[f];
            for (int i = 0; i < corners.Length; i += 3)
            {
                var ids = new Vector3I(face[corners[i]], face[corners[i + 1]], face[corners[i + 2]]); Vector3 a = mesh.Vertices[ids.X], b = mesh.Vertices[ids.Y], c = mesh.Vertices[ids.Z]; double size = (b - a).Cross(c - a).Length() * .5;
                if (size < .00000001) continue; area += size; cumulative.Add(area); triangles.Add(new Settings { ["indices"] = ids, ["face"] = faceId, ["normal"] = mesh.Normal(f) });
            }
        }
        if (triangles.Count == 0) { const string message = "The selected surface contains no usable triangles."; data.Set("error", message); return message; }
        double requested = Math.Ceiling(area * Math.Max(0, Get(settings, "density", 35).AsDouble())), count = Math.Ceiling(requested * Math.Clamp(Get(settings, "candidate_multiplier", 2).AsDouble(), 1, 4));
        if (count > 20000) { string message = $"Requested {count:0} candidate roots; the limit is 20000. Lower density or reserve multiplier."; data.Set("error", message); return message; }
        int candidates = (int)count; using var rng = new RandomNumberGenerator { Seed = unchecked((ulong)Get(settings, "seed", 31).AsInt64()) };
        var roots = new List<GeneratedRoot>(); float gridSize = data.Get("grid_size").AsSingle(); double spacing = Get(settings, "spacing", 0).AsDouble(); var grid = new Dictionary<Vector3I, List<Vector3>>();
        bool ordered = Get(settings, "arrangement", 0).AsInt32() == 1; Aabb bounds = _meshes.bounds(meshResource); Vector3 rowNormal = triangles[0]["normal"].AsVector3();
        int depth = (int)rowNormal.Abs().MaxAxisIndex(), uAxis = (depth + 1) % 3, vAxis = (depth + 2) % 3, rows = Math.Max(1, Get(settings, "rows", 4).AsInt32()), columns = Math.Max(1, (int)Math.Ceiling((double)candidates / rows));
        if (ordered && (long)candidates * triangles.Count > 2000000) return "Ordered rows exceed the two-million-triangle-query budget. Reduce density or use a smaller face region.";
        for (int i = 0; i < candidates; i++)
        {
            double sample = rng.Randf() * area; int low = 0, high = cumulative.Count - 1;
            while (low < high) { int middle = (low + high) / 2; if (cumulative[middle] < sample) low = middle + 1; else high = middle; }
            var triangle = triangles[low]; double u = Math.Sqrt(rng.Randf()), v = rng.Randf(); var bary = new Vector3((float)(1 - u), (float)(u * (1 - v)), (float)(u * v));
            Vector3I ids = triangle["indices"].AsVector3I(); Vector3 point = mesh.Vertices[ids.X] * bary.X + mesh.Vertices[ids.Y] * bary.Y + mesh.Vertices[ids.Z] * bary.Z;
            if (ordered)
            {
                Vector3 origin = bounds.Position; origin[depth] -= Math.Max(1, bounds.Size[depth]); origin[uAxis] += (float)(bounds.Size[uAxis] * ((double)(i % rows) + .5) / rows); origin[vAxis] += (float)(bounds.Size[vAxis] * ((double)(i / rows) + .5) / columns);
                Vector3 direction = Vector3.Zero; direction[depth] = 1; float nearest = float.PositiveInfinity; bool found = false;
                foreach (var candidate in triangles)
                {
                    Vector3I at = candidate["indices"].AsVector3I(); Variant hit = Geometry3D.RayIntersectsTriangle(origin, direction, mesh.Vertices[at.X], mesh.Vertices[at.Y], mesh.Vertices[at.Z]);
                    if (hit.VariantType == Variant.Type.Nil || origin.DistanceSquaredTo(hit.AsVector3()) >= nearest) continue;
                    point = hit.AsVector3(); nearest = origin.DistanceSquaredTo(point); ids = at; triangle = candidate; found = true;
                }
                if (!found) continue;
                Vector3 a = mesh.Vertices[ids.X], b = mesh.Vertices[ids.Y] - a, c = mesh.Vertices[ids.Z] - a, offset = point - a;
                double denominator = (double)b.Dot(b) * c.Dot(c) - (double)b.Dot(c) * b.Dot(c);
                double y = ((double)c.Dot(c) * offset.Dot(b) - (double)b.Dot(c) * offset.Dot(c)) / denominator, z = ((double)b.Dot(b) * offset.Dot(c) - (double)b.Dot(c) * offset.Dot(b)) / denominator;
                bary = new Vector3((float)(1 - y - z), (float)y, (float)z);
            }
            bool allowed = true;
            if (spacing > .00001)
            {
                var cell = (Vector3I)(point / (float)spacing).Floor();
                for (int x = -1; x <= 1; x++) for (int y = -1; y <= 1; y++) for (int z = -1; z <= 1; z++)
                    if (grid.TryGetValue(cell + new Vector3I(x, y, z), out var nearby)) foreach (Vector3 other in nearby) if (other.DistanceSquaredTo(point) < spacing * spacing) allowed = false;
                if (allowed) { if (!grid.TryGetValue(cell, out var nearby)) grid[cell] = nearby = new List<Vector3>(); nearby.Add(point); }
            }
            var random = new Vector4(rng.Randf(), rng.Randf(), rng.Randf(), rng.Randf());
            if (allowed) roots.Add(new GeneratedRoot(new Settings { ["id"] = i, ["triangle"] = ids, ["face"] = triangle["face"], ["bary"] = bary, ["normal"] = triangle["normal"], ["random"] = random, ["position"] = point, ["density_rank"] = rng.Randf() }, (Vector3I)(point / gridSize).Floor(), i));
        }
        roots.Sort((a, b) => { int result = a.Cell.X.CompareTo(b.Cell.X); if (result == 0) result = a.Cell.Y.CompareTo(b.Cell.Y); if (result == 0) result = a.Cell.Z.CompareTo(b.Cell.Z); return result == 0 ? a.Id.CompareTo(b.Id) : result; });
        data.Set("surface_triangles", triangles); data.Set("roots", new Godot.Collections.Array<Settings>(roots.Select(root => root.Data))); data.Set("topology", signature); data.Set("source_points", mesh.Vertices); data.Set("generation_key", key); data.Set("source_skin", source.Get("skin")); data.Set("source_to_rig", binding != null ? binding.Get("mesh_to_rig") : world);
        var sourceWeights = new Godot.Collections.Array<Settings>();
        if (skinMesh != null)
        {
            var lookup = new Dictionary<Vector3I, Settings>();
            for (int surface = 0; surface < skinMesh.GetSurfaceCount(); surface++)
            {
                var arrays = skinMesh.SurfaceGetArrays(surface); Vector3[] vertices = arrays[(int)Mesh.ArrayType.Vertex].AsVector3Array();
                float[] weights = arrays[(int)Mesh.ArrayType.Weights].VariantType != Variant.Type.Nil ? arrays[(int)Mesh.ArrayType.Weights].AsFloat32Array() : Array.Empty<float>();
                int[] bones = arrays[(int)Mesh.ArrayType.Bones].VariantType != Variant.Type.Nil ? arrays[(int)Mesh.ArrayType.Bones].AsInt32Array() : Array.Empty<int>(); int width = weights.Length / Math.Max(1, vertices.Length);
                for (int index = 0; index < vertices.Length; index++) { var influences = new Settings(); for (int k = 0; k < width; k++) if (weights[index * width + k] > 0) influences[bones[index * width + k]] = weights[index * width + k]; lookup[Quantize(vertices[index])] = influences; }
            }
            foreach (Vector3 point in mesh.Vertices) sourceWeights.Add(lookup.GetValueOrDefault(Quantize(point), new Settings()));
        }
        data.Set("source_weights", sourceWeights); item.Set("skeleton_id", source.Get("skeleton_id")); data.Set("source_valid", true); Dict(data, "candidate_grid").Clear(); data.Set("render_cache", default(Variant)); data.Set("error", ""); data.Set("generated_usec", Time.GetTicksUsec() - start); data.Set("rigid_bone", -1);
        if (binding != null && binding.Get("rigid_bone_id").AsString().Length > 0)
        {
            var armature = document.Call("component", source.Get("skeleton_id")).As<Resource>(); if (armature != null)
            {
                var bones = armature.Get("bones").AsGodotArray(); for (int i = 0; i < bones.Count; i++) if (bones[i].AsGodotDictionary()["id"].AsString() == binding.Get("rigid_bone_id").AsString()) { data.Set("rigid_bone", i); data.Set("rigid_offset", binding.Get("attachment_offset")); }
            }
        }
        return "";
    }
}
