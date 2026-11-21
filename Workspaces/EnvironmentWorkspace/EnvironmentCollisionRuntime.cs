using Godot;
using System;

public partial class EnvironmentCollisionRuntime : RefCounted
{
    public void build_chunk(Node3D runtime, Resource terrain, Vector2I coordinate, MeshInstance3D chunk, long key)
    {
        chunk.Mesh = terrain.Call("chunk_mesh", coordinate, runtime.Get("cave_cutaway"), chunk.GetMeta("smooth_paint", false)).As<Mesh>(); chunk.SetMeta("terrain_key", key); runtime.Set("chunks_rebuilt", runtime.Get("chunks_rebuilt").AsInt64() + 1);
        var body = chunk.GetNodeOrNull<StaticBody3D>("Collision");
        if (chunk.Mesh.GetSurfaceCount() == 0) { if (body != null) body.CollisionLayer = 0; return; }
        if (body == null) { body = new StaticBody3D { Name = "Collision" }; chunk.AddChild(body); body.AddChild(new CollisionShape3D { Name = "Shape" }); }
        var collider = body.GetNode<CollisionShape3D>("Shape");
        // Render meshes may outlive every viewport through terrain caches and
        // saved documents. Physics-server shapes belong to their live collider.
        if (chunk.Mesh.HasMeta("kiwi_terrain_collision")) chunk.Mesh.RemoveMeta("kiwi_terrain_collision");
        // The collider retains a native resource reference. Release the managed
        // creation reference now rather than during late engine finalization.
        using var shape = new ConcavePolygonShape3D(); shape.SetFaces(chunk.Mesh.GetFaces()); collider.Shape = shape;
    }
    public void assign_chunk_materials(MeshInstance3D chunk, Material? material, Material? paint, bool collision)
    {
        chunk.MaterialOverride = null; int[] slots = chunk.Mesh.GetMeta("environment_material_slots", Array.Empty<int>()).AsInt32Array();
        for (int surface = 0; surface < chunk.Mesh.GetSurfaceCount(); surface++) chunk.SetSurfaceOverrideMaterial(surface, surface < slots.Length && slots[surface] == 1 && paint != null ? paint : material);
        var body = chunk.GetNodeOrNull<StaticBody3D>("Collision"); if (body != null) body.CollisionLayer = collision && chunk.Visible && chunk.Mesh.GetSurfaceCount() > 0 ? 1u : 0;
    }
    public void sync_asset_collision(Node3D node, bool enabled)
    {
        foreach (Node child in node.GetChildren())
        {
            if (child is not MeshInstance3D visual) continue; var body = visual.GetNodeOrNull<StaticBody3D>("Collision");
            if (enabled && body == null && visual.Mesh != null)
            {
                Vector3[] faces = visual.Mesh.GetMeta("kiwi_collision_faces", visual.Mesh.GetFaces()).AsVector3Array(); if (faces.Length == 0) continue;
                body = new StaticBody3D { Name = "Collision" }; visual.AddChild(body); using var shape = new ConcavePolygonShape3D(); shape.SetFaces(faces); body.AddChild(new CollisionShape3D { Shape = shape });
            }
            if (body != null) body.CollisionLayer = enabled && node.Visible ? 1u : 0;
        }
    }
    public void release(Node3D runtime)
    {
        foreach (var node in runtime.FindChildren("*", "MeshInstance3D", true, false)) if (((MeshInstance3D)node).Mesh is Mesh mesh && mesh.HasMeta("kiwi_terrain_collision")) mesh.RemoveMeta("kiwi_terrain_collision");
        foreach (var node in runtime.FindChildren("*", "CollisionShape3D", true, false)) ((CollisionShape3D)node).Shape = null;
    }
}
