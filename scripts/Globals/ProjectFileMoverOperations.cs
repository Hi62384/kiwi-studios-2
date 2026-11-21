using Godot;
public partial class ProjectFileMoverOperations : RefCounted
{
    private readonly FileOperationsNative _files = new();
    private readonly ProjectFileSelectionOperations _selection = new();
    private static Control Browser(Node owner) => owner.Get("file_system").As<Control>();
    private static TextureRect Icon(Node owner) => owner.Get("folder_mover_icon").As<TextureRect>();
    public void set_hovered(Node owner, Control? button) => owner.Set("_hovered_expandable_button", button == null ? default(Variant) : Variant.From(button));
    public void start(Node owner) { owner.Set("_moving_selected_files", true); position_icon(owner); Icon(owner).Visible = true; }
    public void stop(Node owner) { owner.Set("_moving_selected_files", false); Icon(owner).Visible = false; move_to_hovered(owner); }
    public void move_to_hovered(Node owner)
    {
        var hovered = owner.Get("_hovered_expandable_button").As<Control>(); if (!GodotObject.IsInstanceValid(hovered) || hovered!.IsQueuedForDeletion()) return;
        var browser = Browser(owner); var paths = new Godot.Collections.Array<string>(); foreach (var value in _selection.top_selected_files(browser.Get("files_selector").As<Node>())) paths.Add(value.AsGodotObject().GetMeta("path").AsString());
        browser.Get("file_system_callable_actions").As<Node>().Call("move_files", _files.get_lowest_directory(hovered.GetMeta("path").AsString()), paths);
    }
    public void position_icon(Node owner) => Icon(owner).Position = Browser(owner).GetGlobalMousePosition();
    public void process(Node owner) { if (!owner.Get("_moving_selected_files").AsBool()) return; position_icon(owner); if (Input.IsActionJustReleased("left_click")) stop(owner); }
}
