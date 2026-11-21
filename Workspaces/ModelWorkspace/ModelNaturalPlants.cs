using Godot;
using System;
using System.Linq;
using System.Collections.Generic;
using Settings = Godot.Collections.Dictionary;
using Topology = ModelGeometryOperations.Topology;
using Geometry = ModelNaturalGeometry;

public partial class ModelNaturalGenerator
{
    private static void Plant(Build build, string name, Settings p, RandomNumberGenerator rng)
    {
        if (name == "Cactus") { Cactus(build, p); return; }
        if (name == "Vine" && p.TryGetValue("growth_path", out var growthPath) && growthPath.AsVector3Array().Length >= 2) { Vine(build, p); return; }
        if (name == "Bush") { var q = p.Duplicate(); q["height"] = F(p, "height") * .8f; q["radius"] = F(p, "radius") * .12f; q["levels"] = 1; q["leaf_size"] = F(p, "height") * .15f; q["branches"] = 12; Tree(build, "Oak", q, rng); return; }
        for (int j = 0; j < I(p, "branches"); j++)
        {
            if (build.Stop()) return; float angle = j * 2.39996f; Vector3 d = new(Mathf.Cos(angle), 0, Mathf.Sin(angle)), origin = d * rng.Randf() * F(p, "radius") * .4f; float h = F(p, "height") * rng.RandfRange(.6f, 1);
            var path = new[] { origin, origin + Vector3.Up * h * .5f + d * h * .1f, origin + Vector3.Up * h + d * h * .25f }; var radii = new[] { h * .015f, h * .009f, .001f };
            if (name == "Grass") { Geometry.Blade(build.Mesh, origin, d, h, F(p, "curve")); continue; } if (name == "Succulent") { Geometry.Leaf(build.Mesh, origin, Vector3.Up + d * .4f, h, .17f); continue; }
            if (name == "Vine") { path = new[] { origin, origin + Vector3.Up * h * .3f + d * h * .2f, origin + Vector3.Up * h * .7f - d * h * .2f, origin + Vector3.Up * h }; radii = new[] { h * .012f, h * .01f, h * .008f, .002f }; }
            Geometry.Tube(build.Mesh, path, radii, 6);
            if (name == "Mushroom")
            {
                var q = p.Duplicate(); q["radius"] = h * .35f; q["height"] = h * .25f; var cap = new Topology(); Rock(build, cap, "Mushroom", q, rng); int offset = build.Mesh.Points.Count;
                foreach (Vector3 point in cap.Points) build.Mesh.Points.Add(point + path[^1]); foreach (int[] face in cap.Faces) build.Mesh.AddFace(face.Select(v => v + offset).ToArray(), null, 1);
            }
            else if (name == "Flower") for (int petal = 0; petal < 7; petal++) Geometry.Leaf(build.Mesh, path[^1], new Vector3(Mathf.Cos(Mathf.Tau * petal / 7), .1f, Mathf.Sin(Mathf.Tau * petal / 7)), h * .23f, .6f, 2);
            else if (name != "Reed") for (int k = 0; k < 12; k++) { float t = (k + 1) / 13f; Vector3 center = path[0].Lerp(path[^1], t); float width = Mathf.Sin(t * Mathf.Pi) * h * .3f; foreach (float sign in new[] { -1f, 1f }) Geometry.Leaf(build.Mesh, center, d * sign + Vector3.Up * .2f, width, name == "Fern" ? .13f : .4f); }
        }
    }
    private static void Cactus(Build build, Settings p)
    {
        float h = F(p, "height"), r = F(p, "radius") * .35f; var path = new Vector3[13]; var radii = new float[13]; for (int i = 0; i < 13; i++) { path[i] = Vector3.Up * h * i / 12; radii[i] = Mathf.Max(.002f, r * Mathf.Sqrt(Mathf.Max(.001f, 1 - Mathf.Pow(i / 12f, 8)))); }
        var topology = Geometry.Tube(build.Mesh, path, radii, 12); build.Graph.Add(new Settings { ["id"] = "trunk", ["parent"] = "", ["points"] = path, ["radii"] = radii, ["level"] = 0, ["topology"] = topology });
        for (int index = 0; index < Math.Min(5, I(p, "branches")); index++)
        {
            if (build.Stop()) return; float a = index * 2.39996f + F(p, "seed") * .713f; Vector3 d = new(Mathf.Cos(a), 0, Mathf.Sin(a)), origin = path[3 + index % 6]; var junction = Geometry.Junction(build.Mesh, build.Graph, "trunk", origin, d, r * 4); if (junction.Count > 0) origin = junction["point"].AsVector3() + d * r * .1f;
            var arm = new[] { origin, origin + d * h * .2f, origin + d * h * .3f + Vector3.Up * h * .1f, origin + d * h * .3f + Vector3.Up * h * .4f }; var tube = Geometry.Tube(build.Mesh, arm, new[] { r * .65f, r * .65f, r * .55f, .002f }, 10); Geometry.Stitch(build.Mesh, junction, tube, (arm[1] - arm[0]).Normalized());
        }
        for (int ring = 0; ring < 13; ring++) for (int index = 0; index < 12; index++) { int at = ring * 12 + index; Vector3 point = build.Mesh.Points[at]; float scale = 1 + .12f * Mathf.Cos(Mathf.Tau * index / 12 * 6); point.X *= scale; point.Z *= scale; build.Mesh.Points[at] = point; }
    }
    private static void Rock(Build build, Topology mesh, string name, Settings p, RandomNumberGenerator rng)
    {
        int sides = I(p, "detail"), rings = Math.Max(4, sides / 2); using var noise = new FastNoiseLite { Seed = I(p, "seed"), Frequency = 2.3f }; float h = F(p, "height"), radius = F(p, "radius"), phase = rng.Randf() * Mathf.Tau;
        mesh.Points.Add(new Vector3(0, h, 0));
        for (int i = 1; i < rings; i++)
        {
            if (build.Stop()) return; float phi = Mathf.Pi * i / rings;
            for (int j = 0; j < sides; j++)
            {
                float a = Mathf.Tau * j / sides; Vector3 direction = new(Mathf.Sin(phi) * Mathf.Cos(a), Mathf.Cos(phi), Mathf.Sin(phi) * Mathf.Sin(a)); float n = noise.GetNoise3Dv(direction * 2), r = 1 + n * F(p, "irregularity"); Vector3 point = direction * new Vector3(radius, h, radius) * r;
                if (name == "Sandstone" || name == "Slate" || name == "Limestone") { float frequency = name == "Limestone" ? 7 : name == "Slate" ? 16 : 12; point.X += Mathf.Sin(point.Y * frequency + phase) * radius * .12f; point.Z += Mathf.Sin(point.Y * (frequency - .7f)) * radius * .1f; }
                if (name == "Slate") point.Y *= .23f; if (name == "Basalt") { point.Y *= 1.6f; point.X = Mathf.Snapped(point.X, radius * .15f); point.Z = Mathf.Snapped(point.Z, radius * .15f); } if (name == "River stone") point.Y *= .55f; if (name == "Volcanic") point *= 1 + Mathf.Abs(n) * .7f; if (name == "Mushroom") point.Y = Mathf.Max(-h * .12f, point.Y);
                if (name == "Stalactite" || name == "Stalagmite") { float t = 1 - (float)i / rings; point = new Vector3(Mathf.Cos(a) * radius * (1 - t) * r, h * t, Mathf.Sin(a) * radius * (1 - t) * r); } mesh.Points.Add(point);
            }
        }
        int bottom = mesh.Points.Count; mesh.Points.Add(name == "Stalactite" || name == "Stalagmite" ? Vector3.Zero : new Vector3(0, name == "Mushroom" ? -h * .12f : -h, 0));
        for (int j = 0; j < sides; j++) { mesh.AddFace(new[] { 0, 1 + j, 1 + (j + 1) % sides }); for (int i = 0; i < rings - 2; i++) { int a = 1 + i * sides + j, b = 1 + i * sides + (j + 1) % sides; mesh.AddFace(new[] { a, a + sides, b + sides, b }); } mesh.AddFace(new[] { bottom, 1 + (rings - 2) * sides + (j + 1) % sides, 1 + (rings - 2) * sides + j }); }
    }
    private static void Vine(Build build, Settings p)
    {
        Vector3[] path = p["growth_path"].AsVector3Array(); var source = p.TryGetValue("growth_surface", out var surface) ? surface.As<Resource>() : null;
        if (path.Length > 256 || (source != null && source.Get("faces").AsGodotArray().Count > 50000)) { p["_error"] = "Vine attachment budget exceeded. Use up to 256 path points and a simpler surface model."; return; }
        var triangles = new List<(Vector3 A, Vector3 B, Vector3 C)>();
        if (source != null) { var data = new ModelMeshOperations.Snapshot(source); for (int f = 0; f < data.Faces.Length; f++) { int[] indices = data.Triangles(f), face = data.Faces[f]; for (int i = 0; i < indices.Length; i += 3) triangles.Add((data.Vertices[face[indices[i]]], data.Vertices[face[indices[i + 1]]], data.Vertices[face[indices[i + 2]]])); } }
        for (int index = 0; index < path.Length; index++)
        {
            if (build.Stop()) return; float nearest = float.PositiveInfinity; Vector3 hit = path[index]; foreach (var triangle in triangles) { Vector3 point = Geometry.TrianglePoint(path[index], triangle.A, triangle.B, triangle.C); float distance = point.DistanceSquaredTo(path[index]); if (distance < nearest) { nearest = distance; hit = point + (triangle.C - triangle.A).Cross(triangle.B - triangle.A).Normalized() * .015f; } } path[index] = hit;
        }
        var clean = new List<Vector3>(); foreach (var point in path) if (clean.Count == 0 || clean[^1].DistanceSquaredTo(point) > .000001f) clean.Add(point); path = clean.ToArray(); if (path.Length < 2) { p["_error"] = "The vine needs two different attachment points."; return; }
        var radii = Enumerable.Repeat(F(p, "radius") * .04f, path.Length).ToArray(); var topology = Geometry.Tube(build.Mesh, path, radii, 6); build.Graph.Add(new Settings { ["id"] = "vine", ["parent"] = "", ["points"] = path, ["radii"] = radii, ["level"] = 0, ["topology"] = topology });
        for (int segment = 0; segment < path.Length - 1; segment++) for (int index = 0; index < I(p, "branches"); index++)
        {
            if (build.Stop()) return; float t = (index + .5f) / I(p, "branches"); Vector3 point = path[segment].Lerp(path[segment + 1], t), tangent = (path[segment + 1] - path[segment]).Normalized(), side = tangent.Cross(Mathf.Abs(tangent.Z) < .9f ? Vector3.Forward : Vector3.Up).Normalized(); Geometry.Leaf(build.Mesh, point, side * (index % 2 != 0 ? -1 : 1) + tangent * .2f, F(p, "leaf_size"), .45f); build.Leaves.Add(new Settings { ["branch"] = "vine", ["t"] = segment + t, ["position"] = point });
        }
    }
}
