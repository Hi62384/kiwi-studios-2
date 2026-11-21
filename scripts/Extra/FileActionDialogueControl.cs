using Godot;

[GlobalClass]
public partial class FileActionDialogueControl : Panel
{
    public Button? copy_path_button { get; set; }
    public Button? copy_absolute_path_button { get; set; }
    public Button? rename_button { get; set; }
    public Button? duplicate_button { get; set; }
    public Button? delete_button { get; set; }
    public Button? show_in_file_manager_button { get; set; }
    public Button? open_in_external_program_button { get; set; }
    public Button? _create_new_button { get; set; }
    public Panel? _create_new_panel { get; set; }
    public Button? create_new_folder_button { get; set; }
    public Godot.Collections.Array<Button> _buttons_to_hide_external_panels { get; set; } = new();
    public Control? _file_system { get; set; }
    private readonly SharedControlOperations _operations = new();
    private bool _dismissPending;
    private ulong _dismissFrame;
    public override void _Ready()
    {
        copy_path_button = GetNode<Button>("VBoxContainer/Button2");
        copy_absolute_path_button = GetNode<Button>("VBoxContainer/Button9");
        rename_button = GetNode<Button>("VBoxContainer/Button10"); duplicate_button = GetNode<Button>("VBoxContainer/Button11");
        delete_button = GetNode<Button>("VBoxContainer/Button12"); show_in_file_manager_button = GetNode<Button>("VBoxContainer/Button13");
        open_in_external_program_button = GetNode<Button>("VBoxContainer/Button14");
        _create_new_button = GetNode<Button>("VBoxContainer/Button8"); _create_new_panel = GetNode<Panel>("CreateNewPanel");
        create_new_folder_button = GetNode<Button>("CreateNewPanel/VBoxContainer/Button8");
        _buttons_to_hide_external_panels = new() { copy_path_button, copy_absolute_path_button, rename_button, duplicate_button, delete_button, show_in_file_manager_button, open_in_external_program_button };
        _operations.dialogue_ready(this); SetProcess(false);
    }
    public void _hide_external_panels() => _operations.external_panels(this, false);
    public void _show_external_panels() => _operations.external_panels(this, true);
    public void _make_fully_visible_on_screen() => _operations.fully_visible(this);
    public override void _Input(InputEvent @event)
    {
        if (!_dismissPending && _operations.dismiss_dialogue())
        {
            _dismissPending = true; _dismissFrame = Engine.GetProcessFrames(); SetProcess(true);
        }
    }
    public override void _Process(double delta)
    {
        if (_dismissPending && Engine.GetProcessFrames() > _dismissFrame) { SetProcess(false); QueueFree(); }
    }
}
