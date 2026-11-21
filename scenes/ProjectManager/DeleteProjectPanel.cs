using Godot;

public partial class DeleteProjectPanel : Panel
{
    [Signal] public delegate void did_somethingEventHandler();
    public override void _Ready()
    {
        GetNode<Button>("VBoxContainer/HBoxContainer/Button").Pressed += do_something;
        GetNode<Button>("VBoxContainer/RemoveFromListing").Pressed += () => Remove(false, true);
        GetNode<Button>("VBoxContainer/ToRecyleBinButton").Pressed += () => Remove(true, false);
        GetNode<Button>("VBoxContainer/DeleteButton").Pressed += () => Remove(false, false);
    }

    private GodotObject? Selected => GetParent().Get("selected_panel_display").AsGodotObject();
    private void Remove(bool recycle, bool listingOnly)
    {
        var selected = Selected;
        if (selected == null || !GodotObject.IsInstanceValid(selected)) { do_something(); return; }
        string path = selected.Get("project_path").As<Label>().Text;
        var manager = GetParent().Get("project_manager").As<ProjectManagerController>();
        if (listingOnly) manager.remove_project_from_listing(path);
        else manager.unalive_project_directory(path, recycle);
        do_something();
    }

    public void display()
    {
        var selected = Selected;
        if (selected == null || !GodotObject.IsInstanceValid(selected)) return;
        GetNode<Label>("VBoxContainer/Label").Text = selected.Get("project_name").As<Label>().Text;
        Visible = true;
    }

    public void do_something() { Visible = false; EmitSignal(SignalName.did_something); }
}
