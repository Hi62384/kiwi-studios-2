using Godot;

public partial class CSharpMigrationSmoke : Node
{
    public override async void _Ready()
    {
        var scene = GD.Load<PackedScene>("res://scenes/ProjectManager/ProjectManagerProjectDisplay.tscn");
        var panel = scene.Instantiate<Panel>();
        AddChild(panel);
        bool valid = panel is ProjectManagerProjectDisplay
            && panel.Get("project_name").AsGodotObject() is Label
            && panel.Get("project_path").AsGodotObject() is Label
            && panel.Get("button").AsGodotObject() is Button
            && panel.Get("selected_cover").AsGodotObject() is ColorRect;
        using var filters = new CompositePixelFilters();
        using var sourceImage = Image.CreateEmpty(2, 1, false, Image.Format.Rgbaf);
        sourceImage.SetPixel(0, 0, new Color(2f, .5f, .25f, .4f));
        sourceImage.SetPixel(1, 0, new Color(0, 1, 0, 1));
        using var graded = filters.grade(sourceImage, new Godot.Collections.Dictionary { ["exposure"] = 1f });
        bool filterParity = graded.GetPixel(0, 0).IsEqualApprox(new Color(4f, 1f, .5f, .4f));
        using var keyed = filters.chroma_key(sourceImage, new Godot.Collections.Dictionary { ["spill"] = 0f });
        filterParity &= keyed.GetPixel(1, 0).A < .001f && keyed.GetPixel(0, 0).A > .39f;
        GD.Print(filterParity ? "PASS C# grading preserves HDR/alpha and chroma defaults remove green" : "FAIL C# grading/keying parity");
        valid &= filterParity;
        using var placed = filters.transform(sourceImage, new Vector2I(5, 3), new Vector2(1, 1), 0, Vector2.One, Vector2.Zero, false);
        bool placement = placed.GetPixel(1, 1).IsEqualApprox(sourceImage.GetPixel(0, 0))
            && placed.GetPixel(2, 1).IsEqualApprox(sourceImage.GetPixel(1, 0)) && placed.GetPixel(0, 0).A == 0;
        GD.Print(placement ? "PASS C# transform places source pixels without modifying HDR or alpha" : "FAIL C# transform placement");
        valid &= placement;
        using var buffer = new CompositeBuffer { image = sourceImage, frame_time = 1.25, source_identity = "original", depth_units = "meters", camera_reference = "camera-A", pixel_aspect_ratio = 1.5f };
        using var duplicateBuffer = buffer.duplicate_buffer();
        duplicateBuffer.image!.SetPixel(0, 0, Colors.Black);
        bool bufferCopy = duplicateBuffer.is_valid() && buffer.image!.GetPixel(0, 0).R == 2f && duplicateBuffer.frame_time == 1.25
            && duplicateBuffer.depth_units == "meters" && duplicateBuffer.camera_reference == "camera-A" && duplicateBuffer.pixel_aspect_ratio == 1.5f;
        GD.Print(bufferCopy ? "PASS C# buffer cloning preserves metadata and independently copies pixels" : "FAIL C# buffer cloning");
        valid &= bufferCopy;
        var curve = new CompositeCurveEditor(); AddChild(curve); curve.Size = new Vector2(260, 190);
        int finishedEdits = 0; Godot.Collections.Array? editedPoints = null;
        curve.edit_finished += () => finishedEdits++;
        curve.points_changed += values => editedPoints = values;
        curve._GuiInput(new InputEventMouseButton { ButtonIndex = MouseButton.Left, Pressed = true, Position = new Vector2(130, 95) });
        curve._GuiInput(new InputEventMouseMotion { Position = new Vector2(156, 57) });
        curve._GuiInput(new InputEventMouseButton { ButtonIndex = MouseButton.Left, Pressed = false, Position = new Vector2(156, 57) });
        bool curveDrag = finishedEdits == 1 && editedPoints?.Count == 3 && editedPoints[1].AsVector2().IsEqualApprox(new Vector2(.6f, .7f));
        GD.Print(curveDrag ? "PASS C# curve drag publishes the moved point and one completed edit" : "FAIL C# curve pointer interaction");
        valid &= curveDrag; curve.QueueFree();
        GD.Print(valid ? "PASS C# panel scene and script-facing properties" : "FAIL C# panel interoperability");
        string folder = "res://.godot/verification/csharp_project_" + System.Guid.NewGuid().ToString("N");
        DirAccess.MakeDirRecursiveAbsolute(ProjectSettings.GlobalizePath(folder));
        var controller = new ProjectManagerController { ListingPathOverride = folder.PathJoin("listing.tres") };
        AddChild(controller);
        string original = folder.PathJoin("original");
        string duplicate = folder.PathJoin("duplicate");
        controller.create_project(original, "Original");
        controller.rename_project(original, "Renamed");
        controller.duplicate_project(original, duplicate, "Duplicate");
        string copiedFile = controller.get_project_file_path_in_project_dir(duplicate);
        bool workflow = copiedFile.Length > 0 && GD.Load<Resource>(copiedFile).Get("project_name").AsString() == "Duplicate";
        controller.unalive_project_directory(original, false);
        controller.unalive_project_directory(duplicate, false);
        workflow &= controller.get_saved_projects().Get("project_paths").AsGodotArray().Count == 0;
        GD.Print(workflow ? "PASS C# project create/rename/duplicate/remove with isolated listing" : "FAIL C# project workflow");
        valid &= workflow;
        var managerScene = GD.Load<PackedScene>("res://scenes/ProjectManager/ProjectManager.tscn").Instantiate<ProjectManagerUi>();
        managerScene.GetNode<ProjectManagerController>("ProjectManager").ListingPathOverride = folder.PathJoin("ui-listing.tres");
        AddChild(managerScene);
        managerScene.GetNode<Button>("%CreateProjectButton").EmitSignal(Button.SignalName.Pressed);
        await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
        var chooser = managerScene.GetNode<Control>("CreateProjectPanel");
        chooser.Get("close_button").As<Button>().EmitSignal(Button.SignalName.Pressed);
        await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
        await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
        bool canceled = !chooser.Visible && !managerScene.GetNode<ColorRect>("%ScreenCover").Visible;
        GD.Print(canceled ? "PASS C# project-manager dialog cancellation clears modal cover" : "FAIL C# dialog cancellation");
        valid &= canceled;
        string uiProject = folder.PathJoin("ui-project");
        managerScene.GetNode<Button>("%CreateProjectButton").EmitSignal(Button.SignalName.Pressed);
        chooser.GetNode<LineEdit>("VBoxContainer/LineEdit").Text = "UI Created";
        chooser.GetNode<LineEdit>("VBoxContainer/HBoxContainer3/LineEdit2").Text = uiProject;
        chooser.Get("select_button").As<Button>().EmitSignal(Button.SignalName.Pressed);
        await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
        await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
        bool created = managerScene.project_manager.get_project_file_path_in_project_dir(uiProject).Length > 0;
        GD.Print(created ? "PASS C# parameter mappings create a project through the UI" : "FAIL C# parameter mapping confirmation");
        valid &= created;
        managerScene.project_manager.unalive_project_directory(uiProject, false);
        DirAccess.RemoveAbsolute(ProjectSettings.GlobalizePath(folder.PathJoin("ui-listing.tres")));
        var bridgeProject = new Project("Bridge test");
        StaticData.set_loaded_project(bridgeProject);
        managerScene.QueueFree();
        controller.QueueFree();
        DirAccess.RemoveAbsolute(ProjectSettings.GlobalizePath(folder.PathJoin("listing.tres")));
        DirAccess.RemoveAbsolute(ProjectSettings.GlobalizePath(folder));
        panel.QueueFree();
        GetTree().Quit(valid ? 0 : 1);
    }
}
