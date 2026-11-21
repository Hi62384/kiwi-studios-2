using Godot;
using System;
using System.Linq;
using System.Collections.Generic;
using Settings = Godot.Collections.Dictionary;

public partial class ModelViewportTransforms : RefCounted
{
    private readonly ModelGeometryOperations _geometry = new();
    private readonly ModelMeshOperations _meshes = new();
    private static ModelViewportPicking Picking(Control canvas) => canvas.Get("_picking_native").As<ModelViewportPicking>();
    public Vector3 screen_plane(Control canvas, Vector2 point, Vector3 pivot, Vector3 normal)
    {
        var ray = Picking(canvas).ray(canvas, point); Vector3 direction = ray["direction"].AsVector3(), origin = ray["origin"].AsVector3();
        Vector3 n = normal == Vector3.Zero ? canvas.Get("camera").As<Camera3D>().Basis.Z : normal; float denominator = n.Dot(direction);
        return Mathf.Abs(denominator) < .000001f ? pivot : origin + direction * n.Dot(pivot - origin) / denominator;
    }
    public Settings snap_target(Control canvas, Vector2 point)
    {
        var session = canvas.Get("session").As<RefCounted>(); var picking = Picking(canvas); var hit = canvas.Call("pick", point, session.Get("selected")).AsGodotDictionary();
        if (hit.Count == 0) return hit; string kind = canvas.Get("snap_kind").AsString(); if (kind == "Surface") return hit;
        var lookup = ModelDocumentOperations.Lookup(session.Get("document").As<Resource>()); var item = lookup[hit["id"].AsString()]; Transform3D transform = ModelDocumentOperations.WorldTransform(lookup, item);
        if (kind == "Origin") { hit["point"] = transform.Origin; return hit; }
        var mesh = item.Get("mesh").As<Resource>(); if (mesh == null) return hit; var data = new ModelMeshOperations.Snapshot(mesh);
        float closest = float.PositiveInfinity; Vector3 best = hit["point"].AsVector3();
        void Consider(Vector3 p) { float distance = picking.project(canvas, p).DistanceTo(point); if (distance < closest) { closest = distance; best = p; } }
        if (kind == "Vertex") foreach (Vector3 vertex in data.Vertices) Consider(transform * vertex);
        else foreach (var edge in ModelGeometryOperations.Edges(data.Faces)) Consider(Geometry3D.GetClosestPointToSegment(hit["point"].AsVector3(), transform * data.Vertices[edge.A], transform * data.Vertices[edge.B]));
        hit["point"] = best; return hit;
    }
    public bool begin_transform(Control canvas, int index, Vector2 point, bool modal)
    {
        var session = canvas.Get("session").As<RefCounted>(); var document = session.Get("document").As<Resource>(); var lookup = ModelDocumentOperations.Lookup(document); string mode = session.Get("mode").AsString();
        if (mode == "Object") foreach (string id in session.Get("selected").AsGodotArray<string>())
            if (lookup.TryGetValue(id, out var item) && item.Get("binding").As<Resource>() != null) { canvas.EmitSignal("notice", "Move the armature or its parent to place a rig. Detach this mesh before changing its component rest transform."); return false; }
        var data = canvas.Call("geometry").AsGodotDictionary(); if (data.Count == 0) return false;
        int[] vertices = session.Call("selected_vertices").AsInt32Array(); canvas.Set("_selected_vertices", vertices); var chosen = canvas.Get("_selected_lookup").AsGodotDictionary(); chosen.Clear(); foreach (int vertex in vertices) chosen[vertex] = true; canvas.Set("_weights_radius", -1f);
        if (canvas.Get("proportional").AsBool() && mode != "Object" && (session.Call("primary").As<Resource>().Get("mesh").As<Resource>().Get("vertices").AsVector3Array().Length - vertices.Length) * (long)vertices.Length > 2000000)
        { canvas.EmitSignal("notice", "Proportional neighborhood is too large. Select fewer points or disable Proportional."); return false; }
        canvas.Set("_axis", index); canvas.Set("_pivot", data["pivot"]); var axes = canvas.Get("_axes").AsGodotArray<Vector3>(); axes.Clear(); foreach (Vector3 axis in data["axes"].AsGodotArray<Vector3>()) axes.Add(axis);
        canvas.Set("_start", point); canvas.Set("_source", document.Call("snapshot")); canvas.Set("_numeric", ""); canvas.Set("_plane", false); canvas.Set("_start_world", screen_plane(canvas, point, data["pivot"].AsVector3(), Vector3.Zero));
        session.Call("begin"); canvas.Set("_drag", true); canvas.Set("_modal", modal); canvas.GrabFocus(); return true;
    }
    public void finish_transform(Control canvas, bool cancel)
    {
        if (!canvas.Get("_drag").AsBool()) return; canvas.Set("_drag", false); canvas.Set("_modal", false); var session = canvas.Get("session").As<RefCounted>();
        if (cancel) session.Call("cancel"); else session.Call("commit", canvas.Get("tool").AsString() + " " + session.Get("mode").AsString().ToLowerInvariant());
        canvas.Set("_source", default(Variant)); canvas.Set("_numeric", ""); canvas.EmitSignal("gesture_finished");
    }
    public void update_transform(Control canvas, Vector2 point, bool ctrl)
    {
        if (!canvas.Get("_drag").AsBool()) return;
        var picking = Picking(canvas); var camera = canvas.Get("camera").As<Camera3D>(); var session = canvas.Get("session").As<RefCounted>();
        var source = canvas.Get("_source").As<Resource>(); var originalItems = ModelDocumentOperations.Lookup(source); var currentItems = ModelDocumentOperations.Lookup(session.Get("document").As<Resource>());
        int axis = canvas.Get("_axis").AsInt32(); var axes = canvas.Get("_axes").AsGodotArray<Vector3>(); Vector3 pivot = canvas.Get("_pivot").AsVector3(); Vector2 start = canvas.Get("_start").AsVector2(); string tool = canvas.Get("tool").AsString(), mode = session.Get("mode").AsString();
        Vector3 planeNormal = camera.Basis.Z;
        if (axis >= 0) { if (canvas.Get("_plane").AsBool()) planeNormal = axes[axis]; else { Vector3 normal = (camera.Position - pivot).Slide(axes[axis]); if (normal.Length() > .00001f) planeNormal = normal.Normalized(); } }
        Vector3 delta = screen_plane(canvas, point, pivot, planeNormal) - screen_plane(canvas, start, pivot, planeNormal);
        if (axis >= 0) delta = canvas.Get("_plane").AsBool() ? delta - axes[axis] * delta.Dot(axes[axis]) : axes[axis] * delta.Dot(axes[axis]);
        bool snapping = canvas.Get("snap").AsBool() != ctrl; if (snapping) delta = delta.Snapped(Vector3.One * canvas.Get("grid_step").AsSingle());
        Vector2 sourceScreen = picking.project(canvas, pivot); float angle = (start - sourceScreen).AngleTo(point - sourceScreen), factor = Mathf.Max(.01f, 1 + (point.X - start.X - point.Y + start.Y) / 140);
        if (axis >= 0)
        {
            var data = canvas.Call("geometry").AsGodotDictionary(); Vector2 projected = data.Count > 0 ? data["ends"].AsVector2Array()[axis] - data["center"].AsVector2() : Vector2.Zero;
            if (projected.LengthSquared() > 100) factor = Mathf.Max(.01f, 1 + (point - start).Dot(projected) / projected.LengthSquared());
            if (tool == "Rotate" && Mathf.Abs(camera.Basis.Z.Dot(axes[axis])) > .03f) { Vector3 a = screen_plane(canvas, start, pivot, axes[axis]) - pivot, b = screen_plane(canvas, point, pivot, axes[axis]) - pivot; if (a.Length() > .00001f && b.Length() > .00001f) angle = a.SignedAngleTo(b, axes[axis]); }
        }
        if (snapping) { angle = Mathf.Snapped(angle, Mathf.DegToRad(15)); factor = Mathf.Snapped(factor, .1f); }
        string numeric = canvas.Get("_numeric").AsString();
        if (float.TryParse(numeric, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out float number))
        { if (tool == "Move") delta = (axis >= 0 ? axes[axis] : camera.Basis.X) * number; else if (tool == "Rotate") angle = Mathf.DegToRad(number); else factor = number; }
        Basis rotation = new(axis >= 0 ? axes[axis] : camera.Basis.Z, angle), placementRotation = Basis.Identity;
        var primary = session.Call("primary").As<Resource>();
        if (tool == "Move" && snapping && canvas.Get("snap_kind").AsString() != "Grid")
        {
            var hit = snap_target(canvas, point);
            if (hit.Count > 0)
            {
                delta = hit["point"].AsVector3() - pivot;
                if (canvas.Get("snap_kind").AsString() == "Surface" && mode == "Object")
                {
                    var original = originalItems[primary.Get("id").AsString()]; Transform3D transform = ModelDocumentOperations.WorldTransform(originalItems, original); Vector3 normal = hit["normal"].AsVector3();
                    if (canvas.Get("align_surface").AsBool()) placementRotation = new Basis(new Quaternion(transform.Basis.Y.Normalized(), normal));
                    var mesh = original.Get("mesh").As<Resource>();
                    if (mesh != null)
                    {
                        var vertices = mesh.Get("vertices").AsVector3Array(); Aabb bounds = vertices.Length == 0 ? new Aabb() : new Aabb(vertices[0], Vector3.Zero); foreach (var vertex in vertices) bounds = bounds.Expand(vertex);
                        float support = float.PositiveInfinity; for (int i = 0; i < 8; i++) support = Mathf.Min(support, (placementRotation * (transform * bounds.GetEndpoint(i) - pivot)).Dot(normal)); delta -= normal * support;
                    }
                }
            }
        }
        if (mode == "Object")
        {
            var selected = session.Get("selected").AsGodotArray<string>();
            foreach (string id in selected)
            {
                if (!originalItems.TryGetValue(id, out var original) || !currentItems.TryGetValue(id, out var item) || !ModelDocumentOperations.Accessible(currentItems, item, true) || selected.Any(parent => ModelDocumentOperations.Descendant(originalItems, id, parent))) continue;
                Transform3D world = ModelDocumentOperations.WorldTransform(originalItems, original), parentTransform = originalItems.TryGetValue(original.Get("parent_id").AsString(), out var parent) ? ModelDocumentOperations.WorldTransform(originalItems, parent) : Transform3D.Identity;
                if (tool == "Move") world = new Transform3D(placementRotation * world.Basis, pivot + placementRotation * (world.Origin - pivot) + delta);
                else if (tool == "Rotate") world = new Transform3D(rotation * world.Basis, pivot + rotation * (world.Origin - pivot));
                else { Vector3 scale = Vector3.One * factor; if (axis >= 0) { scale = Vector3.One; scale[axis] = factor; } Basis basis = new(axes[0], axes[1], axes[2]), scaling = basis * Basis.FromScale(scale) * basis.Inverse(); world = new Transform3D(scaling * world.Basis, pivot + scaling * (world.Origin - pivot)); }
                item.Set("transform", parentTransform.AffineInverse() * world);
            }
        }
        else
        {
            var original = originalItems[primary.Get("id").AsString()]; Transform3D transform = ModelDocumentOperations.WorldTransform(originalItems, original), inverse = transform.AffineInverse(); var mesh = primary.Get("mesh").As<Resource>(); Vector3[] vertices = original.Get("mesh").As<Resource>().Get("vertices").AsVector3Array(); var result = new Vector3[vertices.Length];
            primary.Set("generator", ""); bool proportional = canvas.Get("proportional").AsBool(); float radius = canvas.Get("radius").AsSingle(); int[] chosen = canvas.Get("_selected_vertices").AsInt32Array(); var selected = new HashSet<int>(chosen); float[] weights = canvas.Get("_weights").AsFloat32Array();
            if (proportional && !Mathf.IsEqualApprox(canvas.Get("_weights_radius").AsSingle(), radius))
            {
                weights = new float[vertices.Length]; var chosenWorld = chosen.Select(index => transform * vertices[index]).ToArray();
                for (int i = 0; i < vertices.Length; i++) { if (selected.Contains(i)) { weights[i] = 1; continue; } float closest = float.PositiveInfinity; Vector3 p = transform * vertices[i]; foreach (var other in chosenWorld) closest = Mathf.Min(closest, p.DistanceTo(other)); weights[i] = Mathf.SmoothStep(radius, 0, closest); }
                canvas.Set("_weights", weights); canvas.Set("_weights_radius", radius);
            }
            for (int i = 0; i < vertices.Length; i++)
            {
                float weight = proportional ? weights[i] : selected.Contains(i) ? 1 : 0; if (weight <= 0) { result[i] = vertices[i]; continue; }
                Vector3 p = transform * vertices[i], moved = p + delta;
                if (tool == "Rotate") moved = pivot + rotation * (p - pivot);
                else if (tool == "Scale") { Vector3 offset = p - pivot; moved = pivot + (axis < 0 ? offset * factor : offset + axes[axis] * offset.Dot(axes[axis]) * (factor - 1)); }
                result[i] = inverse * p.Lerp(moved, weight);
            }
            mesh.Set("vertices", result);
        }
        session.EmitSignal("changed");
    }
    public bool begin_extrusion(Control canvas, Vector2 point)
    {
        var session = canvas.Get("session").As<RefCounted>(); var item = session.Call("primary").As<Resource>();
        if (session.Get("mode").AsString() != "Face" || item == null || item.Get("locked").AsBool()) return false;
        if (item.Get("skin_mesh").As<Mesh>() != null || item.Get("binding").As<Resource>() != null) { canvas.EmitSignal("notice", "Detach the mesh in Rigging before editing topology."); return false; }
        if (session.Get("elements").AsInt32Array().Length == 0) Picking(canvas).select_at(canvas, point, false);
        if (session.Get("elements").AsInt32Array().Length == 0) return false;
        canvas.Set("_start", point); canvas.Set("_source", session.Get("document").As<Resource>().Call("snapshot")); session.Call("begin"); canvas.Set("_extruding", true); canvas.Set("_extrude_amount", 0f); canvas.Set("_extrude_numeric", ""); return true;
    }
    public void update_extrusion(Control canvas, Vector2 point, bool ctrl)
    {
        var session = canvas.Get("session").As<RefCounted>(); var item = session.Call("primary").As<Resource>(); var lookup = ModelDocumentOperations.Lookup(canvas.Get("_source").As<Resource>()); var original = lookup[item.Get("id").AsString()]; Transform3D transform = ModelDocumentOperations.WorldTransform(lookup, original);
        var mesh = original.Get("mesh").As<Resource>(); var data = new ModelMeshOperations.Snapshot(mesh); int[] selected = session.Get("elements").AsInt32Array(); Vector3 localNormal = data.Normal(selected[0]), normal = (transform.Basis.Inverse().Transposed() * localNormal).Normalized(), center = transform * data.Center(selected[0]);
        Vector2 axis = Picking(canvas).project(canvas, center + normal) - Picking(canvas).project(canvas, center), pixels = point - canvas.Get("_start").AsVector2();
        float amount = axis.Length() > 12 ? pixels.Dot(axis) / axis.LengthSquared() : -pixels.Y * canvas.Get("distance").AsSingle() * .002f;
        amount /= Mathf.Max(.0001f, (transform.Basis * localNormal).Length()); if (canvas.Get("snap").AsBool() != ctrl) amount = Mathf.Snapped(amount, canvas.Get("grid_step").AsSingle());
        if (float.TryParse(canvas.Get("_extrude_numeric").AsString(), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out float number)) amount = number;
        canvas.Set("_extrude_amount", amount); item.Set("mesh", Mathf.Abs(amount) < .00001f ? _meshes.copy_mesh(mesh) : _geometry.extrude(mesh, selected, amount, false)["mesh"]); item.Set("generator", ""); session.EmitSignal("changed");
    }
    public void finish_extrusion(Control canvas, bool cancel)
    {
        if (!canvas.Get("_extruding").AsBool()) return; canvas.Set("_extruding", false); var session = canvas.Get("session").As<RefCounted>();
        if (cancel || Mathf.Abs(canvas.Get("_extrude_amount").AsSingle()) < .00001f) session.Call("cancel"); else session.Call("commit", "Push/pull faces");
        canvas.Set("_source", default(Variant)); canvas.EmitSignal("gesture_finished");
    }
    public void sculpt_at(Control canvas, Vector2 point, Vector2 previous, bool erase)
    {
        var session = canvas.Get("session").As<RefCounted>(); var item = session.Call("primary").As<Resource>(); var hit = canvas.Call("pick", point, new Godot.Collections.Array<string>()).AsGodotDictionary(); var mesh = item?.Get("mesh").As<Resource>();
        if (item == null || mesh == null || item.Get("locked").AsBool() || item.Get("skin_mesh").As<Mesh>() != null || item.Get("binding").As<Resource>() != null || !hit.TryGetValue("id", out var id) || id.AsString() != item.Get("id").AsString()) return;
        var lookup = ModelDocumentOperations.Lookup(session.Get("document").As<Resource>()); Transform3D transform = ModelDocumentOperations.WorldTransform(lookup, item), inverse = transform.AffineInverse(); Vector3 center = hit["point"].AsVector3(), normal = hit["normal"].AsVector3(); string sculpt = canvas.Get("sculpt").AsString(); float strength = canvas.Get("strength").AsSingle(), radius = canvas.Get("radius").AsSingle();
        Vector3[] vertices = mesh.Get("vertices").AsVector3Array(), relaxed = sculpt == "Smooth" ? _geometry.smooth_mesh(mesh, strength, 1).Get("vertices").AsVector3Array() : Array.Empty<Vector3>(); Vector3 delta = screen_plane(canvas, point, center, Vector3.Zero) - screen_plane(canvas, previous, center, Vector3.Zero);
        for (int i = 0; i < vertices.Length; i++)
        {
            Vector3 p = transform * vertices[i]; float weight = Mathf.SmoothStep(radius, 0, p.DistanceTo(center)) * strength; if (weight <= 0) continue;
            switch (sculpt) { case "Grab": p += delta * weight * 3; break; case "Inflate": p += normal * weight * .05f * (erase ? -1 : 1); break; case "Smooth": p = p.Lerp(transform * relaxed[i], weight); break; case "Flatten": p -= normal * (p - center).Dot(normal) * weight; break; case "Pinch": p = p.Lerp(center, weight * .15f); break; }
            vertices[i] = inverse * p;
        }
        mesh.Set("vertices", vertices); item.Set("mesh", mesh); item.Set("generator", ""); session.EmitSignal("changed");
    }
}
