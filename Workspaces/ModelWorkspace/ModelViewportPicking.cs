using Godot;
using System;
using System.Linq;
using System.Collections.Generic;
using Settings = Godot.Collections.Dictionary;

public partial class ModelViewportPicking : RefCounted
{
    private static bool IntersectsRay(Aabb bounds, Vector3 origin, Vector3 direction)
    {
        float near = 0, far = float.PositiveInfinity;
        for (int axis = 0; axis < 3; axis++)
        {
            if (Mathf.Abs(direction[axis]) < 1e-12f) { if (origin[axis] < bounds.Position[axis] || origin[axis] > bounds.End[axis]) return false; continue; }
            float a = (bounds.Position[axis] - origin[axis]) / direction[axis], b = (bounds.End[axis] - origin[axis]) / direction[axis];
            near = Mathf.Max(near, Mathf.Min(a, b)); far = Mathf.Min(far, Mathf.Max(a, b)); if (near > far) return false;
        }
        return true;
    }
    public Vector2 project(Control canvas, Vector3 point) => canvas.Get("camera").As<Camera3D>().UnprojectPosition(point) * canvas.Size / (Vector2)canvas.Get("viewport").As<SubViewport>().Size;
    public Settings ray(Control canvas, Vector2 point)
    {
        var camera = canvas.Get("camera").As<Camera3D>();
        Vector2 p = point * (Vector2)canvas.Get("viewport").As<SubViewport>().Size / canvas.Size;
        return new Settings { ["origin"] = camera.ProjectRayOrigin(p), ["direction"] = camera.ProjectRayNormal(p) };
    }
    public Settings pick(Control canvas, Vector2 point, Godot.Collections.Array<string> excluded)
    {
        var visuals = canvas.Get("visuals").AsGodotDictionary();
        if (canvas.Get("_pending_sync").AsBool() && (visuals.Count == 0 || (!canvas.Get("_pressed").AsBool() && !canvas.Get("_drag").AsBool() && !canvas.Get("_extruding").AsBool())))
        { canvas.Call("sync"); visuals = canvas.Get("visuals").AsGodotDictionary(); }
        var session = canvas.Get("session").As<RefCounted>();
        var lookup = ModelDocumentOperations.Lookup(session.Get("document").As<Resource>());
        var hidden = canvas.Get("preview_hidden").AsGodotDictionary();
        var r = ray(canvas, point); Vector3 origin = r["origin"].AsVector3(), direction = r["direction"].AsVector3();
        float best = float.PositiveInfinity; var result = new Settings();
        foreach (var item in lookup.Values)
        {
            string id = item.Get("id").AsString();
            if (excluded.Contains(id) || hidden.ContainsKey(id) || !ModelDocumentOperations.Accessible(lookup, item, true) || !visuals.TryGetValue(id, out var value)) continue;
            var visual = value.As<MeshInstance3D>(); var mesh = visual.Mesh; Transform3D transform = visual.Transform;
            if (!visual.IsVisibleInTree() || mesh == null || mesh.GetSurfaceCount() == 0 || Mathf.Abs(transform.Basis.Determinant()) < .000001f) continue;
            Transform3D inverse = transform.AffineInverse(); Vector3 localOrigin = inverse * origin, localDirection = (inverse.Basis * direction).Normalized();
            if (!IntersectsRay(mesh.GetAabb(), localOrigin, localDirection)) continue;
            var triangles = mesh.GenerateTriangleMesh(); if (triangles == null) continue;
            var hit = triangles.IntersectRay(localOrigin, localDirection); if (hit.Count == 0) continue;
            Vector3 local = hit["position"].AsVector3(), world = transform * local; float distance = origin.DistanceTo(world);
            if (distance >= best) continue;
            best = distance; result = new Settings { ["id"] = id, ["point"] = world, ["normal"] = (transform.Basis.Inverse().Transposed() * hit["normal"].AsVector3()).Normalized(), ["local"] = local };
        }
        return result;
    }
    public int face_at(Control canvas, Resource item, Vector2 point)
    {
        var session = canvas.Get("session").As<RefCounted>(); var lookup = ModelDocumentOperations.Lookup(session.Get("document").As<Resource>());
        var transform = ModelDocumentOperations.WorldTransform(lookup, item); if (Mathf.Abs(transform.Basis.Determinant()) < .000001f) return -1;
        var r = ray(canvas, point); var inverse = transform.AffineInverse(); Vector3 origin = inverse * r["origin"].AsVector3(), direction = (inverse.Basis * r["direction"].AsVector3()).Normalized();
        var data = new ModelMeshOperations.Snapshot(item.Get("mesh").As<Resource>()); float best = float.PositiveInfinity; int chosen = -1;
        for (int f = 0; f < data.Faces.Length; f++)
        {
            int[] face = data.Faces[f], triangles = data.Triangles(f);
            for (int i = 0; i < triangles.Length; i += 3)
            {
                Variant hit = Geometry3D.RayIntersectsTriangle(origin, direction, data.Vertices[face[triangles[i]]], data.Vertices[face[triangles[i + 1]]], data.Vertices[face[triangles[i + 2]]]);
                if (hit.VariantType == Variant.Type.Nil) continue; float distance = origin.DistanceTo(hit.AsVector3()); if (distance < best) { best = distance; chosen = f; }
            }
        }
        return chosen;
    }
    public bool visible_point(Control canvas, Vector3 point)
    {
        var camera = canvas.Get("camera").As<Camera3D>(); if (camera.IsPositionBehind(point)) return false;
        if (canvas.Get("xray").AsBool()) return true;
        var hit = canvas.Call("pick", project(canvas, point), new Godot.Collections.Array<string>()).AsGodotDictionary();
        return hit.Count == 0 || camera.GlobalPosition.DistanceTo(point) <= camera.GlobalPosition.DistanceTo(hit["point"].AsVector3()) + .025f;
    }
    public int element_at(Control canvas, Vector2 point)
    {
        var session = canvas.Get("session").As<RefCounted>(); var item = session.Call("primary").As<Resource>(); var mesh = item?.Get("mesh").As<Resource>(); if (mesh == null) return -1;
        string mode = session.Get("mode").AsString(); if (mode == "Face") return face_at(canvas, item!, point);
        var lookup = ModelDocumentOperations.Lookup(session.Get("document").As<Resource>()); Transform3D transform = ModelDocumentOperations.WorldTransform(lookup, item!);
        var data = new ModelMeshOperations.Snapshot(mesh); float best = 11; int chosen = -1;
        if (mode == "Vertex")
        {
            for (int i = 0; i < data.Vertices.Length; i++) { Vector3 p = transform * data.Vertices[i]; float distance = project(canvas, p).DistanceTo(point); if (distance < best && visible_point(canvas, p)) { best = distance; chosen = i; } }
        }
        else
        {
            var edges = ModelGeometryOperations.Edges(data.Faces);
            for (int i = 0; i < edges.Count; i++) { var edge = edges[i]; Vector3 a = transform * data.Vertices[edge.A], b = transform * data.Vertices[edge.B]; float distance = Geometry2D.GetClosestPointToSegment(point, project(canvas, a), project(canvas, b)).DistanceTo(point); if (distance < best && visible_point(canvas, (a + b) * .5f)) { best = distance; chosen = i; } }
        }
        return chosen;
    }
    public void select_at(Control canvas, Vector2 point, bool additive)
    {
        var session = canvas.Get("session").As<RefCounted>();
        if (session.Get("mode").AsString() == "Object") { var hit = canvas.Call("pick", point, new Godot.Collections.Array<string>()).AsGodotDictionary(); session.Call("select", hit.TryGetValue("id", out var id) ? id.AsString() : "", additive); return; }
        int index = element_at(canvas, point); var elements = additive ? session.Get("elements").AsInt32Array().ToList() : new List<int>();
        if (index >= 0 && !elements.Remove(index)) elements.Add(index);
        session.Set("elements", elements.ToArray()); session.EmitSignal("changed");
    }
    public void box_select(Control canvas, Rect2 rect, bool additive)
    {
        var session = canvas.Get("session").As<RefCounted>(); var lookup = ModelDocumentOperations.Lookup(session.Get("document").As<Resource>());
        string mode = session.Get("mode").AsString();
        if (mode == "Object")
        {
            var selected = session.Get("selected").AsGodotArray<string>(); if (!additive) selected.Clear();
            var hidden = canvas.Get("preview_hidden").AsGodotDictionary();
            foreach (var item in lookup.Values)
            {
                string id = item.Get("id").AsString(); var mesh = item.Get("mesh").As<Resource>();
                if (item.Get("locked").AsBool() || hidden.ContainsKey(id) || !ModelDocumentOperations.Accessible(lookup, item, false) || mesh == null) continue;
                var data = new ModelMeshOperations.Snapshot(mesh); if (data.Vertices.Length == 0) continue;
                var bounds = new Aabb(data.Vertices[0], Vector3.Zero); foreach (var vertex in data.Vertices) bounds = bounds.Expand(vertex);
                Vector3 p = ModelDocumentOperations.WorldTransform(lookup, item) * bounds.GetCenter();
                if (rect.HasPoint(project(canvas, p)) && visible_point(canvas, p) && !selected.Contains(id)) selected.Add(id);
            }
        }
        else
        {
            var item = session.Call("primary").As<Resource>(); var mesh = item?.Get("mesh").As<Resource>(); if (mesh == null) return;
            var data = new ModelMeshOperations.Snapshot(mesh); Transform3D transform = ModelDocumentOperations.WorldTransform(lookup, item!);
            Vector3[] points = mode == "Vertex" ? data.Vertices : mode == "Edge" ? ModelGeometryOperations.Edges(data.Faces).Select(edge => (data.Vertices[edge.A] + data.Vertices[edge.B]) * .5f).ToArray() : Enumerable.Range(0, data.Faces.Length).Select(data.Center).ToArray();
            var elements = additive ? session.Get("elements").AsInt32Array().ToList() : new List<int>(); var selected = new HashSet<int>(elements);
            for (int i = 0; i < points.Length; i++) { Vector3 p = transform * points[i]; if (rect.HasPoint(project(canvas, p)) && visible_point(canvas, p) && selected.Add(i)) elements.Add(i); }
            session.Set("elements", elements.ToArray());
        }
        session.EmitSignal("changed");
    }
    public Settings geometry(Control canvas)
    {
        var session = canvas.Get("session").As<RefCounted>(); var item = session.Call("primary").As<Resource>();
        if (item == null || canvas.Get("sculpt").AsString().Length > 0) return new();
        var lookup = ModelDocumentOperations.Lookup(session.Get("document").As<Resource>()); if (!ModelDocumentOperations.Accessible(lookup, item, true)) return new();
        Transform3D transform = ModelDocumentOperations.WorldTransform(lookup, item); Vector3 pivot = transform * item.Get("pivot").AsVector3();
        var mesh = item.Get("mesh").As<Resource>();
        if (session.Get("mode").AsString() != "Object" && mesh != null)
        {
            int[] indices = session.Call("selected_vertices").AsInt32Array(); if (indices.Length == 0) return new();
            Vector3[] vertices = mesh.Get("vertices").AsVector3Array(); pivot = Vector3.Zero;
            foreach (int index in indices) pivot += transform * vertices[index] / indices.Length;
        }
        var camera = canvas.Get("camera").As<Camera3D>(); if (camera.IsPositionBehind(pivot)) return new();
        float depth = -(camera.Transform.AffineInverse() * pivot).Z;
        float length = camera.ProjectPosition(camera.UnprojectPosition(pivot) + new Vector2(85, 0), depth).DistanceTo(pivot);
        Basis basis = canvas.Get("local_axes").AsBool() ? transform.Basis.Orthonormalized() : Basis.Identity;
        var axes = new Godot.Collections.Array<Vector3> { basis.X, basis.Y, basis.Z }; var ends = new Vector2[3]; var rings = new Godot.Collections.Array<Vector2[]>();
        for (int i = 0; i < 3; i++)
        {
            ends[i] = project(canvas, pivot + axes[i] * length); var ring = new Vector2[65];
            for (int j = 0; j < ring.Length; j++) { float angle = Mathf.Tau * j / 64; ring[j] = project(canvas, pivot + (axes[(i + 1) % 3] * Mathf.Cos(angle) + axes[(i + 2) % 3] * Mathf.Sin(angle)) * length); }
            rings.Add(ring);
        }
        return new Settings { ["pivot"] = pivot, ["center"] = project(canvas, pivot), ["length"] = length, ["axes"] = axes, ["ends"] = ends, ["rings"] = rings };
    }
    public int handle_at(Control canvas, Vector2 point, Settings data)
    {
        if (data.Count == 0) return -2; bool rotate = canvas.Get("tool").AsString() == "Rotate"; Vector2 center = data["center"].AsVector2();
        if (!rotate && point.DistanceTo(center) < 9) return -1;
        float best = 9; int index = -2; var rings = data["rings"].AsGodotArray(); var ends = data["ends"].AsVector2Array();
        for (int i = 0; i < 3; i++)
        {
            if (rotate)
            {
                var ring = rings[i].AsVector2Array(); for (int j = 0; j < ring.Length - 1; j++) { float d = point.DistanceTo(Geometry2D.GetClosestPointToSegment(point, ring[j], ring[j + 1])); if (d < best) { best = d; index = i; } }
            }
            else
            {
                if (center.DistanceTo(ends[i]) < 15) continue; float d = point.DistanceTo(Geometry2D.GetClosestPointToSegment(point, center.Lerp(ends[i], .25f), ends[i])); if (d < best) { best = d; index = i; }
            }
        }
        return index;
    }
}
