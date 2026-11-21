using Godot;
using System;
using System.Collections.Generic;
using System.Linq;

public partial class RigGeometry : RefCounted
{
    public Godot.Collections.Dictionary geometry(Mesh source, Transform3D transform)
    {
        var points = new List<Vector3>(); var surfaces = new Godot.Collections.Array<int[]>();
        var lookup = new Dictionary<Vector3I, int>(); var neighbors = new List<HashSet<int>>(); var edges = new Dictionary<(int, int), double>();
        for (int surface = 0; surface < source.GetSurfaceCount(); surface++)
        {
            var arrays = source.SurfaceGetArrays(surface); var vertices = arrays[(int)Mesh.ArrayType.Vertex].AsVector3Array(); var mapping = new int[vertices.Length];
            for (int i = 0; i < vertices.Length; i++)
            {
                Vector3 point = transform * vertices[i]; var key = new Vector3I(Mathf.RoundToInt((double)point.X * 100000), Mathf.RoundToInt((double)point.Y * 100000), Mathf.RoundToInt((double)point.Z * 100000));
                if (!lookup.TryGetValue(key, out int index)) { index = points.Count; lookup[key] = index; points.Add(point); neighbors.Add(new HashSet<int>()); }
                mapping[i] = index;
            }
            Variant indicesValue = arrays[(int)Mesh.ArrayType.Index]; int[] indices = indicesValue.VariantType == Variant.Type.Nil ? System.Array.Empty<int>() : indicesValue.AsInt32Array();
            int count = indices.Length > 0 ? indices.Length : vertices.Length;
            for (int offset = 0; offset < count - 2; offset += 3)
                for (int k = 0; k < 3; k++)
                {
                    int a = mapping[indices.Length > 0 ? indices[offset + k] : offset + k]; int b = mapping[indices.Length > 0 ? indices[offset + (k + 1) % 3] : offset + (k + 1) % 3];
                    if (a == b) continue; neighbors[a].Add(b); neighbors[b].Add(a); edges[(Math.Min(a, b), Math.Max(a, b))] = points[a].DistanceTo(points[b]);
                }
            surfaces.Add(mapping);
        }
        var graph = new Godot.Collections.Array<int[]>(); foreach (var adjacent in neighbors) graph.Add(adjacent.ToArray());
        int[] islands = new int[points.Count]; System.Array.Fill(islands, -1); var groups = new Godot.Collections.Array<int[]>();
        for (int vertex = 0; vertex < points.Count; vertex++)
        {
            if (islands[vertex] >= 0) continue;
            var members = new List<int> { vertex }; islands[vertex] = groups.Count;
            for (int cursor = 0; cursor < members.Count; cursor++)
                foreach (int other in neighbors[members[cursor]]) if (islands[other] < 0) { islands[other] = groups.Count; members.Add(other); }
            groups.Add(members.ToArray());
        }
        double average = 0; foreach (double distance in edges.Values) average += distance;
        return new Godot.Collections.Dictionary { ["points"] = points.ToArray(), ["surfaces"] = surfaces, ["neighbors"] = graph, ["islands"] = islands, ["groups"] = groups, ["edge"] = average / Math.Max(1, edges.Count) };
    }
}
