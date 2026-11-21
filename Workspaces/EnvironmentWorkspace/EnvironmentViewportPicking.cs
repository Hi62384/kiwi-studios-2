using Godot;
using System;
using System.Linq;
using System.Collections.Generic;
using Settings = Godot.Collections.Dictionary;

public partial class EnvironmentViewportRuntime
{
    private static bool RayBounds(Aabb box, Vector3 origin, Vector3 direction)
    {
        float near = 0, far = float.PositiveInfinity;
        for (int axis = 0; axis < 3; axis++)
        {
            if (Math.Abs(direction[axis]) < 1e-12f) { if (origin[axis] < box.Position[axis] || origin[axis] > box.End[axis]) return false; continue; }
            float a = (box.Position[axis] - origin[axis]) / direction[axis], b = (box.End[axis] - origin[axis]) / direction[axis]; near = Math.Max(near, Math.Min(a, b)); far = Math.Min(far, Math.Max(a, b)); if (near > far) return false;
        }
        return true;
    }
    public Settings pick(Control canvas, Vector2 point, bool terrainOnly, string[] excluded)
    {
        if (canvas.Get("_pending_sync").AsBool()) sync(canvas); var ray = _picking.ray(canvas, point); Vector3 rayOrigin = ray["origin"].AsVector3(), rayDirection = ray["direction"].AsVector3(); var camera = canvas.Get("camera").As<Camera3D>(); float best = camera.Far; var result = new Settings();
        var document = Document(canvas); var nodes = Dict(Renderer(canvas), "nodes"); var cache = Dict(canvas, "_triangles"); var skip = new HashSet<string>(excluded, StringComparer.Ordinal);
        foreach (var value in document.Get("components").AsGodotArray())
        {
            var item = value.As<Resource>(); string id = item.Get("id").AsString(); if (skip.Contains(id) || !_documents.editable_component(document, item) || !nodes.ContainsKey(id)) continue;
            if (terrainOnly && document.Call("component_kind", id).AsString() != "terrain") continue; var owner = nodes[id].As<Node3D>();
            foreach (var child in owner.FindChildren("*", "MeshInstance3D", true, false))
            {
                var visual = (MeshInstance3D)child; if (terrainOnly && visual.GetMeta("terrain_water", false).AsBool()) continue; var mesh = visual.Mesh;
                if (mesh == null || !visual.IsVisibleInTree() || Math.Abs(visual.GlobalBasis.Determinant()) < .000001f) continue;
                Aabb bounds = mesh.GetAabb(); if (visual.VisibilityRangeEnd > 0 && camera.GlobalPosition.DistanceTo(visual.GlobalTransform * bounds.GetCenter()) > visual.VisibilityRangeEnd + visual.VisibilityRangeEndMargin) continue;
                var inverse = visual.GlobalTransform.AffineInverse(); Vector3 origin = inverse * rayOrigin, direction = (inverse.Basis * rayDirection).Normalized(); if (!RayBounds(bounds, origin, direction)) continue;
                ulong key = mesh.GetInstanceId(); if (!cache.ContainsKey(key)) { if (cache.Count >= 128) cache.Remove(cache.Keys.First()); cache[key] = mesh.GenerateTriangleMesh(); }
                var triangles = cache[key].As<TriangleMesh>(); if (triangles == null) continue; var hit = triangles.IntersectRay(origin, direction); if (hit.Count == 0) continue;
                Vector3 worldPoint = visual.GlobalTransform * hit["position"].AsVector3(); float distance = rayOrigin.DistanceTo(worldPoint); if (distance >= best) continue;
                best = distance; var transform = _documents.world_transform(document, item); result = new Settings { ["id"] = id, ["point"] = worldPoint, ["local"] = transform.AffineInverse() * worldPoint, ["normal"] = (visual.GlobalBasis.Inverse().Transposed() * hit["normal"].AsVector3()).Normalized() };
            }
        }
        return result;
    }
    public void draw(Control canvas)
    {
        var session = canvas.Get("session").As<RefCounted>(); if (session == null) return; var document = Document(canvas); var camera = canvas.Get("camera").As<Camera3D>(); var overlay = canvas.Get("overlay").As<Control>(); var primary = session.Call("primary").As<Resource>();
        foreach (var id in session.Get("selected").AsGodotArray())
        {
            var item = _documents.component(document, id.AsString()); if (item == null || item.Get("mesh").As<Resource>() is not Resource mesh || !_documents.visible_component(document, item)) continue;
            var transform = _documents.world_transform(document, item); var box = _meshes.bounds(mesh); var points = new Vector3[8]; for (int corner = 0; corner < 8; corner++) points[corner] = transform * (box.Position + box.Size * new Vector3(corner & 1, (corner >> 1) & 1, (corner >> 2) & 1));
            for (int corner = 0; corner < 8; corner++) for (int axis = 0; axis < 3; axis++)
            {
                int other = corner ^ (1 << axis); if (other < corner || camera.IsPositionBehind(points[corner]) || camera.IsPositionBehind(points[other])) continue;
                overlay.DrawLine(_picking.project(canvas, points[corner]), _picking.project(canvas, points[other]), item == primary ? new Color("ffca7d") : new Color("6bbfee"), 1.5f, true);
            }
        }
        _overlay.draw_handles_and_navigation(canvas, "RMB fly · MMB orbit · Shift+MMB pan · F frame · W/E/R transform"); foreach (string name in new[] { "cave_tool", "water_tool", "road_tool" }) Tool(canvas, name).Call("draw");
        string mode = Mode(canvas); var hit = Dict(canvas, "_brush_hit");
        if ((Array.IndexOf(BrushTools, mode) >= 0 || mode is "Paint material" or "Paint biome" or "Erase biome" or "Paint scatter" or "Erase scatter") && hit.Count > 0)
        {
            string id = hit["id"].AsString(); var item = _documents.component(document, id); var terrain = document.Call("terrain", id).As<Resource>(); if (item == null || terrain == null) return;
            Vector3 local = hit["local"].AsVector3(); var transform = _documents.world_transform(document, item); var ring = new List<Vector2>(); bool square = canvas.Get("brush_square").AsBool(); float radius = canvas.Get("brush_radius").AsSingle();
            for (int i = 0; i < 49; i++)
            {
                double angle = i * Math.Tau / 48; var direction = new Vector2((float)Math.Cos(angle), (float)Math.Sin(angle)); if (square) direction /= Math.Max(Math.Abs(direction.X), Math.Abs(direction.Y));
                Vector2 point = new Vector2(local.X, local.Z) + direction * radius; var surface = terrain.Call("sample", point).AsGodotDictionary(); if (surface.Count > 0) ring.Add(_picking.project(canvas, transform * new Vector3(point.X, surface["height"].AsSingle() + .025f, point.Y)));
            }
            if (ring.Count > 1) overlay.DrawPolyline(ring.ToArray(), new Color("7de3c5"), 2, true);
        }
    }
}
