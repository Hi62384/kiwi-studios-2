using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

public partial class RigMath : RefCounted
{
    private static Variant Value(Settings bone, string key, Variant fallback) => bone.TryGetValue(key, out var found) ? found : fallback;
    private static GArray Bones(Resource rig) => rig.Get("bones").AsGodotArray();
    public Godot.Collections.Array<Transform3D> globals(GArray bones, bool pose)
    {
        var result = new Transform3D[bones.Count]; var ready = new bool[bones.Count]; var visiting = new bool[bones.Count];
        Transform3D Global(int index)
        {
            if (ready[index]) return result[index]; if (visiting[index]) return Transform3D.Identity; visiting[index] = true;
            var bone = bones[index].AsGodotDictionary();
            var local = pose ? new Transform3D(Basis.FromEuler(bone["rotation"].AsVector3() * (Mathf.Pi / 180)) * Basis.FromScale(bone["scale"].AsVector3()), bone["position"].AsVector3()) : bone["rest"].AsTransform3D();
            int parent = bone["parent"].AsInt32(); result[index] = parent >= 0 && parent < bones.Count ? Global(parent) * local : local;
            ready[index] = true; visiting[index] = false; return result[index];
        }
        for (int i = 0; i < bones.Count; i++) Global(i);
        return new Godot.Collections.Array<Transform3D>(result);
    }
    public long bind_signature(GArray bones)
    {
        var values = new GArray();
        foreach (Variant value in bones) { var bone = value.AsGodotDictionary(); values.Add(new GArray { Value(bone, "id", Value(bone, "name", "")), bone["parent"], bone["rest"] }); }
        return GD.Hash(values);
    }
    public Vector3 tail(Settings bone, Transform3D global) => global * new Vector3(0, (float)Math.Max(.001, Value(bone, "length", .25).AsDouble()), 0);
    public Transform3D frame(Vector3 head, Vector3 end, double roll)
    {
        Vector3 direction = (end - head).Normalized(); if (direction.LengthSquared() < .5) direction = Vector3.Up;
        return new Transform3D(new Basis(new Quaternion(Vector3.Up, direction)) * new Basis(Vector3.Up, (float)roll), head);
    }
    public void set_rest(Settings bone, Transform3D local, bool keepPose)
    {
        Transform3D old = Value(bone, "rest", local).AsTransform3D();
        var pose = new Transform3D(Basis.FromEuler(Value(bone, "rotation", Vector3.Zero).AsVector3() * (Mathf.Pi / 180)) * Basis.FromScale(Value(bone, "scale", Vector3.One).AsVector3()), Value(bone, "position", local.Origin).AsVector3());
        bone["rest"] = local; Transform3D next = keepPose ? local * old.AffineInverse() * pose : local;
        bone["position"] = next.Origin; bone["rotation"] = next.Basis.GetRotationQuaternion().GetEuler() * (180 / Mathf.Pi); bone["scale"] = next.Basis.Scale;
    }
    public void ensure(Resource rig)
    {
        var bones = Bones(rig); Godot.Collections.Array<Transform3D>? world = null;
        for (int i = 0; i < bones.Count; i++)
        {
            var bone = bones[i].AsGodotDictionary();
            if (!bone.ContainsKey("id") || bone["id"].AsString().Length == 0) bone["id"] = rig.Get("id").AsString() + ":bone:" + i;
            if (!bone.ContainsKey("length"))
            {
                bone["length"] = .25;
                foreach (Variant childValue in bones) { var child = childValue.AsGodotDictionary(); if (child["parent"].AsInt32() == i) { bone["length"] = Math.Max(.01, child["rest"].AsTransform3D().Origin.Length()); break; } }
            }
            if (!bone.ContainsKey("radius")) bone["radius"] = Math.Max(.025, bone["length"].AsDouble() * .3);
            if (!bone.ContainsKey("connected")) bone["connected"] = false;
            if (!bone.ContainsKey("roll"))
            {
                world ??= globals(bones, false); var aligned = frame(world[i].Origin, world[i].Origin + world[i].Basis.Y, 0);
                var relative = aligned.Basis.Inverse() * world[i].Basis.Orthonormalized(); bone["roll"] = Math.Atan2(relative.Z.X, relative.X.X);
            }
            if (!bone.ContainsKey("mirror_id")) bone["mirror_id"] = "";
            if (!bone.ContainsKey("metadata")) bone["metadata"] = new Settings();
        }
    }
    public int add_bone(Resource rig, Vector3 head, Vector3 end, int parent, string title)
    {
        ensure(rig); var bones = Bones(rig); if (parent < -1 || parent >= bones.Count) parent = -1;
        var world = globals(bones, false); var local = frame(head, end, 0); if (parent >= 0) local = world[parent].AffineInverse() * local;
        var names = new HashSet<string>(bones.Select(value => value.AsGodotDictionary()["name"].AsString())); string unique = title; int number = 2;
        while (names.Contains(unique)) unique = title + " " + number++;
        double length = head.DistanceTo(end);
        var bone = new Settings { ["id"] = Guid.NewGuid().ToString("N"), ["name"] = unique, ["parent"] = parent, ["length"] = Math.Max(.001, length), ["radius"] = Math.Max(.025, length * .3), ["connected"] = parent >= 0 && tail(bones[parent].AsGodotDictionary(), world[parent]).DistanceTo(head) < .001, ["roll"] = 0.0, ["mirror_id"] = "", ["metadata"] = new Settings() };
        set_rest(bone, local, false); bones.Add(bone); rig.Set("bones", bones); return bones.Count - 1;
    }
    public void move_joint(Resource rig, int index, bool end, Vector3 position, bool connected)
    {
        var bones = Bones(rig); if (index < 0 || index >= bones.Count) return;
        var world = globals(bones, false); Vector3[] heads = world.Select(pose => pose.Origin).ToArray(); Vector3[] tails = bones.Select((value, i) => tail(value.AsGodotDictionary(), world[i])).ToArray();
        var changed = new HashSet<int> { index };
        if (end)
        {
            tails[index] = position;
            if (connected) for (int i = 0; i < bones.Count; i++) { var bone = bones[i].AsGodotDictionary(); if (bone["parent"].AsInt32() == index && Value(bone, "connected", false).AsBool()) { heads[i] = position; changed.Add(i); } }
        }
        else
        {
            heads[index] = position; var bone = bones[index].AsGodotDictionary(); int parent = bone["parent"].AsInt32();
            if (connected && parent >= 0 && Value(bone, "connected", false).AsBool())
            {
                tails[parent] = position; changed.Add(parent);
                for (int i = 0; i < bones.Count; i++) { var sibling = bones[i].AsGodotDictionary(); if (sibling["parent"].AsInt32() == parent && Value(sibling, "connected", false).AsBool()) { heads[i] = position; changed.Add(i); } }
            }
            else if (!connected) bone["connected"] = false;
        }
        foreach (int i in changed) world[i] = frame(heads[i], tails[i], Value(bones[i].AsGodotDictionary(), "roll", 0.0).AsDouble());
        for (int i = 0; i < bones.Count; i++)
        {
            var bone = bones[i].AsGodotDictionary(); int parent = bone["parent"].AsInt32(); if (changed.Contains(i)) bone["length"] = Math.Max(.001, heads[i].DistanceTo(tails[i]));
            set_rest(bone, parent >= 0 ? world[parent].AffineInverse() * world[i] : world[i], true);
        }
    }
    public int[] descendants(Resource rig, int index)
    {
        var bones = Bones(rig); var result = new List<int> { index }; var seen = new HashSet<int> { index };
        for (int cursor = 0; cursor < result.Count; cursor++) for (int i = 0; i < bones.Count; i++) if (bones[i].AsGodotDictionary()["parent"].AsInt32() == result[cursor] && seen.Add(i)) result.Add(i);
        return result.ToArray();
    }
    public void duplicate_chain(Resource rig, int[] chosen, bool reflect, int axis, double offset)
    {
        var bones = Bones(rig); var world = globals(bones, false); var mapping = new Dictionary<int, int>();
        foreach (int index in chosen)
        {
            var bone = bones[index].AsGodotDictionary(); Vector3 head = world[index].Origin, end = tail(bone, world[index]);
            if (reflect) { head[axis] = (float)(2 * offset - head[axis]); end[axis] = (float)(2 * offset - end[axis]); }
            else { head += Vector3.Right * .1f; end += Vector3.Right * .1f; }
            string name = bone["name"].AsString();
            string title = name.EndsWith("_L", StringComparison.Ordinal) ? name[..^2] + "_R" : name.EndsWith("_R", StringComparison.Ordinal) ? name[..^2] + "_L" : name + (reflect ? "_R" : " copy");
            int parent = bone["parent"].AsInt32(); int added = add_bone(rig, head, end, mapping.GetValueOrDefault(parent, parent), title); mapping[index] = added;
            var copy = bones[added].AsGodotDictionary(); copy["radius"] = bone["radius"]; copy["metadata"] = bone["metadata"].AsGodotDictionary().Duplicate(true);
            if (reflect) { bone["mirror_id"] = copy["id"]; copy["mirror_id"] = bone["id"]; }
        }
    }
    public void fit_to_bounds(Resource rig, Aabb target)
    {
        var bones = Bones(rig); if (bones.Count == 0) return;
        var world = globals(bones, false); var original = new Aabb(world[0].Origin, Vector3.Zero);
        for (int i = 0; i < bones.Count; i++) { original = original.Expand(world[i].Origin); original = original.Expand(tail(bones[i].AsGodotDictionary(), world[i])); }
        Vector3 scale = target.Size.Max(Vector3.One * .05f) / original.Size.Max(Vector3.One * .05f);
        var heads = new Vector3[bones.Count]; var tails = new Vector3[bones.Count];
        for (int i = 0; i < bones.Count; i++)
        {
            heads[i] = target.GetCenter() + (world[i].Origin - original.GetCenter()) * scale;
            tails[i] = target.GetCenter() + (tail(bones[i].AsGodotDictionary(), world[i]) - original.GetCenter()) * scale;
        }
        for (int i = 0; i < bones.Count; i++) { world[i] = frame(heads[i], tails[i], 0); bones[i].AsGodotDictionary()["length"] = heads[i].DistanceTo(tails[i]); }
        for (int i = 0; i < bones.Count; i++) { var bone = bones[i].AsGodotDictionary(); int parent = bone["parent"].AsInt32(); set_rest(bone, parent >= 0 ? world[parent].AffineInverse() * world[i] : world[i], false); }
    }
    public void capture_preset(Resource preset, Resource? rig)
    {
        if (rig == null) return;
        preset.Set("title", rig.Get("title")); var bones = Bones(rig).Duplicate(true); preset.Set("bones", bones);
        foreach (Variant value in bones) { var bone = value.AsGodotDictionary(); set_rest(bone, bone["rest"].AsTransform3D(), false); }
    }
    public Resource create_preset_armature(Resource preset, bool fit, Aabb target)
    {
        var armature = new KiwiModelComponent();
        armature.Set("id", Guid.NewGuid().ToString("N")); armature.Set("title", preset.Get("title")); armature.Set("is_skeleton", true);
        armature.Set("bones", preset.Get("bones").AsGodotArray().Duplicate(true)); ensure(armature);
        if (fit) fit_to_bounds(armature, target);
        return armature;
    }
    public bool parent_bone(Resource rig, int index, int parent, bool connect)
    {
        var bones = Bones(rig); if (index < 0 || index >= bones.Count || parent < -1 || parent >= bones.Count || parent == index || descendants(rig, index).Contains(parent)) return false;
        var world = globals(bones, false); var bone = bones[index].AsGodotDictionary(); bone["parent"] = parent; bone["connected"] = connect && parent >= 0;
        set_rest(bone, parent >= 0 ? world[parent].AffineInverse() * world[index] : world[index], true);
        if (connect && parent >= 0) move_joint(rig, index, false, tail(bones[parent].AsGodotDictionary(), world[parent]), true);
        return true;
    }
    public string[] validate(GArray bones)
    {
        var errors = new List<string>(); var names = new HashSet<string>(); var ids = new HashSet<string>();
        for (int i = 0; i < bones.Count; i++)
        {
            var bone = bones[i].AsGodotDictionary(); int parent = Value(bone, "parent", -1).AsInt32();
            if (parent >= bones.Count || parent == i || parent < -1) errors.Add("Invalid bone parent");
            var seen = new HashSet<int> { i }; int ancestor = parent;
            while (ancestor >= 0 && ancestor < bones.Count) { if (!seen.Add(ancestor)) { errors.Add("Bone parenting cycle"); break; } ancestor = Value(bones[ancestor].AsGodotDictionary(), "parent", -1).AsInt32(); }
            var rest = Value(bone, "rest", Transform3D.Identity).AsTransform3D();
            if (!rest.Origin.IsFinite() || !rest.Basis.IsFinite() || Math.Abs(rest.Basis.Determinant()) < .000001) errors.Add("Invalid bone rest transform");
            string name = Value(bone, "name", "").AsString(); if (name.Length == 0 || !names.Add(name)) errors.Add("Duplicate or empty bone name");
            if (name.Contains(':') || name.Contains('/')) errors.Add("Unsupported bone name character");
            if (bone.TryGetValue("id", out var id) && (id.AsString().Length == 0 || !ids.Add(id.AsString()))) errors.Add("Missing or duplicate bone identity");
            foreach (string key in new[] { "length", "radius", "roll" }) if (bone.TryGetValue(key, out var value) && (!double.IsFinite(value.AsDouble()) || key != "roll" && value.AsDouble() <= 0)) errors.Add("Invalid bone " + key);
            foreach (string channel in new[] { "position", "rotation", "scale" }) { var value = Value(bone, channel, Vector3.Zero); if (value.VariantType != Variant.Type.Vector3 || !value.AsVector3().IsFinite()) errors.Add("Invalid bone pose"); }
        }
        return errors.ToArray();
    }
}
