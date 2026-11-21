using Godot;
using System;
using System.Linq;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

public partial class RigEditor : RefCounted
{
    public RefCounted? session { get; set; }
    public string rig_id { get; set; } = "";
    public bool enabled { get; set; }
    public string mode { get; set; } = "Edit";
    public bool symmetry { get; set; }
    public int symmetry_axis { get; set; }
    public double symmetry_offset { get; set; }
    public bool show_bones { get; set; } = true;
    public bool only_chain { get; set; }
    public bool connected { get; set; } = true;
    public bool busy { get; set; }
    public string message { get; set; } = "";
    public int selected_bone
    {
        get { if (session == null) return 0; var selection = session.Get("rig_selection").AsGodotDictionary(); return selection.TryGetValue(rig_id, out var value) ? value.AsInt32() : 0; }
        set { if (session == null) return; var selection = session.Get("rig_selection").AsGodotDictionary(); selection[rig_id] = value; session.Set("rig_selection", selection); }
    }
    private RefCounted Owner => session ?? throw new InvalidOperationException("The rig editor has no model session.");
    private Resource Document => Owner.Get("document").As<Resource>();
    private readonly RigMath _math = new();
    private readonly RigArmatureEdits _edits = new();
    private readonly RigBindingWeights _bindings = new();
    private readonly RigBindingImport _importer = new();
    private static string Text(Resource value, string property) => value.Get(property).AsString();
    private Resource? Component(string id) => Document.Call("component", id).As<Resource>();
    private void Action(string label, Action operation)
    {
        Owner.Call("begin");
        try { operation(); } catch { Owner.Call("cancel"); throw; }
        Owner.Call("commit", label);
    }
    public Resource? rig()
    {
        var primary = Owner.Call("primary").As<Resource>();
        if (rig_id.Length == 0 && primary != null)
        { if (primary.Get("is_skeleton").AsBool()) rig_id = Text(primary, "id"); else if (Text(primary, "skeleton_id").Length > 0) rig_id = Text(primary, "skeleton_id"); }
        var result = Component(rig_id);
        if (result == null) foreach (Variant value in Document.Get("components").AsGodotArray())
        { var item = value.As<Resource>(); if (item.Get("is_skeleton").AsBool()) { result = item; rig_id = Text(item, "id"); break; } }
        if (result != null) { _math.ensure(result); selected_bone = Math.Clamp(selected_bone, 0, Math.Max(0, result.Get("bones").AsGodotArray().Count - 1)); }
        return result;
    }
    public Godot.Collections.Array<Resource> meshes()
    {
        var result = new Godot.Collections.Array<Resource>(); var selected = Owner.Get("selected").AsGodotArray();
        foreach (Variant value in Document.Get("components").AsGodotArray())
        {
            var item = value.As<Resource>(); if (item.Get("mesh").As<Resource>() == null || !Document.Call("editable_component", item).AsBool()) continue;
            bool included = selected.Contains(item.Get("id"));
            foreach (Variant id in selected) if (Document.Call("is_descendant", item.Get("id"), id).AsBool()) included = true;
            if (included) result.Add(item);
        }
        if (result.Count == 0 && rig() != null) foreach (Variant value in Document.Get("components").AsGodotArray())
        { var item = value.As<Resource>(); if (item.Get("mesh").As<Resource>() != null && Text(item, "skeleton_id") == rig_id && Document.Call("editable_component", item).AsBool()) result.Add(item); }
        return result;
    }
    public Aabb bounds()
    {
        bool first = true; var result = new Aabb(Vector3.One * -.5f, Vector3.One);
        foreach (var item in meshes()) { var box = Document.Call("world_transform", item).AsTransform3D() * item.Get("mesh").As<Resource>().Call("bounds").AsAabb(); result = first ? box : result.Merge(box); first = false; }
        return result;
    }
    public Resource create(string kind, int count)
    {
        var item = new RigTemplates().create(kind, bounds(), count);
        Action("Create " + kind + " rig", () => Document.Get("components").AsGodotArray().Add(item));
        rig_id = Text(item, "id"); selected_bone = 0; enabled = true; mode = "Edit"; message = "Drag joints to fit. Bind when ready."; return item;
    }
    public Resource empty_rig()
    {
        var item = new KiwiModelComponent(); item.Set("id", Guid.NewGuid().ToString("N")); item.Set("title", "Armature"); item.Set("is_skeleton", true);
        Action("Create armature", () => Document.Get("components").AsGodotArray().Add(item)); rig_id = Text(item, "id"); enabled = true; mode = "Draw"; return item;
    }
    public string bind(string method, int influences)
    {
        var armature = rig(); var prepared = _importer.prepare_bind(Document, armature, new GArray(meshes().Select(value => Variant.From(value))), selected_bone, method, influences);
        return prepared["message"].AsString().Length > 0 ? prepared["message"].AsString() : install_bindings(Text(armature!, "id"), prepared["bindings"].AsGodotDictionary());
    }
    public string install_bindings(string id, Settings bindings)
    {
        var armature = Component(id); if (armature == null) return "Armature no longer exists.";
        string error = _bindings.prepare_install(Document, armature, bindings); if (error.Length > 0) return error;
        Action("Bind meshes to armature", () => _bindings.install_bindings(Document, armature, bindings)); message = "Bound " + bindings.Count + " mesh(es). Pose the bones to test deformation."; return "";
    }
    public bool can_edit_rest()
    {
        var armature = rig(); if (armature == null) return true;
        foreach (Variant value in Document.Get("components").AsGodotArray())
        {
            var item = value.As<Resource>();
            if (Text(item, "skeleton_id") == Text(armature, "id") && item.Get("skin_mesh").As<Mesh>() != null && item.Get("binding").As<Resource>() == null)
            { message = "Adopt imported weights in Weight mode before editing this rig's rest structure, or explicitly rebind its meshes. Original custom binds are preserved."; return false; }
        }
        return true;
    }
    public void add(Vector3 head, Vector3 tail, int parent)
    {
        if (!can_edit_rest()) return; var armature = rig() ?? empty_rig();
        Action("Draw bone", () => { selected_bone = _math.add_bone(armature, head, tail, parent, "Bone"); if (symmetry) mirror_chain(armature, new[] { selected_bone }, true); _bindings.refresh_bindings(Document, armature, true, new Settings()); });
    }
    public void move_joint(int index, bool end, Vector3 point)
    {
        if (!can_edit_rest()) return; var armature = rig(); if (armature == null) return;
        _edits.move_joint(armature, index, end, point, connected, symmetry, symmetry_axis, symmetry_offset); _bindings.refresh_bindings(Document, armature, false, new Settings()); Owner.EmitSignal("changed");
    }
    public void reset_pose(bool all)
    { var armature = rig(); if (armature != null) Action("Reset rig pose", () => _edits.reset_pose(armature, selected_bone, all)); }
    public void pose(string channel, Vector3 value)
    { var armature = rig(); if (armature == null || armature.Get("bones").AsGodotArray().Count == 0) return; Action("Pose bone", () => armature.Get("bones").AsGodotArray()[selected_bone].AsGodotDictionary()[channel] = value); }
    public void rename(string title)
    {
        var armature = rig(); title = title.Trim(); if (armature == null || armature.Get("bones").AsGodotArray().Count == 0 || title.Length == 0) return;
        if (title.Contains(':') || title.Contains('/')) { message = "Bone names cannot contain ':' or '/'."; return; }
        var bones = armature.Get("bones").AsGodotArray();
        for (int i = 0; i < bones.Count; i++) if (i != selected_bone && bones[i].AsGodotDictionary()["name"].AsString() == title) { message = "Bone names must be unique."; return; }
        Action("Rename bone", () => bones[selected_bone].AsGodotDictionary()["name"] = title);
    }
    public void parent(int parent, bool connect)
    {
        if (!can_edit_rest()) return; var armature = rig(); if (armature == null) return;
        if (selected_bone >= armature.Get("bones").AsGodotArray().Count || parent < -1 || parent >= armature.Get("bones").AsGodotArray().Count || _math.descendants(armature, selected_bone).Contains(parent)) { message = "A bone cannot be parented to itself or its descendants."; return; }
        Action("Parent bone", () => { _math.parent_bone(armature, selected_bone, parent, connect); _bindings.refresh_bindings(Document, armature, false, new Settings()); });
    }
    public void delete_bone()
    {
        if (!can_edit_rest()) return; var armature = rig(); if (armature == null || armature.Get("bones").AsGodotArray().Count == 0) return;
        if (armature.Get("bones").AsGodotArray().Count == 1) foreach (Variant value in Document.Get("components").AsGodotArray())
            if (Text(value.As<Resource>(), "skeleton_id") == Text(armature, "id")) { message = "Detach the meshes before deleting the last bone."; return; }
        int removed = selected_bone;
        Action("Delete bone", () => { var fallback = _edits.delete_bone(Document, armature, removed); _bindings.refresh_bindings(Document, armature, true, fallback); });
        selected_bone = Math.Clamp(removed, 0, Math.Max(0, armature.Get("bones").AsGodotArray().Count - 1));
    }
    public void insert_joint()
    {
        if (!can_edit_rest()) return; var armature = rig(); if (armature == null || armature.Get("bones").AsGodotArray().Count == 0) return; int old = selected_bone;
        Action("Insert bone joint", () => { selected_bone = _edits.insert_joint(armature, old); _bindings.refresh_bindings(Document, armature, true, new Settings()); });
    }
    public void duplicate_chain(bool mirror)
    {
        if (!can_edit_rest()) return; var armature = rig(); if (armature == null || armature.Get("bones").AsGodotArray().Count == 0) return; int[] chosen = _math.descendants(armature, selected_bone);
        Action(mirror ? "Mirror bones" : "Duplicate bone chain", () => { mirror_chain(armature, chosen, mirror); _bindings.refresh_bindings(Document, armature, true, new Settings()); });
    }
    public void mirror_chain(Resource armature, int[] chosen, bool reflect) => _math.duplicate_chain(armature, chosen, reflect, symmetry_axis, symmetry_offset);
    public Resource preset() { var result = new RigPreset(); _math.capture_preset(result, rig()); return result; }
    public bool load_preset(Resource? value, bool fit)
    {
        if (value == null || value is not RigPreset && value.GetScript().As<Script>()?.ResourcePath != "res://Workspaces/ModelWorkspace/rig/rig_preset.gd" || _math.validate(value.Get("bones").AsGodotArray()).Length > 0) return false;
        var armature = _math.create_preset_armature(value, fit, fit ? bounds() : new Aabb()); Action("Load rig preset", () => Document.Get("components").AsGodotArray().Add(armature)); rig_id = Text(armature, "id"); enabled = true; mode = "Edit"; return true;
    }
    public string adopt_imported()
    { var armature = rig(); if (armature == null) return "Select an armature."; var prepared = _importer.prepare_import(Document, armature, new GArray(meshes().Select(value => Variant.From(value)))); return prepared["message"].AsString().Length > 0 ? prepared["message"].AsString() : install_bindings(Text(armature, "id"), prepared["bindings"].AsGodotDictionary()); }
    public string cleanup(string kind)
    {
        var armature = rig(); if (armature == null) return "Select an armature first.";
        var prepared = new RigWeighting().prepare_cleanup(armature, new GArray(meshes().Select(value => Variant.From(value))), selected_bone, symmetry_axis, symmetry_offset, kind); var before = prepared["before"].AsGodotDictionary(); var after = prepared["after"].AsGodotDictionary();
        if (after.Count == 0) return "No weights needed changing.";
        var weak = GodotObject.WeakRef(Owner) ?? throw new InvalidOperationException("The model session is no longer available."); var handler = _bindings;
        handler.apply_weight_patch(Owner, after);
        var undo = Callable.From(() => handler.apply_weight_patch(weak, before)); var redo = Callable.From(() => handler.apply_weight_patch(weak, after));
        Owner.Call("custom_action", kind, undo, redo, before.Count); return "";
    }
    public void fill_region(Settings region, double amount)
    {
        var armature = rig(); if (armature == null || armature.Get("bones").AsGodotArray().Count == 0) return;
        if (region.Count == 0) { message = "Select vertices or faces before assigning weights."; return; }
        var prepared = new RigWeighting().prepare_region(Document,armature,selected_bone,region,amount);
        var before = prepared["before"].AsGodotDictionary(); var after = prepared["after"].AsGodotDictionary(); if (after.Count == 0) return;
        var weak = GodotObject.WeakRef(Owner) ?? throw new InvalidOperationException("The model session is no longer available."); var handler = _bindings;
        handler.apply_weight_patch(Owner,after);
        Owner.Call("custom_action","Assign selected vertex weights",Callable.From(()=>handler.apply_weight_patch(weak,before)),Callable.From(()=>handler.apply_weight_patch(weak,after)),before.Count);
    }
    public void detach()
    { var targets = meshes(); Action("Detach rig meshes", () => { foreach (var item in targets) { item.Set("binding", default(Variant)); item.Set("skin", default(Variant)); item.Set("skin_mesh", default(Variant)); item.Set("skeleton_id", ""); } }); }
}
