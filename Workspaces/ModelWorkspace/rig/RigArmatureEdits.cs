using Godot;
using System;
using Settings = Godot.Collections.Dictionary;

public partial class RigArmatureEdits : RefCounted
{
    private readonly RigMath _math = new();
    public Settings delete_bone(Resource document, Resource armature, int removed)
    {
        var bones = armature.Get("bones").AsGodotArray(); var fallback = new Settings(); if (removed < 0 || removed >= bones.Count) return fallback;
        var world = _math.globals(bones, false); var previous = bones.Duplicate(true); string removedId = previous[removed].AsGodotDictionary()["id"].AsString();
        bones.RemoveAt(removed); armature.Set("bones", bones);
        for (int i = 0; i < bones.Count; i++)
        {
            var bone = bones[i].AsGodotDictionary(); if (bone["mirror_id"].AsString() == removedId) bone["mirror_id"] = "";
            int old = i >= removed ? i + 1 : i, parent = previous[old].AsGodotDictionary()["parent"].AsInt32();
            if (parent == removed) parent = previous[removed].AsGodotDictionary()["parent"].AsInt32();
            bone["parent"] = parent > removed ? parent - 1 : parent;
            _math.set_rest(bone, parent >= 0 ? world[parent].AffineInverse() * world[old] : world[old], true); bone["connected"] = false;
        }
        if (bones.Count > 0)
        {
            int parent = previous[removed].AsGodotDictionary()["parent"].AsInt32(); if (parent > removed) parent--;
            fallback[removedId] = bones[Math.Clamp(parent, 0, bones.Count - 1)].AsGodotDictionary()["id"];
        }
        string rigId = armature.Get("id").AsString();
        foreach (Variant value in document.Get("components").AsGodotArray())
        {
            var item = value.As<Resource>(); var binding = item.Get("binding").As<Resource>();
            if (item.Get("skeleton_id").AsString() == rigId && binding != null && fallback.TryGetValue(binding.Get("rigid_bone_id"), out var replacement)) binding.Set("rigid_bone_id", replacement);
        }
        return fallback;
    }
    public int insert_joint(Resource armature, int old)
    {
        var bones = armature.Get("bones").AsGodotArray(); if (old < 0 || old >= bones.Count) return old;
        var world = _math.globals(bones, false); var original = bones[old].AsGodotDictionary(); Vector3 end = _math.tail(original, world[old]); Vector3 midpoint = world[old].Origin.Lerp(end, .5f);
        original["length"] = original["length"].AsDouble() * .5; int added = _math.add_bone(armature, midpoint, end, old, original["name"].AsString() + " tip");
        var inverse = _math.globals(bones, false)[added].AffineInverse();
        for (int i = 0; i < added; i++)
        {
            var bone = bones[i].AsGodotDictionary(); if (bone["parent"].AsInt32() != old) continue;
            bone["parent"] = added; _math.set_rest(bone, inverse * world[i], true);
        }
        return added;
    }
    public void reset_pose(Resource armature, int selected, bool all)
    {
        var bones = armature.Get("bones").AsGodotArray();
        for (int i = 0; i < bones.Count; i++) if (all || i == selected) { var bone = bones[i].AsGodotDictionary(); _math.set_rest(bone, bone["rest"].AsTransform3D(), false); }
    }
    public void move_joint(Resource armature, int index, bool end, Vector3 point, bool connected, bool symmetry, int axis, double offset)
    {
        _math.move_joint(armature, index, end, point, connected); if (!symmetry) return;
        var bones = armature.Get("bones").AsGodotArray(); var source = bones[index].AsGodotDictionary(); string mirror = source.TryGetValue("mirror_id", out var id) ? id.AsString() : "";
        for (int i = 0; i < bones.Count; i++) if (bones[i].AsGodotDictionary()["id"].AsString() == mirror)
        { Vector3 reflected = point; reflected[axis] = (float)(2 * offset - point[axis]); _math.move_joint(armature, i, end, reflected, connected); break; }
    }
}
