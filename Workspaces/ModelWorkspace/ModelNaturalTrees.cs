using Godot;
using System;
using System.Linq;
using Settings = Godot.Collections.Dictionary;
using Geometry = ModelNaturalGeometry;

public partial class ModelNaturalGenerator
{
    private static void Branch(Build build, Settings p, string id, string parent, Vector3 origin, Vector3 direction, float length, float radius, int level, string name)
    {
        // GDScript hash() exposes the unsigned 32-bit hash as a positive int64.
        // Sign-extending the C# int changes the random stream for half the IDs.
        if (build.Stop()) return; using var rng = new RandomNumberGenerator { Seed = unchecked((uint)GD.Hash(new Godot.Collections.Array { p["seed"], id })) };
        var overrides = p.TryGetValue("branch_overrides", out var all) ? all.AsGodotDictionary() : new Settings(); var local = overrides.TryGetValue(id, out var found) ? found.AsGodotDictionary() : new Settings(); if (local.TryGetValue("pruned", out var pruned) && pruned.AsBool()) return;
        direction = Basis.FromEuler((local.TryGetValue("rotation", out var r) ? r.AsVector3() : Vector3.Zero) * Mathf.Pi / 180) * direction; length *= Mathf.Clamp(F(local, "length", 1), .05f, 3); radius *= Mathf.Clamp(F(local, "radius", 1), .1f, 2);
        var junction = Geometry.Junction(build.Mesh, build.Graph, parent, origin, direction, length); if (junction.Count > 0) origin = junction["point"].AsVector3() + direction * radius * .3f;
        var path = new Vector3[9]; var radii = new float[9]; Vector3 sideways = direction.Cross(Vector3.Up).Normalized();
        for (int i = 0; i <= 8; i++) { float t = i / 8f, bend = F(p, "curve") * length * Mathf.Sin(t * Mathf.Pi * .5f); path[i] = origin + direction * length * t + sideways * bend + Vector3.Up * (length * .22f * Mathf.Sin(t * Mathf.Pi) - F(p, "droop") * length * t * t); radii[i] = Mathf.Max(.001f, radius * (1 - F(p, "taper") * t)); }
        var topology = Geometry.Tube(build.Mesh, path, radii, I(p, "segments")); Geometry.Stitch(build.Mesh, junction, topology, (path[1] - path[0]).Normalized());
        build.Graph.Add(new Settings { ["id"] = id, ["parent"] = parent, ["points"] = path, ["radii"] = radii, ["level"] = level, ["topology"] = topology, ["joined"] = junction.Count > 0 });
        if (level < I(p, "levels"))
        {
            int count = Math.Max(2, I(p, "branches") / (int)Math.Pow(2, level + 1));
            for (int j = 0; j < count; j++) { if (build.Stop()) return; int index = Mathf.Clamp(3 + (int)((float)j / count * 5), 1, 7); float angle = Mathf.Tau * j / count + rng.RandfRange(-.3f, .3f); Vector3 d = (direction * .35f + new Vector3(Mathf.Cos(angle), .4f, Mathf.Sin(angle)) * F(p, "angle")).Normalized(); Branch(build, p, id + "/" + j, id, path[index], d, length * .58f, radius * .4f, level + 1, name); }
        }
        else if (F(p, "foliage") > 0)
        {
            bool conifer = Conifer(name); int count = Math.Max(1, (int)((conifer ? 72 : 36) * F(p, "foliage")));
            for (int j = 0; j < count; j++) { if (build.Stop()) return; int index = Mathf.Clamp(2 + j % 7, 1, 8); float a = j * 2.39996f; Vector3 d = new Vector3(Mathf.Cos(a), rng.RandfRange(-.15f, .55f), Mathf.Sin(a)).Normalized(); float size = F(p, "leaf_size") * rng.RandfRange(.75f, 1.25f) * (conifer ? .8f : 1); Geometry.Leaf(build.Mesh, path[index], d, size, conifer ? .09f : name == "Willow" ? .12f : .45f, 1, name == "Maple" ? 1 : name == "Oak" ? 2 : name == "Birch" ? 3 : 0); build.Leaves.Add(new Settings { ["branch"] = id, ["t"] = index / 8f, ["position"] = path[index] }); }
        }
    }
    private static void Tree(Build build, string name, Settings p, RandomNumberGenerator rng)
    {
        float height = F(p, "height"), radius = F(p, "radius"); var path = new Vector3[17]; var radii = new float[17]; bool fallen = name == "Log" || name == "Driftwood" || name == "Root", stump = name == "Stump"; if (stump) height *= .2f;
        for (int i = 0; i < 17; i++)
        {
            double t = i / 16.0, phase = p["seed"].AsDouble() * .713, preciseRadius = p["radius"].AsDouble(), curve = p["curve"].AsDouble();
            Vector3 lean = new((float)(p["lean"].AsDouble() * height * t * t), 0, (float)(Math.Sin(t * 3) * curve * height * .15 + (Math.Sin(t * 6 + phase) - Math.Sin(phase)) * height * .03 * p["irregularity"].AsDouble()));
            path[i] = !fallen ? new Vector3(0, (float)(height * t), 0) + lean : new Vector3((float)(height * t), (float)(preciseRadius + (Math.Sin(t * 3 + phase) - Math.Sin(phase)) * preciseRadius * .12), (float)((Math.Sin(t * 4 + phase) - Math.Sin(phase)) * height * curve * .4)); radii[i] = (float)(preciseRadius * (1 - p["taper"].AsDouble() * t) * (1 + .7 * Math.Pow(1 - t, 8)));
        }
        var topology = Geometry.Tube(build.Mesh, path, radii, I(p, "segments")); build.Graph.Add(new Settings { ["id"] = "trunk", ["parent"] = "", ["points"] = path, ["radii"] = radii, ["level"] = 0, ["topology"] = topology }); if (fallen || stump) return;
        for (int root = 0; root < I(p, "roots"); root++)
        {
            float angle = Mathf.Tau * root / Math.Max(1, I(p, "roots")); Vector3 d = new(Mathf.Cos(angle), 0, Mathf.Sin(angle)); float reach = radius * (name == "Mangrove" ? 6 : 3); var points = new[] { path[1], d * reach * .45f + Vector3.Up * radius * .3f, d * reach + Vector3.Down * radius * .5f }; Vector3 direction = (points[1] - points[0]).Normalized(); var junction = Geometry.Junction(build.Mesh, build.Graph, "trunk", points[0], direction, reach); if (junction.Count > 0) points[0] = junction["point"].AsVector3() + direction * radius * .1f;
            var rootTopology = Geometry.Tube(build.Mesh, points, new[] { radius * .8f, radius * .35f, .005f }, I(p, "segments")); Geometry.Stitch(build.Mesh, junction, rootTopology, (points[1] - points[0]).Normalized());
        }
        for (int j = 0; j < I(p, "branches"); j++)
        {
            if (build.Stop()) return; bool conifer = Conifer(name), palm = name == "Palm", acacia = name == "Acacia";
            float t = conifer ? .2f + .7f * (j / 3) / Math.Max(1, Mathf.CeilToInt(I(p, "branches") / 3f) - 1) : rng.RandfRange(.4f, .88f); if (palm) t = .95f; if (acacia) t = .7f + rng.Randf() * .15f;
            int index = Mathf.Clamp(Mathf.RoundToInt(t * 16), 1, 16); float angle = j * 2.39996f + rng.RandfRange(-.2f, .2f); Vector3 direction = new Vector3(Mathf.Cos(angle) * F(p, "angle"), palm || acacia ? .1f : .6f, Mathf.Sin(angle) * F(p, "angle")).Normalized(); float length = height * F(p, "length") * (conifer ? (1 - t) * 1.5f : rng.RandfRange(.65f, 1));
            var q = p.Duplicate(); q["levels"] = palm ? 0 : I(p, "levels"); if (palm) { q["droop"] = .5f; q["foliage"] = 0f; } if (acacia) { q["droop"] = 0f; q["curve"] = .1f; }
            Branch(build, q, "b" + j, "trunk", path[index], direction, length, radius * .32f, 0, name);
            if (palm && build.Graph[^1]["id"].AsString() == "b" + j)
            {
                var frond = build.Graph[^1]; var points = frond["points"].AsVector3Array(); for (int k = 1; k < 8; k++) { Vector3 tangent = (points[k + 1] - points[k - 1]).Normalized(), side = tangent.Cross(Vector3.Up).Normalized(); foreach (float sign in new[] { -1f, 1f }) { Geometry.Leaf(build.Mesh, points[k], side * sign + tangent * .4f + Vector3.Down * .2f, length * .3f * Mathf.Sin(Mathf.Pi * k / 9), .07f); build.Leaves.Add(new Settings { ["branch"] = frond["id"], ["t"] = k / 8f, ["position"] = points[k] }); } }
            }
        }
    }
}
