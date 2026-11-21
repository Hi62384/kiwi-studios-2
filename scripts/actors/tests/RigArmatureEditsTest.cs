using Godot;
using System;

public partial class RigArmatureEditsTest : Node
{
    public override void _Ready()
    {
        try
        {
            using var session = GD.Load<GDScript>("res://Workspaces/ModelWorkspace/model_session.gd").New().As<RefCounted>();
            var component = session.Call("add", "Cylinder", new Godot.Collections.Dictionary { ["height"] = 4.0, ["radius"] = .3 }).As<Resource>();
            using var editor = GD.Load<GDScript>("res://Workspaces/ModelWorkspace/rig/rig_editor.gd").New(session).As<RefCounted>();
            var rig = editor.Call("create", "Tentacle", 4).As<Resource>(); string rigId = rig.Get("id").AsString(), componentId = component.Get("id").AsString();
            if (editor.Call("bind", "Smooth", 4).AsString().Length > 0) throw new Exception("Rig fixture could not bind.");
            Resource Find(string id) => session.Get("document").As<Resource>().Call("component", id).As<Resource>();
            Vector3[] Points() => Find(componentId).Get("binding").As<Resource>().Call("deformed_points", Find(rigId), 0).AsVector3Array();
            Vector3[] before = Points(); editor.Set("selected_bone", 0); editor.Call("insert_joint");
            var insertedRig = Find(rigId); var binding = Find(componentId).Get("binding").As<Resource>(); var after = Points();
            if (insertedRig.Get("bones").AsGodotArray().Count != 5 || binding.Call("validate", insertedRig).AsStringArray().Length != 0 || before.Length != after.Length) throw new Exception("Joint insertion lost the rig or valid mesh binding.");
            for (int i = 0; i < before.Length; i++) if (before[i].DistanceTo(after[i]) > .0001) throw new Exception("Joint insertion changed the neutral mesh shape.");
            session.Call("undo"); if (Find(rigId).Get("bones").AsGodotArray().Count != 4) throw new Exception("Joint insertion did not undo as one action.");
            session.Call("redo"); if (Find(rigId).Get("bones").AsGodotArray().Count != 5) throw new Exception("Joint insertion did not redo.");
            editor.Set("selected_bone", 4); editor.Call("delete_bone");
            if (Find(rigId).Get("bones").AsGodotArray().Count != 4 || Find(componentId).Get("binding").As<Resource>().Call("validate", Find(rigId)).AsStringArray().Length != 0) throw new Exception("Deleting the inserted joint left invalid bone mappings.");
            GD.Print("PASS native joint insertion preserves neutral geometry and bindings, undo/redo is atomic, and deleting the joint restores valid mappings");
            var region = new Godot.Collections.Dictionary { ["vertex"] = new Godot.Collections.Dictionary { ["id"] = componentId,["surface"] = 0,["vertex"] = 0 } };
            editor.Set("selected_bone",2); var nativeEditor=editor.Get("_native").As<RigEditor>();
            long beforeRegion=Find(componentId).Get("binding").As<Resource>().Call("signature").AsInt64(); nativeEditor.fill_region(region,.37);
            long afterRegion=Find(componentId).Get("binding").As<Resource>().Call("signature").AsInt64();
            if(beforeRegion==afterRegion) throw new Exception("Region assignment did not alter weights.");
            session.Call("undo"); if(Find(componentId).Get("binding").As<Resource>().Call("signature").AsInt64()!=beforeRegion) throw new Exception("Region assignment did not undo exactly.");
            session.Call("redo"); if(Find(componentId).Get("binding").As<Resource>().Call("signature").AsInt64()!=afterRegion) throw new Exception("Region assignment did not redo exactly.");
            GD.Print("PASS native selected-region weight assignment changes weights and supports exact undo/redo");
            long beforeCleanup = Find(componentId).Get("binding").As<Resource>().Call("signature").AsInt64(); editor.Set("selected_bone", 0);
            if (editor.Call("cleanup", "Clear influence").AsString().Length > 0) throw new Exception("Cleanup fixture did not change weights.");
            long afterCleanup = Find(componentId).Get("binding").As<Resource>().Call("signature").AsInt64();
            if (beforeCleanup == afterCleanup) throw new Exception("Cleanup did not alter the weight data.");
            editor.Dispose(); session.Call("undo");
            if (Find(componentId).Get("binding").As<Resource>().Call("signature").AsInt64() != beforeCleanup) throw new Exception("Native cleanup callback failed undo after the editor closed.");
            session.Call("redo");
            if (Find(componentId).Get("binding").As<Resource>().Call("signature").AsInt64() != afterCleanup) throw new Exception("Native cleanup callback failed redo after the editor closed.");
            GD.Print("PASS native cleanup history restores exact weights after the editor closes");
            using var reopenedEditor = GD.Load<GDScript>("res://Workspaces/ModelWorkspace/rig/rig_editor.gd").New(session).As<RefCounted>();
            using var oversized = new ArrayMesh(); var arrays = new Godot.Collections.Array(); arrays.Resize((int)Mesh.ArrayType.Max); arrays[(int)Mesh.ArrayType.Vertex] = new Vector3[RigWeighting.MaxVertices + 2];
            oversized.AddSurfaceFromArrays(Mesh.PrimitiveType.Triangles, arrays); var target = Find(componentId); target.Set("binding", default(Variant)); target.Set("skin_mesh", oversized);
            long revision = session.Get("revision").AsInt64(); string refused = reopenedEditor.Call("bind", "Smooth", 4).AsString();
            if (!refused.StartsWith("Weighting limit:", StringComparison.Ordinal) || session.Get("revision").AsInt64() != revision || target.Get("binding").As<Resource>() != null || target.Get("skin_mesh").As<Mesh>().GetInstanceId() != oversized.GetInstanceId()) throw new Exception("Weighting budget refusal changed the source or history.");
            GD.Print("PASS native weighting budget refusal preserves the source mesh and undo history"); GetTree().Quit();
        }
        catch (Exception error) { GD.PushError(error.ToString()); GetTree().Quit(1); }
    }
}
