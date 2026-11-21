using Godot;
using System;
using System.Linq;
using System.Collections.Generic;
using Settings = Godot.Collections.Dictionary;
using Topology = ModelGeometryOperations.Topology;

internal static class ModelNaturalGeometry
{
    internal static Settings Tube(Topology mesh, Vector3[] points, float[] radii, int sides, int slot = 0)
    {
        if (points.Length < 2) return new(); int start = mesh.Points.Count, firstFace = mesh.Faces.Count; float distance = 0; Vector3 previousU = Vector3.Zero;
        for (int i = 0; i < points.Length; i++)
        {
            Vector3 tangent = (points[Math.Min(i + 1, points.Length - 1)] - points[Math.Max(0, i - 1)]).Normalized(), u = previousU != Vector3.Zero ? (previousU - tangent * previousU.Dot(tangent)).Normalized() : tangent.Cross(Mathf.Abs(tangent.Z) < .9f ? Vector3.Forward : Vector3.Right).Normalized(), v = tangent.Cross(u); previousU = u;
            float previousDistance = distance; if (i > 0) distance += points[i].DistanceTo(points[i - 1]);
            for (int j = 0; j < sides; j++) mesh.Points.Add(points[i] + (u * (float)Math.Cos(Math.Tau * j / sides) + v * (float)Math.Sin(Math.Tau * j / sides)) * radii[i]);
            if (i == 0) continue;
            for (int j = 0; j < sides; j++)
            {
                int a = start + (i - 1) * sides + j, b = start + (i - 1) * sides + (j + 1) % sides, c = start + i * sides + (j + 1) % sides, d = start + i * sides + j;
                mesh.AddFace(new[] { a, c, b }, new[] { new Vector2((float)j / sides, previousDistance), new Vector2((float)(j + 1) / sides, distance), new Vector2((float)(j + 1) / sides, previousDistance) }, slot);
                mesh.AddFace(new[] { a, d, c }, new[] { new Vector2((float)j / sides, previousDistance), new Vector2((float)j / sides, distance), new Vector2((float)(j + 1) / sides, distance) }, slot);
            }
        }
        int cap = mesh.AddFace(Enumerable.Range(start, sides).ToArray(), null, slot); mesh.AddFace(Enumerable.Range(start + (points.Length - 1) * sides, sides).Reverse().ToArray(), null, slot);
        return new Settings { ["start"] = start, ["face_start"] = firstFace, ["face_end"] = mesh.Faces.Count, ["cap"] = cap, ["sides"] = sides };
    }
    private static Vector3 Center(Topology mesh, int face) { Vector3 center = Vector3.Zero; foreach (int index in mesh.Faces[face]) center += mesh.Points[index]; return center / Math.Max(1, mesh.Faces[face].Length); }
    internal static Settings Junction(Topology mesh, Godot.Collections.Array<Settings> graph, string parent, Vector3 origin, Vector3 direction, float length)
    {
        var found = new Settings(); var fallback = new Settings(); float nearest = float.PositiveInfinity, fallbackDistance = float.PositiveInfinity;
        foreach (var branch in graph)
        {
            if (branch["id"].AsString() != parent || !branch.TryGetValue("topology", out var value)) continue; var topology = value.AsGodotDictionary();
            for (int f = topology["face_start"].AsInt32(); f < topology["face_end"].AsInt32(); f++)
            {
                int[] face = mesh.Faces[f]; if (face.Length != 3) continue; float alignment = ModelGeometryOperations.Normal(mesh.Points, face).Dot(direction);
                if (alignment > .15f) { Vector3 center = Center(mesh, f); float score = origin.DistanceSquaredTo(center) / Mathf.Max(.2f, alignment); if (score < fallbackDistance) { fallbackDistance = score; fallback = new Settings { ["point"] = center, ["face"] = f, ["indices"] = face }; } }
                Variant hit = Geometry3D.SegmentIntersectsTriangle(origin, origin + direction * Mathf.Max(.1f, length), mesh.Points[face[0]], mesh.Points[face[1]], mesh.Points[face[2]]); if (hit.VariantType == Variant.Type.Nil || alignment < .15f) continue;
                float distance = origin.DistanceSquaredTo(hit.AsVector3()); if (distance < nearest) { nearest = distance; found = new Settings { ["point"] = hit, ["face"] = f, ["indices"] = face }; }
            }
            break;
        }
        return found.Count == 0 ? fallback : found;
    }
    internal static void Stitch(Topology mesh, Settings junction, Settings tube, Vector3 axis)
    {
        if (junction.Count == 0 || tube.Count == 0) return; Vector3 center = junction["point"].AsVector3(), u = axis.Cross(Mathf.Abs(axis.Z) < .9f ? Vector3.Forward : Vector3.Right).Normalized(), v = axis.Cross(u);
        (int Index, double Angle)[] Ring(int[] indices) => indices.Select(index => { Vector3 offset = mesh.Points[index] - center; double angle = Math.Atan2(offset.Dot(v), offset.Dot(u)) % Math.Tau; if (angle < 0) angle += Math.Tau; return (Index: index, Angle: angle); }).OrderBy(entry => entry.Angle).ToArray();
        var a = Ring(junction["indices"].AsInt32Array()); var b = Ring(Enumerable.Range(tube["start"].AsInt32(), tube["sides"].AsInt32()).ToArray()); int ai = 0, bi = 0;
        for (int step = 0; step < a.Length + b.Length; step++)
        {
            double nextA = ai >= a.Length ? double.PositiveInfinity : a[(ai + 1) % a.Length].Angle + (ai + 1 >= a.Length ? Math.Tau : 0), nextB = bi >= b.Length ? double.PositiveInfinity : b[(bi + 1) % b.Length].Angle + (bi + 1 >= b.Length ? Math.Tau : 0);
            int[] face = nextA < nextB ? new[] { a[ai % a.Length].Index, a[(ai + 1) % a.Length].Index, b[bi % b.Length].Index } : new[] { a[ai % a.Length].Index, b[(bi + 1) % b.Length].Index, b[bi % b.Length].Index };
            int f = mesh.AddFace(face); Vector3 c = Center(mesh, f) - center, radial = c - axis * c.Dot(axis); if (ModelGeometryOperations.Normal(mesh.Points, face).Dot(radial) < 0) { Array.Reverse(mesh.Faces[f]); Array.Reverse(mesh.Uv[f]); }
            if (nextA < nextB) ai++; else bi++;
        }
        mesh.Faces[junction["face"].AsInt32()] = Array.Empty<int>(); mesh.Faces[tube["cap"].AsInt32()] = Array.Empty<int>();
    }
    internal static void Leaf(Topology mesh, Vector3 origin, Vector3 direction, float size, float width, int slot = 1, int style = 0)
    {
        Vector3 d = direction.Normalized(), side = d.Cross(Mathf.Abs(d.Y) < .95f ? Vector3.Up : Vector3.Right).Normalized() * size * width; int at = mesh.Points.Count;
        if (style > 0)
        {
            var outline = new List<Vector2>(); if (style == 1) outline.AddRange(new[] { new Vector2(0, 0), new Vector2(-.35f, .3f), new Vector2(-1, .45f), new Vector2(-.5f, .57f), new Vector2(-.75f, .85f), new Vector2(-.2f, .72f), new Vector2(0, 1), new Vector2(.2f, .72f), new Vector2(.75f, .85f), new Vector2(.5f, .57f), new Vector2(1, .45f), new Vector2(.35f, .3f) });
            else for (int i = 0; i < 20; i++) { float angle = Mathf.Tau * i / 20, t = (1 - Mathf.Cos(angle)) * .5f, w = Mathf.Sin(angle) * (style == 2 ? 1 + .2f * Mathf.Sin(t * Mathf.Pi * 8) : 1); outline.Add(new Vector2(w, t)); }
            foreach (var point in outline) mesh.Points.Add(origin + d * size * point.Y + side * point.X); mesh.Points.Add(origin + d * size * .5f + Vector3.Up * size * .06f);
            for (int index = 0; index < outline.Count; index++) { Vector2 a = outline[index], b = outline[(index + 1) % outline.Count]; mesh.AddFace(new[] { at + index, at + (index + 1) % outline.Count, at + outline.Count }, new[] { new Vector2(a.X * .5f + .5f, a.Y), new Vector2(b.X * .5f + .5f, b.Y), new Vector2(.5f, .5f) }, slot); } return;
        }
        mesh.Points.AddRange(new[] { origin, origin + d * size * .45f + side, origin + d * size + Vector3.Up * size * .1f, origin + d * size * .45f - side, origin + d * size * .5f + Vector3.Up * size * .09f });
        var mapping = new[] { new Vector2(.5f, 0), new Vector2(0, .45f), new Vector2(.5f, 1), new Vector2(1, .45f), new Vector2(.5f, .5f) };
        foreach (int[] face in new[] { new[] { 0, 1, 4 }, new[] { 1, 2, 4 }, new[] { 2, 3, 4 }, new[] { 3, 0, 4 } }) mesh.AddFace(face.Select(index => at + index).ToArray(), face.Select(index => mapping[index]).ToArray(), slot);
    }
    internal static void Blade(Topology mesh, Vector3 origin, Vector3 direction, float height, float curve)
    {
        int start = mesh.Points.Count; float width = height * .025f; Vector3 side = direction.Cross(Vector3.Up).Normalized();
        for (int i = 0; i < 7; i++) { float t = i / 6f; Vector3 center = origin + Vector3.Up * height * t + direction * height * (.08f * t + curve * t * t); float w = Mathf.Max(.00005f, Mathf.Sin(Mathf.Pi * (t * .9f + .05f)) * width * (1 - t * .9f)); mesh.Points.Add(center - side * w); mesh.Points.Add(center + side * w); if (i > 0) { int a = start + (i - 1) * 2; mesh.AddFace(new[] { a, a + 1, a + 3, a + 2 }, new[] { new Vector2(0, (i - 1) / 6f), new Vector2(1, (i - 1) / 6f), new Vector2(1, t), new Vector2(0, t) }, 1); } }
    }
    internal static Vector3 TrianglePoint(Vector3 p, Vector3 a, Vector3 b, Vector3 c)
    {
        Vector3 ab = b - a, ac = c - a, ap = p - a; float d1 = ab.Dot(ap), d2 = ac.Dot(ap); if (d1 <= 0 && d2 <= 0) return a;
        Vector3 bp = p - b; float d3 = ab.Dot(bp), d4 = ac.Dot(bp); if (d3 >= 0 && d4 <= d3) return b; float vc = d1 * d4 - d3 * d2; if (vc <= 0 && d1 >= 0 && d3 <= 0) return a + ab * (d1 / Mathf.Max(.000000001f, d1 - d3));
        Vector3 cp = p - c; float d5 = ab.Dot(cp), d6 = ac.Dot(cp); if (d6 >= 0 && d5 <= d6) return c; float vb = d5 * d2 - d1 * d6; if (vb <= 0 && d2 >= 0 && d6 <= 0) return a + ac * (d2 / Mathf.Max(.000000001f, d2 - d6));
        float va = d3 * d6 - d5 * d4; if (va <= 0 && d4 - d3 >= 0 && d5 - d6 >= 0) return b + (c - b) * ((d4 - d3) / Mathf.Max(.000000001f, d4 - d3 + d5 - d6)); float denominator = Mathf.Max(.000000001f, va + vb + vc); return a + ab * (vb / denominator) + ac * (vc / denominator);
    }
}
