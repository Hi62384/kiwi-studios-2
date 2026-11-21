using Godot;
using System;
using System.Linq;

public partial class ModelViewportNavigation : RefCounted
{
    public void update_camera(Control canvas)
    {
        var camera = canvas.Get("camera").As<Camera3D>(); Basis basis = Basis.FromEuler(new Vector3(canvas.Get("pitch").AsSingle(), canvas.Get("yaw").AsSingle(), 0));
        camera.Position = canvas.Get("target").AsVector3() + basis.Z * canvas.Get("distance").AsSingle(); camera.Basis = basis; canvas.Get("overlay").As<Control>().QueueRedraw();
    }
    public void set_view(Control canvas, string view)
    {
        switch (view)
        {
            case "Front": canvas.Set("yaw", 0f); canvas.Set("pitch", 0f); break;
            case "Back": canvas.Set("yaw", Mathf.Pi); canvas.Set("pitch", 0f); break;
            case "Left": canvas.Set("yaw", -Mathf.Pi / 2); canvas.Set("pitch", 0f); break;
            case "Right": canvas.Set("yaw", Mathf.Pi / 2); canvas.Set("pitch", 0f); break;
            case "Top": canvas.Set("yaw", 0f); canvas.Set("pitch", -Mathf.Pi / 2 + .0001f); break;
            case "Bottom": canvas.Set("yaw", 0f); canvas.Set("pitch", Mathf.Pi / 2 - .0001f); break;
        }
        canvas.Get("camera").As<Camera3D>().Projection = Camera3D.ProjectionType.Orthogonal; update_camera(canvas);
    }
    public void frame(Control canvas, bool all)
    {
        var session = canvas.Get("session").As<RefCounted>(); var document = session.Get("document").As<Resource>(); var lookup = ModelDocumentOperations.Lookup(document);
        var selected = session.Get("selected").AsGodotArray<string>(); var hidden = canvas.Get("preview_hidden").AsGodotDictionary(); var visuals = canvas.Get("visuals").AsGodotDictionary();
        Aabb bounds = default; bool hasPoints = false;
        void Expand(Vector3 point) { bounds = hasPoints ? bounds.Expand(point) : new Aabb(point, Vector3.Zero); hasPoints = true; }
        foreach (var item in lookup.Values)
        {
            string id = item.Get("id").AsString(); if (hidden.ContainsKey(id) || (!all && !selected.Contains(id) && !selected.Any(parent => ModelDocumentOperations.Descendant(lookup, id, parent)))) continue;
            if (item.Get("growth").As<Resource>() != null && visuals.TryGetValue(id, out var value) && value.As<MeshInstance3D>().Mesh is Mesh mesh)
            {
                var visual = value.As<MeshInstance3D>(); Aabb box = mesh.GetAabb();
                for (int corner = 0; corner < 8; corner++) Expand(visual.GlobalTransform * (box.Position + box.Size * new Vector3(corner & 1, (corner >> 1) & 1, (corner >> 2) & 1))); continue;
            }
            var source = item.Get("mesh").As<Resource>(); if (source == null) continue; Transform3D transform = ModelDocumentOperations.WorldTransform(lookup, item);
            foreach (Vector3 vertex in source.Get("vertices").AsVector3Array()) Expand(transform * vertex);
        }
        var camera = canvas.Get("camera").As<Camera3D>();
        canvas.Set("target", hasPoints ? bounds.GetCenter() : Vector3.Zero); canvas.Set("distance", hasPoints ? Mathf.Max(1, bounds.Size.Length() * 1.5f) : 7f); camera.Size = hasPoints ? Mathf.Max(.3f, bounds.Size.Length() * 1.25f) : 6; update_camera(canvas);
    }
    public void rebuild_grid(Control canvas)
    {
        var mesh = new ImmediateMesh(); var material = new StandardMaterial3D { ShadingMode = BaseMaterial3D.ShadingModeEnum.Unshaded, VertexColorUseAsAlbedo = true }; float step = canvas.Get("grid_step").AsSingle();
        mesh.SurfaceBegin(Mesh.PrimitiveType.Lines, material);
        for (int i = -40; i <= 40; i++)
        {
            mesh.SurfaceSetColor(i == 0 ? new Color("593d49") : new Color(.025f, .04f, .055f)); mesh.SurfaceAddVertex(new Vector3(-40 * step, 0, i * step)); mesh.SurfaceAddVertex(new Vector3(40 * step, 0, i * step));
            mesh.SurfaceSetColor(i == 0 ? new Color("325368") : new Color(.025f, .04f, .055f)); mesh.SurfaceAddVertex(new Vector3(i * step, 0, -40 * step)); mesh.SurfaceAddVertex(new Vector3(i * step, 0, 40 * step));
        }
        mesh.SurfaceEnd(); canvas.Get("grid").As<MeshInstance3D>().Mesh = mesh;
    }
    public void fly(Control canvas, double delta)
    {
        var camera = canvas.Get("camera").As<Camera3D>(); Vector3 velocity = Vector3.Zero;
        if (Input.IsPhysicalKeyPressed(Key.W)) velocity -= camera.Basis.Z;
        if (Input.IsPhysicalKeyPressed(Key.S)) velocity += camera.Basis.Z;
        if (Input.IsPhysicalKeyPressed(Key.A)) velocity -= camera.Basis.X;
        if (Input.IsPhysicalKeyPressed(Key.D)) velocity += camera.Basis.X;
        if (Input.IsPhysicalKeyPressed(Key.Q)) velocity -= Vector3.Up;
        if (Input.IsPhysicalKeyPressed(Key.E)) velocity += Vector3.Up;
        canvas.Set("target", canvas.Get("target").AsVector3() + velocity * (float)delta * canvas.Get("fly_speed").AsSingle()); update_camera(canvas);
    }
}
