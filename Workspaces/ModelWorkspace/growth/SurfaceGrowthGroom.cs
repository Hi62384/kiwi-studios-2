using Godot;
using System;
using System.Collections.Generic;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

public partial class SurfaceGrowthGeometry
{
    public void build_grid(GodotObject data)
    {
        var grid = Dict(data, "candidate_grid"); if (grid.Count > 0) return;
        var roots = data.Get("roots").AsGodotArray(); float size = data.Get("grid_size").AsSingle();
        for (int i = 0; i < roots.Count; i++)
        {
            var cell = (Vector3I)(roots[i].AsGodotDictionary()["position"].AsVector3() / size).Floor();
            if (!grid.ContainsKey(cell)) grid[cell] = new GArray(); grid[cell].AsGodotArray().Add(i);
        }
    }
    public Godot.Collections.Array<int> query(GodotObject data, Vector3 center, double localRadius)
    {
        build_grid(data); var result = new Godot.Collections.Array<int>(); var roots = data.Get("roots").AsGodotArray(); double radiusSquared = localRadius * localRadius;
        float size = data.Get("grid_size").AsSingle(); int extent = (int)Math.Ceiling(localRadius / size); var cell = (Vector3I)(center / size).Floor();
        if (extent > 12)
        {
            for (int i = 0; i < roots.Count; i++) if (roots[i].AsGodotDictionary()["position"].AsVector3().DistanceSquaredTo(center) <= radiusSquared) result.Add(i);
            return result;
        }
        var grid = Dict(data, "candidate_grid");
        for (int x = -extent; x <= extent; x++) for (int y = -extent; y <= extent; y++) for (int z = -extent; z <= extent; z++)
        {
            if (!grid.TryGetValue(cell + new Vector3I(x, y, z), out var values)) continue;
            foreach (var value in values.AsGodotArray()) { int i = value.AsInt32(); if (roots[i].AsGodotDictionary()["position"].AsVector3().DistanceSquaredTo(center) <= radiusSquared) result.Add(i); }
        }
        return result;
    }
    public int apply_at(GodotObject tool, GodotObject data, Vector3 center, Vector3 movement, Vector3 normal, bool invert)
    {
        ulong started = Time.GetTicksUsec(); float radius = tool.Get("radius").AsSingle(); var indices = query(data, center, radius); int count = 0;
        _settings.prepare_regions(data); Vector3[] source = data.Get("source_points").AsVector3Array(); var roots = data.Get("roots").AsGodotArray();
        string kind = tool.Get("tool").AsString(); var settings = Dict(data, "settings");
        Vector3 averageDirection = Vector3.Zero, averageOffset = Vector3.Zero; double averageLength = 0, averageDensity = 0;
        if (kind == "Smooth" && indices.Count > 0)
        {
            foreach (int index in indices)
            {
                var root = roots[index].AsGodotDictionary(); var edit = Style(data, root, ResolvedSettings(data, root)); var frame = point_frame(data, root, source);
                averageDirection += frame.Basis * Get(edit, "direction", Vector3.Up).AsVector3(); averageOffset += frame.Basis * Get(edit, "offset", Vector3.Zero).AsVector3(); averageLength += edit["length"].AsDouble(); averageDensity += edit["density"].AsDouble();
            }
            averageDirection = averageDirection.Normalized(); averageOffset /= indices.Count; averageLength /= indices.Count; averageDensity /= indices.Count;
        }
        bool through = tool.Get("through").AsBool(), replace = tool.Get("replace").AsBool(), targetCut = tool.Get("target_cut").AsBool();
        float strength = tool.Get("strength").AsSingle(), falloff = tool.Get("falloff").AsSingle(), value = tool.Get("value").AsSingle(), frequency = tool.Get("frequency").AsSingle(), sign = invert ? -1 : 1;
        var metric = tool.Get("distance_metric").AsBasis(); var protectedFaces = new HashSet<int>(data.Get("protected_faces").AsInt32Array());
        var canvas = tool.Get("canvas").As<Control>(); var triangles = tool.Get("triangle_mesh").As<TriangleMesh>(); var hit = Dict(tool, "last_hit");
        Vector3[]? posed = null; Vector3 origin = Vector3.Zero;
        if (!through && canvas != null && triangles != null && hit.Count > 0)
        { posed = hit["points"].AsVector3Array(); origin = hit["transform"].AsTransform3D().AffineInverse() * canvas.Get("camera").As<Camera3D>().GlobalPosition; }
        var pending = Dict(data, "pending"); var dirty = Dict(data, "dirty_chunks");
        foreach (int index in indices)
        {
            var root = roots[index].AsGodotDictionary();
            if (protectedFaces.Contains(root["face"].AsInt32()) && kind != "Protect") continue;
            if (!through && root["normal"].AsVector3().Dot(normal) < .1f) continue;
            if (posed != null)
            {
                Vector3 point = point_frame(data, root, posed).Origin; var visible = triangles!.IntersectRay(origin, (point - origin).Normalized());
                if (visible.Count > 0 && origin.DistanceTo(visible["position"].AsVector3()) + Math.Max(.0001f, radius * .01f) < origin.DistanceTo(point)) continue;
            }
            Vector3 position = root["position"].AsVector3(); float distance = (metric * (position - center)).Length() / Math.Max(.0001f, radius);
            float weight = strength * Mathf.Pow(Math.Clamp(1 - distance, 0, 1), Mathf.Lerp(.05f, 4, falloff)); if (weight < .0001f) continue;
            string id = root["id"].AsInt64().ToString(System.Globalization.CultureInfo.InvariantCulture); var edit = Style(data, root, ResolvedSettings(data, root)); var frame = point_frame(data, root, source); Basis inverse = frame.Basis.Inverse();
            Vector3 delta = inverse * movement, offset = Get(edit, "offset", Vector3.Zero).AsVector3(), direction = Get(edit, "direction", Vector3.Up).AsVector3();
            float length = edit["length"].AsSingle(), density = edit["density"].AsSingle(); var change = new Settings();
            switch (kind)
            {
                case "Color paint": change["color"] = Get(edit, "color", Colors.White).AsColor().Lerp(invert ? Colors.White : tool.Get("paint_color").AsColor(), weight); break;
                case "Brush": change["offset"] = offset + delta * weight * sign; break;
                case "Comb": if (delta.LengthSquared() > .0000001f) change["direction"] = direction.Slerp(delta.Normalized(), Math.Clamp(weight, 0, 1)).Normalized(); break;
                case "Cut": change["length"] = Math.Max(0, targetCut ? Mathf.Lerp(length, Math.Min(length, value), weight) : length - weight * Math.Max(.01f, value) * sign); break;
                case "Grow": change["length"] = Math.Max(0, length + weight * Math.Max(.01f, value) * sign); break;
                case "Length": change["length"] = Math.Max(0, replace ? Mathf.Lerp(length, value, weight) : length + value * weight * sign); break;
                case "Curl":
                    if (Get(settings, "type", 0).AsInt32() == 2) change["offset"] = offset + new Vector3(0, 0, value * weight * sign);
                    else { change["curl"] = Math.Clamp(Get(edit, "curl", 0).AsSingle() + weight * sign, -4, 4); change["frequency"] = frequency; } break;
                case "Clump":
                    float gridSize = Math.Max(.02f, value); Vector3 clumpCenter = position.Snapped(Vector3.One * gridSize);
                    change["clump"] = Math.Clamp(Get(edit, "clump", 0).AsSingle() + weight * sign, 0, 1); change["clump_target"] = inverse * (clumpCenter - position) + Vector3.Up * length; change["clump_id"] = ((Vector3I)(clumpCenter / gridSize)).ToString();
                    change["clump_start"] = tool.Get("clump_start"); change["clump_end"] = tool.Get("clump_end"); change["clump_variation"] = tool.Get("clump_variation"); break;
                case "Density": change["density"] = Math.Clamp(replace ? Mathf.Lerp(density, value, weight) : density + weight * sign, 0, 1); break;
                case "Smooth": change["offset"] = offset.Lerp(inverse * averageOffset, weight); change["direction"] = direction.Lerp(inverse * averageDirection, weight).Normalized(); change["length"] = Mathf.Lerp(length, (float)averageLength, weight); change["density"] = Mathf.Lerp(density, (float)averageDensity, weight); break;
                case "Relax": change["offset"] = offset.Lerp(Vector3.Zero, weight); change["curl"] = Mathf.Lerp(Get(edit, "curl", 0).AsSingle(), 0, weight); change["direction"] = direction.Lerp(Vector3.Up, weight).Normalized(); break;
                case "Part": Vector3 axis = movement.Normalized(), away = position - center; away -= axis * away.Dot(axis); change["direction"] = Vector3.Up.Lerp(inverse * away.Normalized(), Math.Clamp(weight * 2, 0, 1)).Normalized(); break;
                case "Feather width": change["width"] = Math.Max(.001f, Get(edit, "width", Get(settings, "width", .14)).AsSingle() + weight * value * sign); break;
                case "Spread": change["offset"] = offset + inverse * (position - center) * weight * sign; break;
                case "Protect": change["locked"] = !invert; break;
                case "Reset region": change = new Settings { ["offset"] = Vector3.Zero, ["direction"] = Vector3.Up, ["curl"] = 0.0, ["clump"] = 0.0, ["length"] = Get(settings, "length", .5), ["density"] = 1.0 / Get(settings, "candidate_multiplier", 2).AsDouble() }; break;
            }
            if (Get(edit, "locked", false).AsBool() && kind != "Protect") continue;
            if (!pending.ContainsKey(id)) pending[id] = new Settings(); pending[id].AsGodotDictionary().Merge(change, true); dirty[index / 128] = true; count++;
        }
        data.Set("revision", data.Get("revision").AsInt64() + 1); data.Set("groom_usec", Time.GetTicksUsec() - started); tool.Set("touched", tool.Get("touched").AsInt64() + count); return count;
    }
}
