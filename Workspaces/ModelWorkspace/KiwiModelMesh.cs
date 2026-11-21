using Godot;
using System;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class KiwiModelMesh : Resource
{
    [Export] public Vector3[] vertices { get; set; } = Array.Empty<Vector3>();
    [Export] public Godot.Collections.Array<int[]> faces { get; set; } = new();
    [Export] public Godot.Collections.Array<Vector2[]> uv { get; set; } = new();
    [Export] public int[] materials { get; set; } = Array.Empty<int>();
    [Export] public bool smooth { get; set; }
    public long _edge_signature { get; set; } = -1;
    public Godot.Collections.Array<Settings> _edge_cache { get; set; } = new();
    private readonly ModelMeshOperations _operations = new();
    public int _vertex_count() => vertices.Length;
    public KiwiModelMesh copy_mesh() => (KiwiModelMesh)_operations.copy_mesh(this);
    public Vector3[] _face_points(int face)
    {
        int[] indices = faces[face]; var points = new Vector3[indices.Length];
        for (int i = 0; i < indices.Length; i++) points[i] = vertices[indices[i]];
        return points;
    }
    public int add_face(int[] indices) => add_face(indices, Array.Empty<Vector2>(), 0);
    public int add_face(int[] indices, Vector2[] corners) => add_face(indices, corners, 0);
    public int add_face(int[] indices, Vector2[] corners, int material)
    {
        faces.Add(indices); var next = materials; Array.Resize(ref next, next.Length + 1);
        next[^1] = material; materials = next;
        if (corners.Length != indices.Length) corners = _operations.face_uv(_face_points(faces.Count - 1));
        uv.Add(corners); return faces.Count - 1;
    }
    public Vector3 center(int face) => _operations.center(_face_points(face));
    public Vector3 normal(int face) => _operations.normal(_face_points(face));
    public Godot.Collections.Array<Settings> edges() => _operations.edges(this);
    public static string edge_key(int a, int b) => new ModelMeshOperations().edge_key(a, b);
    public int[] triangles(int face_index) => _operations.triangles(_face_points(face_index));
    public Vector2 uv_at(int face, Vector3 point) => _operations.uv_at(_face_points(face), uv[face], point);
    public string[] validate() => _operations.validate(this, true);
    public string[] validate(bool thorough) => _operations.validate(this, thorough);
    public ArrayMesh render_mesh() => _operations.render_mesh(this, new Godot.Collections.Array<Material>());
    public ArrayMesh render_mesh(Godot.Collections.Array<Material> surface_materials) => _operations.render_mesh(this, surface_materials);
    public static KiwiModelMesh from_mesh(Mesh? source) => (KiwiModelMesh)new ModelMeshOperations().from_mesh(source);
    public void append_mesh(KiwiModelMesh other) => _operations.append_mesh(this, other, Transform3D.Identity, 0);
    public void append_mesh(KiwiModelMesh other, Transform3D transform) => _operations.append_mesh(this, other, transform, 0);
    public void append_mesh(KiwiModelMesh other, Transform3D transform, int material_offset) => _operations.append_mesh(this, other, transform, material_offset);
    public Aabb bounds() => _operations.bounds(this);
}
