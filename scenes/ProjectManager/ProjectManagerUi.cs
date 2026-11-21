using Godot;
using System;
using System.Threading.Tasks;
using Dictionary = Godot.Collections.Dictionary;

public partial class ProjectManagerUi : Control
{
    [Export] public ProjectManagerController project_manager { get; set; } = null!;
    [Export] public ProjectManagerProjectDisplay? selected_panel_display { get; set; }
    private VBoxContainer _projects = null!;
    private LineEdit _filter = null!;
    private ColorRect _cover = null!;

    public override void _Ready()
    {
        project_manager = GetNode<ProjectManagerController>("%ProjectManager");
        _projects = GetNode<VBoxContainer>("%ProjectDisplayContainer");
        _filter = GetNode<LineEdit>("%FilterProjectLineEdit");
        _cover = GetNode<ColorRect>("%ScreenCover");
        project_manager.saved_projects_updated += update_displayed_projects;
        _filter.TextChanged += _ => update_displayed_projects();
        GetNode<Button>("%CreateProjectButton").Pressed += () => Run(CreateProject);
        GetNode<Button>("%OpenProjectButton").Pressed += () => Run(OpenProject);
        GetNode<Button>("%RenameProjectButton").Pressed += () => Run(RenameProject);
        GetNode<Button>("%DuplicateProjectButton").Pressed += () => Run(DuplicateProject);
        GetNode<Button>("%RemoveProjectButton").Pressed += () => Run(RemoveProject);
        GetNode<Button>("%OpenInFileManagerButton").Pressed += () =>
        {
            if (!selected_panel_display_is_invalid()) OS.ShellOpen(selected_panel_display!.project_path.Text);
        };
        update_displayed_projects();
    }

    private async void Run(Func<Task> action)
    {
        _cover.Visible = true;
        try { await action(); }
        catch (Exception error) { GD.PushError($"Project operation failed: {error.Message}"); }
        finally { if (IsInstanceValid(_cover)) _cover.Visible = false; }
    }

    public bool selected_panel_display_is_invalid() => selected_panel_display == null
        || !IsInstanceValid(selected_panel_display) || selected_panel_display.error_cover.Visible;

    public void update_displayed_projects()
    {
        selected_panel_display = null;
        foreach (Node child in _projects.GetChildren()) { _projects.RemoveChild(child); child.QueueFree(); }
        var scene = GD.Load<PackedScene>("res://scenes/ProjectManager/ProjectManagerProjectDisplay.tscn");
        var icon = GD.Load<Texture2D>("res://icon.svg");
        foreach (Variant entry in project_manager.get_saved_projects().Get("project_paths").AsGodotArray())
        {
            string path = entry.AsString();
            string resourcePath = project_manager.get_project_file_path_in_project_dir(path);
            Resource? project = resourcePath.Length > 0 ? GD.Load<Resource>(resourcePath) : null;
            string name = project?.Get("project_name").AsString() ?? "MISSING PROJECT";
            if (_filter.Text.Length > 0 && (project == null || !name.Contains(_filter.Text))) continue;
            var panel = scene.Instantiate<ProjectManagerProjectDisplay>(); _projects.AddChild(panel);
            panel.project_path.Text = path; panel.project_name.Text = name; panel.texture_rect.Texture = icon;
            panel.error_cover.Visible = project == null;
            panel.button.Pressed += () =>
            {
                if (selected_panel_display == panel && project != null)
                {
                    StaticData.set_loaded_project((Project)project);
                    GetTree().ChangeSceneToFile("res://scenes/Main.tscn");
                    return;
                }
                if (selected_panel_display != null && IsInstanceValid(selected_panel_display)) selected_panel_display.selected_cover.Visible = false;
                selected_panel_display = panel; panel.selected_cover.Visible = true;
            };
        }
    }

    private async Task<Dictionary> SelectParameters(Control dialog)
    {
        var state = new Dictionary { ["finished"] = false, ["badboy"] = false };
        dialog.Set("_state", state); dialog.Visible = true;
        try
        {
            while (!state["finished"].AsBool())
            {
                await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
                if (!IsInstanceValid(dialog) || state["badboy"].AsBool()) return new Dictionary();
            }
            var result = new Dictionary();
            foreach (Variant value in dialog.Get("mappings").AsGodotArray())
            {
                var mapping = value.As<Resource>();
                result[mapping.Get("tag")] = dialog.GetNode(mapping.Get("node").AsNodePath()).Get(mapping.Get("property_name").AsStringName());
            }
            return result;
        }
        finally { if (IsInstanceValid(dialog)) dialog.Visible = false; }
    }

    private async Task CreateProject()
    {
        var dialog = GetNode<Control>("CreateProjectPanel");
        dialog.Get("create_new_folder").As<CheckButton>().ButtonPressed = false;
        var values = await SelectParameters(dialog);
        if (values.Count > 0) project_manager.create_project(values["DirectorySavePath"].AsString(), values["ProjectName"].AsString());
    }

    private async Task RenameProject()
    {
        if (selected_panel_display_is_invalid()) return;
        string path = selected_panel_display!.project_path.Text;
        GetNode<LineEdit>("RenameProjectPanel/VBoxContainer/LineEdit").Text = selected_panel_display.project_name.Text;
        var values = await SelectParameters(GetNode<Control>("RenameProjectPanel"));
        if (values.Count > 0) project_manager.rename_project(path, values["NewProjectName"].AsString());
    }

    private async Task DuplicateProject()
    {
        if (selected_panel_display_is_invalid()) return;
        string path = selected_panel_display!.project_path.Text;
        var dialog = GetNode<Control>("DuplicateProjectPanel");
        dialog.Get("create_new_folder").As<CheckButton>().ButtonPressed = false;
        var values = await SelectParameters(dialog);
        if (values.Count > 0) project_manager.duplicate_project(path, values["SavePath"].AsString(), values["ProjectName"].AsString());
    }

    private async Task OpenProject()
    {
        var dialog = GetNode<FileDialog>("FileDialog");
        var result = new TaskCompletionSource<string>();
        void Selected(string path) => result.TrySetResult(path);
        void Canceled() => result.TrySetResult("");
        dialog.FileSelected += Selected; dialog.DirSelected += Selected; dialog.Canceled += Canceled;
        try
        {
            dialog.PopupCentered(); string path = await result.Task;
            if (project_manager.get_project_file_path_in_project_dir(path).Length > 0) project_manager.add_project_to_listing(path);
        }
        finally { dialog.FileSelected -= Selected; dialog.DirSelected -= Selected; dialog.Canceled -= Canceled; }
    }

    private async Task RemoveProject()
    {
        if (selected_panel_display == null || !IsInstanceValid(selected_panel_display)) return;
        var dialog = GetNode<DeleteProjectPanel>("DeleteProjectPanel");
        dialog.display(); await ToSignal(dialog, DeleteProjectPanel.SignalName.did_something);
    }
}
