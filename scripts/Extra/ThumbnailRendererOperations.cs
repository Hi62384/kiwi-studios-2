using Godot;
using System;
public partial class ThumbnailRendererOperations : RefCounted
{
    private static GDScript Bridge => GD.Load<GDScript>("res://scripts/Extra/thumbnail_renderer.gd");
    public Node3D? render_owner()
    {
        var value = Bridge.Get("_instance"); return value.VariantType == Variant.Type.Object && value.AsGodotObject() is Node3D owner && GodotObject.IsInstanceValid(owner) && !owner.IsQueuedForDeletion() ? owner : null;
    }
    public void ready(Node3D owner) => Bridge.Set("_instance", owner);
    public void exit_tree(Node3D owner) { if (Bridge.Get("_instance").AsGodotObject() == owner) { Bridge.Set("_instance", default); Bridge.Set("_render_busy", false); } }
    public bool try_begin()
    {
        if (render_owner() == null || Bridge.Get("_render_busy").AsBool()) return false; Bridge.Set("_render_busy", true); return true;
    }
    public void delete_objects()
    {
        var owner = render_owner(); if (owner == null) return; var holder = owner.Get("object_holder").As<MeshInstance3D>(); foreach (Node child in holder.GetChildren()) { holder.RemoveChild(child); child.QueueFree(); }
    }
    public void set_target_visibility(int target)
    {
        var owner = render_owner(); if (owner == null) return; delete_objects(); var holder = owner.Get("object_holder").As<MeshInstance3D>(); holder.Mesh = null; var viewport = owner.Get("sub_viewport").As<SubViewport>(); viewport.FindWorld3D().Environment = GD.Load<Godot.Environment>("uid://bngpc7xkudi0e"); holder.Visible = target == 0; owner.Get("sphere_renderer").As<MeshInstance3D>().Visible = target == 1; viewport.TransparentBg = target != 2;
    }
    public void center_object_holder()
    {
        var owner = render_owner(); if (owner == null) return; var holder = owner.Get("object_holder").As<MeshInstance3D>(); var camera = owner.Get("camera_3d").As<Camera3D>(); var aabb = holder.GetAabb(); var center = holder.ToGlobal(aabb.Position + aabb.Size * .5f); var target = camera.GlobalPosition - camera.GlobalTransform.Basis.Z * 5; holder.GlobalPosition += target - center;
    }
    public void prepare_render(string kind, Resource resource)
    {
        var owner = render_owner(); if (owner == null) return; set_target_visibility(kind == "material" ? 1 : kind == "environment" ? 2 : 0);
        switch (kind)
        {
            case "material": owner.Get("sphere_renderer").As<MeshInstance3D>().MaterialOverride = (Material)resource; break;
            case "mesh": owner.Get("object_holder").As<MeshInstance3D>().Mesh = (Mesh)resource; center_object_holder(); break;
            case "scene": owner.Get("object_holder").As<MeshInstance3D>().AddChild(((PackedScene)resource).Instantiate()); center_object_holder(); break;
            case "environment": owner.Get("sub_viewport").As<SubViewport>().FindWorld3D().Environment = (Godot.Environment)resource; break;
        }
    }
    public SubViewport? prepare_snap()
    {
        var owner = render_owner(); if (owner == null) return null; var viewport = owner.Get("sub_viewport").As<SubViewport>(); viewport.RenderTargetUpdateMode = SubViewport.UpdateMode.Once; return viewport;
    }
    public Texture2D? finish_snap(SubViewport? viewport, bool temporary)
    {
        var owner = render_owner(); if (owner == null || !GodotObject.IsInstanceValid(viewport)) return null;
        if (temporary ? viewport!.GetParent() != owner : viewport != owner.Get("sub_viewport").As<SubViewport>()) return null;
        try
        {
            using var image = viewport!.GetTexture()?.GetImage(); return image == null || image.IsEmpty() ? null : ImageTexture.CreateFromImage(image);
        }
        finally { if (temporary) viewport!.QueueFree(); Bridge.Set("_render_busy", false); }
    }
    public Godot.Environment actor_environment(Resource data)
    {
        var runtime = GD.Load<PackedScene>("res://scripts/actors/examples/basic_actor.tscn").Instantiate<Node3D>();
        try { var environment = new Godot.Environment(); new BasicActorOperations().configure_environment(runtime, environment, data); return environment; }
        finally { runtime.Free(); }
    }
    public SubViewport? prepare_text(Resource data)
    {
        var owner = render_owner(); if (owner == null) return null;
        var viewport = new SubViewport { Size = new Vector2I(256, 144), TransparentBg = false, RenderTargetUpdateMode = SubViewport.UpdateMode.Once }; owner.AddChild(viewport); var background = new ColorRect { Color = new Color("182532") }; background.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect); viewport.AddChild(background);
        var label = new Label { Text = "Aa  Text", HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center }; label.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect); new ActorTextSettingsOperations().apply_label(label, data.Get("values").AsGodotDictionary()); viewport.AddChild(label); return viewport;
    }
}
