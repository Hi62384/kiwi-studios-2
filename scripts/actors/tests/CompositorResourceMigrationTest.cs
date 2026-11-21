using Godot;
using System;
using System.Linq;

public partial class CompositorResourceMigrationTest : Node
{
    private const string Fixture = "res://scripts/actors/tests/fixtures/compositing_legacy_graph.tres";
    public override void _Ready()
    {
        try
        {
            if (OS.GetCmdlineUserArgs().Contains("--capture-legacy") || OS.GetCmdlineUserArgs().Contains("--capture-document"))
            {
                var document = GD.Load<GDScript>("res://Workspaces/CompositingWorkspace/compositing_document.gd").New().As<Resource>();
                var graph = GD.Load<GDScript>("res://Workspaces/CompositingWorkspace/composite_graph.gd").New().As<Resource>();
                var edge = GD.Load<GDScript>("res://Workspaces/CompositingWorkspace/composite_graph_connection.gd").New().As<Resource>();
                var oldNode = GD.Load<GDScript>("res://Workspaces/CompositingWorkspace/composite_graph_node.gd").New().As<Resource>();
                oldNode.Set("id", "legacy-node-A"); oldNode.Set("kind", "Color Grade"); oldNode.Set("position", new Vector2(123, 456)); oldNode.Set("exposed", true);
                oldNode.Set("settings", new Godot.Collections.Dictionary { ["exposure"] = 2.5, ["key_color"] = new Color(.2f, .4f, .8f, .5f), ["curves"] = new Godot.Collections.Dictionary { ["red"] = new Godot.Collections.Array { Vector2.Zero, new Vector2(.5f, .25f), Vector2.One } } });
                var nodes = graph.Get("nodes").AsGodotArray(); nodes.Add(oldNode); graph.Set("nodes", nodes);
                edge.Set("from_node", "source-A"); edge.Set("from_port", "image"); edge.Set("to_node", "output-B"); edge.Set("to_port", "image");
                var edges = graph.Get("connections").AsGodotArray(); edges.Add(edge); graph.Set("connections", edges);
                var graphs = document.Get("graphs").AsGodotArray(); graphs.Add(graph); document.Set("graphs", graphs);
                var group = document.Call("add_layer", 9, "Legacy Group").As<Resource>(); group.Set("id", "legacy-group");
                var child = document.Call("add_layer", 0, "Legacy Image").As<Resource>(); child.Set("id", "legacy-image"); child.Set("parent_id", "legacy-group");
                child.Set("position", new Vector2(23, 45)); child.Set("scale", new Vector2(2, .5f)); child.Set("rotation", .25); child.Set("anchor", new Vector2(.2f, .8f));
                child.Set("opacity", .4); child.Set("locked", true); child.Set("blend_mode", 8); child.Set("start_time", 1.0); child.Set("end_time", 4.0); child.Set("source_time_offset", .5); child.Set("playback_speed", 2.0);
                var image = Image.CreateEmpty(2, 1, false, Image.Format.Rgba8); image.Fill(new Color(.25f, .5f, .75f, .5f));
                child.Set("source_image", ImageTexture.CreateFromImage(image)); child.Set("mask_id", "legacy-mask"); child.Set("processing_graph_id", graph.Get("id"));
                child.Set("settings", new Godot.Collections.Dictionary { ["custom"] = "preserve-me", ["vector"] = new Vector3(1, 2, 3) });
                var effects = child.Get("effects").AsGodotArray(); effects.Add(new Godot.Collections.Dictionary { ["kind"] = "blur", ["radius"] = 7 }); child.Set("effects", effects);
                var children = group.Get("children").AsGodotArray(); children.Add(child); group.Set("children", children);
                var mask = document.Call("add_layer", 7, "Legacy Mask").As<Resource>(); mask.Set("id", "legacy-mask"); mask.Set("visible", false); mask.Set("source_image", child.Get("source_image"));
                var animation = document.Get("animation").AsGodotArray(); animation.Add(new Godot.Collections.Dictionary { ["layer_id"] = "legacy-image", ["property"] = "opacity", ["keys"] = new Godot.Collections.Array { new Godot.Collections.Dictionary { ["time"] = 1.0, ["value"] = .4 }, new Godot.Collections.Dictionary { ["time"] = 4.0, ["value"] = .8 } } }); document.Set("animation", animation);
                bool documentCapture = OS.GetCmdlineUserArgs().Contains("--capture-document");
                if (documentCapture)
                {
                    document.Set("title", "Legacy Document State"); document.Set("canvas_size", new Vector2I(320, 180)); document.Set("pixel_aspect_ratio", 1.25); document.Set("frame_rate", 30.0); document.Set("duration", 6.5);
                    document.Set("input_color_settings", new Godot.Collections.Dictionary { ["source_space"] = "sRGB" });
                    document.Set("output_color_settings", new Godot.Collections.Dictionary { ["transform"] = "sRGB", ["exposure"] = .5 });
                    document.Set("processing_settings", new Godot.Collections.Dictionary { ["cache"] = false, ["precision"] = "float32", ["tile_size"] = 64 });
                    document.Set("render_settings", new Godot.Collections.Dictionary { ["transparent"] = true, ["quality"] = "Final" });
                    document.Set("workspace_state", new Godot.Collections.Dictionary { ["mode"] = 1, ["scroll"] = new Vector2(20, 40), ["selected_id"] = "legacy-image" });
                    document.Set("cache_references", new Godot.Collections.Dictionary { ["example"] = "cache-marker" });
                    var media = document.Get("media_references").AsGodotArray(); media.Add("res://example-source.png"); document.Set("media_references", media);
                    document.Set("active_graph_id", graph.Get("id")); document.Set("solo_layer_id", "legacy-image");
                }
                string capturePath = documentCapture ? "res://scripts/actors/tests/fixtures/compositing_legacy_document.tres" : Fixture;
                if (ResourceSaver.Save(document, capturePath) != Error.Ok) throw new Exception("Legacy fixture save failed.");
                GD.Print("PASS pre-migration nested resource fixture captured");
            }
            else
            {
                using var editDocument = new CompositingDocument { canvas_size = new Vector2I(4, 2) };
                var editGroup = (CompositeLayer)editDocument.add_layer(9, "Editing group");
                var editChild = (CompositeLayer)editDocument.add_layer(1, "Editing child"); editChild.parent_id = editGroup.id; editGroup.children.Add(editChild);
                editDocument.set_layer_key(editChild.id, "opacity", 0, .25);
                var editGraph = new CompositeGraph(); var editSource = new CompositeGraphNode { kind = "Layer Source", settings = new Godot.Collections.Dictionary { ["layer_id"] = editChild.id } }; var editOutput = new CompositeGraphNode { kind = "Output" };
                editGraph.nodes.Add(editSource); editGraph.nodes.Add(editOutput); editGraph.output_node = editOutput.id;
                editGraph.connections.Add(new CompositeGraphConnection { from_node = editSource.id, from_port = "image", to_node = editOutput.id, to_port = "image" });
                editDocument.graphs.Add(editGraph); editChild.processing_graph_id = editGraph.id;
                using var edits = new CompositeWorkspaceEdits(); using var history = new CompositeWorkspaceHistory();
                var editSnapshot = (Resource)editDocument.Duplicate(true); var duplicated = edits.duplicate_layer(editDocument, editGroup.id);
                if (!duplicated["changed"].AsBool() || !history.commit(editDocument, editSnapshot)) throw new Exception("Native hierarchy duplication/history commit failed.");
                var duplicateGroup = (CompositeLayer)editDocument.layer(duplicated["selected_id"].AsString())!;
                var duplicateChild = editDocument.layers.Cast<CompositeLayer>().Single(layer => layer.parent_id == duplicateGroup.id);
                var duplicateGraph = editDocument.graphs.Cast<CompositeGraph>().Single(graph => graph.id == duplicateChild.processing_graph_id);
                if (duplicateGroup.children[0] != duplicateChild || !editDocument.has_layer_track(duplicateChild.id, "opacity")
                    || duplicateGraph.nodes[0].Get("settings").AsGodotDictionary()["layer_id"].AsString() != duplicateChild.id
                    || editSource.settings["layer_id"].AsString() != editChild.id) throw new Exception("Native duplication did not remap shared children, graph owners, or animation independently.");
                var undoDocument = (CompositingDocument)history.undo(editDocument)!;
                if (undoDocument.layers.Count != 2 || ((CompositingDocument)history.redo(undoDocument)!).layers.Count != 4) throw new Exception("Native history lost hierarchy undo/redo state.");
                edits.copy_layer(undoDocument, editGroup.id); using var pasteDocument = new CompositingDocument(); var pasted = edits.paste_layer(pasteDocument);
                if (!pasted["changed"].AsBool() || pasteDocument.layers.Count != 2 || pasteDocument.validate().Length != 0) throw new Exception("Native cross-document paste failed.");
                edits.delete_layer(pasteDocument, pasted["selected_id"].AsString());
                if (pasteDocument.layers.Count != 0 || pasteDocument.animation.Count != 0) throw new Exception("Native hierarchy deletion left owned layers or animation tracks.");
                using var previewTools = new CompositeWorkspacePreview(); using var largeDocument = new CompositingDocument { canvas_size = new Vector2I(4096, 2048) };
                var largeLayer = (CompositeLayer)largeDocument.add_layer(1, "Preview layer"); largeLayer.position = new Vector2(512, 128); largeLayer.scale = new Vector2(2, 1);
                largeDocument.set_layer_key(largeLayer.id, "position", 0, new Vector2(1024, 512));
                var smallDocument = (CompositingDocument)previewTools.prepare(largeDocument, 1024);
                if (smallDocument.canvas_size != new Vector2I(1024, 512) || smallDocument.layers[0].Get("position").AsVector2() != new Vector2(128, 32)
                    || smallDocument.sample_layer_value(largeLayer.id, "position", 0, Vector2.Zero).AsVector2() != new Vector2(256, 128)
                    || largeLayer.position != new Vector2(512, 128) || largeDocument.canvas_size != new Vector2I(4096, 2048)) throw new Exception("Native preview scaling changed source state or missed animation.");
                GD.Print("PASS native workspace hierarchy edits, shared references, graph ownership, history, paste/delete and animated preview scaling");
                using var graphActions = new CompositeWorkspaceGraphEdits(); using var graphDocument = new CompositingDocument();
                var graphLayer = (CompositeLayer)graphDocument.add_layer(1, "Graph layer");
                var ownedGraph = (CompositeGraph)graphActions.create_graph(graphDocument, graphLayer.id);
                if (graphActions.create_graph(graphDocument, graphLayer.id) != ownedGraph || graphDocument.graphs.Count != 1 || ownedGraph.validate().Length != 0) throw new Exception("Native graph creation did not reuse a valid owned graph.");
                var blurResult = graphActions.add_node(ownedGraph, "Blur", graphLayer.id); string blurId = blurResult["selected_id"].AsString();
                string sourceId = ownedGraph.nodes[0].Get("id").AsString(); string outputId = ownedGraph.output_node;
                long graphBeforeInvalid = graphDocument.signature();
                if (graphActions.connect_nodes(ownedGraph, sourceId, "image", outputId, "image")["changed"].AsBool()
                    || graphDocument.signature() != graphBeforeInvalid) throw new Exception("Rejected duplicate connection mutated graph state.");
                graphActions.disconnect_nodes(ownedGraph, sourceId, "image", outputId, "image");
                graphActions.connect_nodes(ownedGraph, sourceId, "image", blurId, "image");
                graphActions.connect_nodes(ownedGraph, blurId, "image", outputId, "image");
                var secondBlur = graphActions.add_node(ownedGraph, "Blur", graphLayer.id)["selected_id"].AsString();
                graphActions.connect_nodes(ownedGraph, blurId, "image", secondBlur, "image");
                graphActions.disconnect_nodes(ownedGraph, sourceId, "image", blurId, "image");
                long beforeCycle = graphDocument.signature();
                if (graphActions.connect_nodes(ownedGraph, secondBlur, "image", blurId, "image")["changed"].AsBool()
                    || graphDocument.signature() != beforeCycle) throw new Exception("Native cycle rejection left a graph mutation behind.");
                var duplicateBlur = graphActions.duplicate_node(ownedGraph, blurId)["selected_id"].AsString();
                ownedGraph.node(duplicateBlur)!.Get("settings").AsGodotDictionary()["radius"] = 99;
                if (ownedGraph.node(blurId)!.Get("settings").AsGodotDictionary()["radius"].AsInt32() != 2) throw new Exception("Duplicated node settings alias original settings.");
                using var graphHistory = new CompositeWorkspaceHistory(); var beforeDelete = (Resource)graphDocument.Duplicate(true);
                graphActions.delete_node(ownedGraph, blurId); graphHistory.commit(graphDocument, beforeDelete);
                if (graphLayer.processing_graph_id != ownedGraph.id || ownedGraph.connections.Any(edge => edge.Get("from_node").AsString() == blurId || edge.Get("to_node").AsString() == blurId)) throw new Exception("Node deletion lost graph assignment or left dangling connections.");
                var graphUndone = (CompositingDocument)graphHistory.undo(graphDocument)!;
                if (((CompositeGraph)graphUndone.graphs[0]).node(blurId) == null || ((CompositeGraph)((CompositingDocument)graphHistory.redo(graphUndone)!).graphs[0]).node(blurId) != null) throw new Exception("Graph edits failed history round-trip.");
                GD.Print("PASS native graph creation/reuse, transactional connection rejection, cycle prevention, independent duplication, deletion and undo/redo");
                using var animationActions = new CompositeWorkspaceAnimation(); using var animationDocument = new CompositingDocument();
                var animated = (CompositeLayer)animationDocument.add_layer(1, "Animated");
                animationActions.set_property(animationDocument, animated.id, "opacity", 0, .3);
                if (animated.opacity != .3 || animationDocument.has_layer_track(animated.id, "opacity")) throw new Exception("Unkeyed property edit unexpectedly inserted a track.");
                animationActions.key_transform(animationDocument, animated.id, 0);
                animationActions.set_property(animationDocument, animated.id, "opacity", 1, .9);
                if (Math.Abs(animationDocument.sample_layer_value(animated.id, "opacity", .5, 0).AsDouble() - .6) > .0001 || animated.opacity != .3) throw new Exception("Animated property edit changed the base value or interpolation.");
                animationActions.key_transform(animationDocument, animated.id, .5);
                if (Math.Abs(animationDocument.sample_layer_value(animated.id, "opacity", .5, 0).AsDouble() - .6) > .0001 || animationActions.key_transform(animationDocument, "missing", 0)) throw new Exception("Transform keying did not preserve sampled values or reject missing layers.");
                GD.Print("PASS native workspace unkeyed edits, animated edits, sampled transform keying and missing-layer guards");
                var legacyPresetScript = GD.Load<GDScript>("res://Workspaces/ModelWorkspace/rig/rig_preset.gd");
                using var legacyPreset = legacyPresetScript.New().As<Resource>();
                var presetBones = new Godot.Collections.Array<Godot.Collections.Dictionary> { new() { ["id"] = "preset-root", ["name"] = "Root", ["parent"] = -1, ["rest"] = new Transform3D(Basis.Identity, new Vector3(1, 2, 3)), ["metadata"] = new Godot.Collections.Dictionary { ["deform"] = false } } };
                legacyPreset.Set("title", "Legacy reusable rig"); legacyPreset.Set("bones", presetBones); legacyPreset.Set("metadata", new Godot.Collections.Dictionary { ["style"] = "mechanical", ["count"] = 7 });
                string presetBase = "res://.godot/verification/preset_migration_" + Guid.NewGuid().ToString("N");
                try
                {
                    if (ResourceSaver.Save(legacyPreset, presetBase + ".tres") != Error.Ok || ResourceSaver.Save(legacyPreset, presetBase + ".res") != Error.Ok) throw new Exception("Could not save legacy preset fixtures.");
                    byte[] originalPreset = FileAccess.GetFileAsBytes(presetBase + ".tres");
                    using var loadedPreset = ResourceLoader.Load<Resource>(presetBase + ".tres", "", ResourceLoader.CacheMode.Ignore);
                    using var binaryPreset = ResourceLoader.Load<Resource>(presetBase + ".res", "", ResourceLoader.CacheMode.Ignore);
                    if (loadedPreset is not RigPreset || !legacyPresetScript.Call("accepts", loadedPreset).AsBool() || !legacyPresetScript.Call("accepts", binaryPreset).AsBool()
                        || !originalPreset.AsSpan().SequenceEqual(FileAccess.GetFileAsBytes(presetBase + ".tres"))) throw new Exception("Legacy text/binary preset compatibility or source preservation failed.");
                    foreach (var preset in new[] { loadedPreset, binaryPreset })
                    {
                        if (preset.Get("title").AsString() != "Legacy reusable rig" || preset.Get("bones").AsGodotArray()[0].AsGodotDictionary()["rest"].AsTransform3D().Origin != new Vector3(1, 2, 3)
                            || preset.Get("metadata").AsGodotDictionary()["style"].AsString() != "mechanical") throw new Exception("Preset migration lost hierarchy, rest transform, title or metadata.");
                    }
                    if (ResourceSaver.Save(loadedPreset, presetBase + "_native.res") != Error.Ok) throw new Exception("Native preset binary save failed.");
                    using var nativeBinaryPreset = ResourceLoader.Load<Resource>(presetBase + "_native.res", "", ResourceLoader.CacheMode.Ignore);
                    if (nativeBinaryPreset is not RigPreset || nativeBinaryPreset.Get("bones").AsGodotArray().Count != 1) throw new Exception("Native binary preset round-trip failed.");
                    var thumbnail = GD.Load<GDScript>("res://scripts/Globals/file_operations.gd").Call("get_file_thumbnail", presetBase + ".tres").As<Texture2D>();
                    if (thumbnail == null || !thumbnail.ResourcePath.EndsWith("SkeletonRig.svg", StringComparison.Ordinal)) throw new Exception("Migrated preset lost its rig thumbnail.");
                    var picker = GD.Load<GDScript>("res://scripts/actors/core/actor_project_file_picker.gd").New().As<PopupPanel>();
                    try
                    {
                        picker.Set("project_root", ProjectSettings.GlobalizePath("res://.godot/verification")); picker.Set("allowed_extensions", new[] { "tres", "res" }); picker.Set("allowed_native_types", new[] { "KiwiRigPreset" });
                        if (!picker.Call("_path_allowed_uncached", ProjectSettings.GlobalizePath(presetBase + ".tres")).AsBool()
                            || !picker.Call("_path_allowed_uncached", ProjectSettings.GlobalizePath(presetBase + ".res")).AsBool()) throw new Exception("Project picker rejected native or binary legacy presets.");
                    }
                    finally { picker.Free(); }
                    GD.Print("PASS native rig preset creation, legacy text upgrade, binary legacy compatibility, source preservation and native binary round-trip");
                }
                finally { foreach (string suffix in new[] { ".tres", ".res", "_native.res" }) DirAccess.RemoveAbsolute(ProjectSettings.GlobalizePath(presetBase + suffix)); }
                using var evaluationDocument = new CompositingDocument { canvas_size = new Vector2I(2, 1), pixel_aspect_ratio = 1.5 };
                var evaluationLayer = (CompositeLayer)evaluationDocument.add_layer((int)CompositeLayer.Kind.Solid, "Cache test"); evaluationLayer.color = Colors.Red;
                using var nativeEvaluator = new CompositingEvaluator();
                var firstFrame = nativeEvaluator.evaluate(evaluationDocument, 0);
                evaluationLayer.color = Colors.Blue;
                var secondFrame = nativeEvaluator.evaluate(evaluationDocument, 0);
                if (firstFrame?.image == null || secondFrame?.image == null || !firstFrame.image.GetPixel(0, 0).IsEqualApprox(Colors.Red)
                    || !secondFrame.image.GetPixel(0, 0).IsEqualApprox(Colors.Blue) || secondFrame.pixel_aspect_ratio != 1.5f)
                    throw new Exception("Native evaluation cache invalidation or buffer metadata failed.");
                GD.Print("PASS native evaluator updates changed layers without manual cache clearing and preserves pixel aspect");
                using var unrelatedResource = new Resource();
                const string mentionedLegacyPath = "res://Workspaces/CompositingWorkspace/compositing_document.gd";
                unrelatedResource.SetMeta("description", mentionedLegacyPath);
                string unrelatedPath = "res://.godot/verification/resource_with_legacy_text.tres";
                if (ResourceSaver.Save(unrelatedResource, unrelatedPath) != Error.Ok) throw new Exception("Unrelated resource fixture save failed.");
                var unrelatedReloaded = ResourceLoader.Load<Resource>(unrelatedPath, "", ResourceLoader.CacheMode.Ignore);
                if (unrelatedReloaded.GetScript().VariantType != Variant.Type.Nil || unrelatedReloaded.GetMeta("description").AsString() != mentionedLegacyPath)
                    throw new Exception("Plain text mentioning a legacy script was incorrectly migrated.");
                GD.Print("PASS compatibility loader ignores ordinary text mentioning legacy paths");
                const string documentFixture = "res://scripts/actors/tests/fixtures/compositing_legacy_document.tres";
                byte[] documentBytes = Godot.FileAccess.GetFileAsBytes(documentFixture);
                var migratedDocument = ResourceLoader.Load<CompositingDocument>(documentFixture, "", ResourceLoader.CacheMode.Ignore);
                if (migratedDocument.title != "Legacy Document State" || migratedDocument.canvas_size != new Vector2I(320, 180)
                    || migratedDocument.pixel_aspect_ratio != 1.25 || migratedDocument.frame_rate != 30 || migratedDocument.duration != 6.5
                    || migratedDocument.workspace_state["scroll"].AsVector2() != new Vector2(20, 40) || migratedDocument.processing_settings["cache"].AsBool()
                    || migratedDocument.render_settings["quality"].AsString() != "Final" || migratedDocument.media_references.Count != 1
                    || migratedDocument.cache_references["example"].AsString() != "cache-marker") throw new Exception("Legacy document settings were lost.");
                if (Math.Abs(migratedDocument.sample_layer_value("legacy-image", "opacity", 2.5, 0d).AsDouble() - .6) > .000001)
                    throw new Exception("Legacy opacity key interpolation changed.");
                var snapshot = (CompositingDocument)migratedDocument.Duplicate(true);
                if (snapshot.signature() != migratedDocument.signature()) throw new Exception("An unchanged deep snapshot changed the document content signature.");
                long before = migratedDocument.signature();
                migratedDocument.graphs[0].Get("nodes").AsGodotArray()[0].As<CompositeGraphNode>().settings["exposure"] = 3.5;
                if (before == migratedDocument.signature()) throw new Exception("Graph settings do not affect the content signature.");
                migratedDocument.set_layer_key("legacy-image", "opacity", 2.5, .7);
                migratedDocument.set_layer_key("legacy-image", "opacity", 2.5, .9);
                if (migratedDocument.animation[0]["keys"].AsGodotArray().Count != 3 || Math.Abs(migratedDocument.sample_layer_value("legacy-image", "opacity", 2.5, 0d).AsDouble() - .9) > .000001)
                    throw new Exception("Updating a key inserted a duplicate time or sampled the wrong value.");
                string documentRoundtrip = "res://.godot/verification/migrated_document_roundtrip.tres";
                if (ResourceSaver.Save(migratedDocument, documentRoundtrip) != Error.Ok) throw new Exception("Document round-trip save failed.");
                var documentReloaded = ResourceLoader.Load<CompositingDocument>(documentRoundtrip, "", ResourceLoader.CacheMode.Ignore);
                if (documentReloaded.workspace_state["selected_id"].AsString() != "legacy-image" || documentReloaded.animation[0]["keys"].AsGodotArray().Count != 3
                    || !documentBytes.SequenceEqual(Godot.FileAccess.GetFileAsBytes(documentFixture))) throw new Exception("Document round-trip or immutable source check failed.");
                GD.Print("PASS C# document state, stable deep signatures, graph edit tracking, key replacement, and legacy round-trip");
                using var textureDocument = new CompositingDocument();
                var textureLayer = (CompositeLayer)textureDocument.add_layer(0, "Mutable image");
                using var texturePixels = Image.CreateEmpty(1, 1, false, Image.Format.Rgba8); texturePixels.Fill(Colors.Red);
                using var mutableTexture = ImageTexture.CreateFromImage(texturePixels); textureLayer.source_image = mutableTexture;
                if (DisplayServer.GetName() != "headless")
                {
                    long imageSignature = textureDocument.signature(); texturePixels.Fill(Colors.Blue); mutableTexture.Update(texturePixels);
                    if (imageSignature == textureDocument.signature()) throw new Exception("Texture updates did not invalidate the cached document content signature.");
                    GD.Print("PASS mutable texture updates invalidate content signatures");
                }
                else GD.Print("NOT RUN GPU texture Update signature check: requires a graphics renderer; verified separately in normal-renderer test");
                var binaryDocument = GD.Load<GDScript>("res://Workspaces/CompositingWorkspace/compositing_document.gd").New().As<Resource>();
                binaryDocument.Set("canvas_size", new Vector2I(2, 1)); binaryDocument.Set("duration", 2d);
                var binaryLayerForDocument = binaryDocument.Call("add_layer", 1, "Binary Document Layer").As<Resource>();
                string binaryLayerId = binaryLayerForDocument.Get("id").AsString();
                binaryDocument.Call("set_layer_key", binaryLayerId, "opacity", 0d, .2);
                binaryDocument.Call("set_layer_key", binaryLayerId, "opacity", 1d, .8);
                string binaryDocumentPath = "res://.godot/verification/legacy_document_binary.res";
                if (ResourceSaver.Save(binaryDocument, binaryDocumentPath) != Error.Ok) throw new Exception("Binary document save failed.");
                var binaryDocumentReloaded = ResourceLoader.Load<Resource>(binaryDocumentPath, "", ResourceLoader.CacheMode.Ignore);
                if (binaryDocumentReloaded.Call("validate").AsStringArray().Length != 0 || Math.Abs(binaryDocumentReloaded.Call("sample_layer_value", binaryLayerId, "opacity", .5, 0d).AsDouble() - .5) > .000001)
                    throw new Exception("Binary document C# validation/animation bridge failed.");
                var binaryRendered = nativeEvaluator.evaluate(binaryDocumentReloaded, .5);
                if (binaryRendered?.image == null || Math.Abs(binaryRendered.image.GetPixel(0, 0).A - .5) > .00001)
                    throw new Exception("Native evaluator could not render a legacy binary document through its compatibility schema.");
                using var hierarchyDocument = new CompositingDocument();
                var parentA = hierarchyDocument.add_layer(1, "A"); var parentB = hierarchyDocument.add_layer(9, "B");
                parentA.Set("parent_id", parentB.Get("id")); parentB.Set("parent_id", parentA.Get("id"));
                if (!hierarchyDocument.validate().Any(error => error.Contains("cycles", StringComparison.Ordinal))) throw new Exception("C# document parent cycles were not rejected.");
                parentB.Set("parent_id", "missing-parent");
                if (!hierarchyDocument.validate().Any(error => error.Contains("missing parent", StringComparison.Ordinal))) throw new Exception("Missing document parent was not diagnosed.");
                GD.Print("PASS binary document animation/validation bridge and C# hierarchy diagnostics");
                using var cycleGraph = new CompositeGraph();
                using var gradeA = new CompositeGraphNode { id = "grade-A", kind = "Color Grade" };
                using var gradeB = new CompositeGraphNode { id = "grade-B", kind = "Color Grade" };
                using var cycleOutput = new CompositeGraphNode { id = "cycle-output", kind = "Output" };
                cycleGraph.nodes.Add(gradeA); cycleGraph.nodes.Add(gradeB); cycleGraph.nodes.Add(cycleOutput); cycleGraph.output_node = cycleOutput.id;
                cycleGraph.connections.Add(new CompositeGraphConnection { from_node = gradeA.id, from_port = "output", to_node = gradeB.id, to_port = "image" });
                cycleGraph.connections.Add(new CompositeGraphConnection { from_node = gradeB.id, from_port = "output", to_node = gradeA.id, to_port = "image" });
                cycleGraph.connections.Add(new CompositeGraphConnection { from_node = gradeB.id, from_port = "output", to_node = cycleOutput.id, to_port = "image" });
                if (!cycleGraph.validate().Any(error => error.Contains("cycles", StringComparison.Ordinal))) throw new Exception("A valid-port graph cycle was not detected.");
                cycleGraph.connections.RemoveAt(1);
                if (!cycleGraph.compile_errors().Any(error => error.Contains("missing", StringComparison.Ordinal))) throw new Exception("Disconnected required input was not diagnosed.");
                cycleGraph.connections.Add(new CompositeGraphConnection { from_node = gradeA.id, from_port = "output", to_node = cycleOutput.id, to_port = "image" });
                if (!cycleGraph.validate().Any(error => error.Contains("only have one", StringComparison.Ordinal)) || cycleGraph.node(gradeA.id) != gradeA) throw new Exception("Duplicate input validation or node lookup failed.");
                GD.Print("PASS C# graph lookup, valid-port cycle rejection, missing inputs and duplicate-input diagnostics");
                var oldEdge = GD.Load<GDScript>("res://Workspaces/CompositingWorkspace/composite_graph_connection.gd").New().As<Resource>();
                oldEdge.Set("from_node", "binary-source"); oldEdge.Set("to_node", "binary-output");
                oldEdge.Set("from_port", "image"); oldEdge.Set("to_port", "image");
                var binaryGraph = GD.Load<GDScript>("res://Workspaces/CompositingWorkspace/composite_graph.gd").New().As<Resource>();
                var binarySource = GD.Load<GDScript>("res://Workspaces/CompositingWorkspace/composite_graph_node.gd").New().As<Resource>();
                binarySource.Set("id", "binary-source"); binarySource.Set("kind", "Solid Color");
                var binarySink = GD.Load<GDScript>("res://Workspaces/CompositingWorkspace/composite_graph_node.gd").New().As<Resource>();
                binarySink.Set("id", "binary-output"); binarySink.Set("kind", "Output");
                var binaryNodes = binaryGraph.Get("nodes").AsGodotArray(); binaryNodes.Add(binarySource); binaryNodes.Add(binarySink); binaryGraph.Set("nodes", binaryNodes);
                binaryGraph.Set("output_node", "binary-output");
                var binaryEdges = binaryGraph.Get("connections").AsGodotArray(); binaryEdges.Add(oldEdge); binaryGraph.Set("connections", binaryEdges);
                string binaryPath = "res://.godot/verification/legacy_connection_binary.res";
                if (ResourceSaver.Save(binaryGraph, binaryPath) != Error.Ok) throw new Exception("Binary compatibility fixture save failed.");
                var binaryReloaded = ResourceLoader.Load<Resource>(binaryPath, "", ResourceLoader.CacheMode.Ignore);
                if (binaryReloaded.Get("connections").AsGodotArray()[0].As<Resource>().Get("from_node").AsString() != "binary-source") throw new Exception("Binary legacy schema compatibility failed.");
                if (binaryReloaded.Call("validate").AsStringArray().Length != 0) throw new Exception("Legacy binary graph failed C# port validation.");
                GD.Print("PASS binary resources retain legacy connection data during migration");
                var oldLayer = GD.Load<GDScript>("res://Workspaces/CompositingWorkspace/composite_layer.gd").New().As<Resource>();
                oldLayer.Set("kind", 1); oldLayer.Set("opacity", .65); oldLayer.Set("position", new Vector2(17, 29));
                string binaryLayerPath = "res://.godot/verification/legacy_layer_binary.res";
                if (ResourceSaver.Save(oldLayer, binaryLayerPath) != Error.Ok) throw new Exception("Legacy binary layer fixture save failed.");
                var binaryLayer = ResourceLoader.Load<Resource>(binaryLayerPath, "", ResourceLoader.CacheMode.Ignore);
                if (binaryLayer.Get("position").AsVector2() != new Vector2(17, 29) || Math.Abs(binaryLayer.Get("opacity").AsDouble() - .65) > .000001
                    || binaryLayer.Call("validate").AsStringArray().Length != 0) throw new Exception("Legacy binary layer data or validation bridge failed.");
                GD.Print("PASS binary layer data and C# validation bridge");
                byte[] original = Godot.FileAccess.GetFileAsBytes(Fixture);
                var document = ResourceLoader.Load<Resource>(Fixture, "", ResourceLoader.CacheMode.Ignore);
                var graph = document.Get("graphs").AsGodotArray()[0].As<Resource>();
                if (graph is not CompositeGraph) throw new Exception("Legacy graph was not migrated to the C# graph resource.");
                var layers = document.Get("layers").AsGodotArray().Select(value => value.As<CompositeLayer>()).ToArray();
                var groupLayer = layers.Single(layer => layer.id == "legacy-group");
                var imageLayer = layers.Single(layer => layer.id == "legacy-image");
                var maskLayer = layers.Single(layer => layer.id == "legacy-mask");
                if (imageLayer.parent_id != groupLayer.id || groupLayer.children.Count != 1 || groupLayer.children[0] != imageLayer
                    || imageLayer.position != new Vector2(23, 45) || imageLayer.scale != new Vector2(2, .5f) || imageLayer.anchor != new Vector2(.2f, .8f)
                    || Math.Abs(imageLayer.rotation - .25) > .000001 || Math.Abs(imageLayer.opacity - .4) > .000001 || !imageLayer.locked || imageLayer.blend_mode != 8)
                    throw new Exception("Layer hierarchy or transform state was lost.");
                if (imageLayer.start_time != 1 || imageLayer.end_time != 4 || imageLayer.source_time_offset != .5 || imageLayer.playback_speed != 2
                    || imageLayer.mask_id != maskLayer.id || imageLayer.processing_graph_id != graph.Get("id").AsString()
                    || imageLayer.settings["custom"].AsString() != "preserve-me" || imageLayer.effects[0]["radius"].AsInt32() != 7)
                    throw new Exception("Layer timing, effect settings, or resource references were lost.");
                if (imageLayer.source_image == null || imageLayer.source_image.GetImage().GetSize() != new Vector2I(2, 1) || maskLayer.visible)
                    throw new Exception("Embedded source image or mask state was lost.");
                var animation = document.Get("animation").AsGodotArray()[0].AsGodotDictionary();
                if (animation["layer_id"].AsString() != imageLayer.id || animation["keys"].AsGodotArray().Count != 2)
                    throw new Exception("Layer animation references were lost.");
                using var invalidLayer = new CompositeLayer { kind = (int)CompositeLayer.Kind.Video, opacity = 2 };
                if (invalidLayer.validate().Length < 2 || (int)CompositeLayer.Kind.Group != 9 || (int)CompositeLayer.Blend.Screen != 8)
                    throw new Exception("C# layer validation or serialized enum values changed.");
                GD.Print("PASS C# layer hierarchy, transforms, timing, embedded image, effects, mask/graph links and animation references");
                var edge = graph.Get("connections").AsGodotArray()[0].As<Resource>();
                var node = graph.Get("nodes").AsGodotArray()[0].As<CompositeGraphNode>();
                if (node.id != "legacy-node-A" || node.kind != "Color Grade" || node.position != new Vector2(123, 456) || !node.exposed
                    || node.settings["exposure"].AsDouble() != 2.5 || node.settings["curves"].AsGodotDictionary()["red"].AsGodotArray()[1].AsVector2() != new Vector2(.5f, .25f))
                    throw new Exception("Legacy node settings, placement, or nested curves were lost.");
                if (edge is not CompositeGraphConnection connection || connection.from_node != "source-A" || connection.to_node != "output-B"
                    || connection.from_port != "image" || connection.to_port != "image") throw new Exception("Legacy nested connection did not retain its data and C# type.");
                string roundtrip = "res://.godot/verification/migrated_compositor_roundtrip.tres";
                if (ResourceSaver.Save(document, roundtrip) != Error.Ok) throw new Exception("Migrated document save failed.");
                var reloaded = ResourceLoader.Load<Resource>(roundtrip, "", ResourceLoader.CacheMode.Ignore);
                var reloadedGraph = reloaded.Get("graphs").AsGodotArray()[0].As<Resource>();
                var reloadedEdge = reloadedGraph.Get("connections").AsGodotArray()[0].As<CompositeGraphConnection>();
                if (reloadedEdge.from_node != "source-A") throw new Exception("Round-trip lost connection data.");
                var reloadedNode = reloadedGraph.Get("nodes").AsGodotArray()[0].As<CompositeGraphNode>();
                if (!reloadedNode.settings["key_color"].AsColor().IsEqualApprox(new Color(.2f, .4f, .8f, .5f))) throw new Exception("Round-trip lost the node's color setting.");
                var reloadedImage = reloaded.Get("layers").AsGodotArray().Select(value => value.As<CompositeLayer>()).Single(layer => layer.id == "legacy-image");
                if (reloadedImage.source_image == null || reloadedImage.source_image.GetImage().GetSize() != new Vector2I(2, 1)
                    || reloadedImage.mask_id != "legacy-mask" || reloadedImage.effects.Count != 1) throw new Exception("Layer round-trip lost image/effect/mask data.");
                if (!original.SequenceEqual(Godot.FileAccess.GetFileAsBytes(Fixture))) throw new Exception("Compatibility loading modified the original file.");
                if (Godot.FileAccess.GetFileAsString(roundtrip).Contains(".godot/migration/", StringComparison.Ordinal)) throw new Exception("Saved resource leaks temporary cache dependencies.");
                GD.Print("PASS legacy nested connections load as C# and round-trip without data loss");
            }
            GetTree().Quit();
        }
        catch (Exception exception) { GD.PushError(exception.ToString()); GetTree().Quit(1); }
    }
}
