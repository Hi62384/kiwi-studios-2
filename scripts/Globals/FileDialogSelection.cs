using Godot;

/// <summary>One invocation of a file dialog; signal handlers are removed on completion.</summary>
public partial class FileDialogSelection : RefCounted
{
    public bool finished { get; private set; }
    public Variant result { get; private set; }
    private WeakRef? _dialog;
    public void initialize(FileDialog dialog)
    {
        _dialog = GodotObject.WeakRef(dialog);
        result = dialog.FileMode == FileDialog.FileModeEnum.OpenFiles ? new Godot.Collections.Array() : Variant.From("");
        dialog.Connect("dir_selected", new Callable(this, nameof(selected)));
        dialog.Connect("file_selected", new Callable(this, nameof(selected)));
        dialog.Connect("files_selected", new Callable(this, nameof(selected_files)));
        dialog.Connect("canceled", new Callable(this, nameof(cancel)));
        dialog.Connect("tree_exiting", new Callable(this, nameof(cancel)));
        dialog.RootSubfolder = "";
        dialog.Visible = true;
    }
    public void selected(string path) { result = path; finish(); }
    public void selected_files(string[] paths) { result = paths; finish(); }
    public void cancel() => finish();
    private void finish()
    {
        if (finished) return;
        finished = true;
        var dialog = _dialog?.GetRef().AsGodotObject();
        if (!GodotObject.IsInstanceValid(dialog)) return;
        foreach (var item in new[] { ("dir_selected", nameof(selected)), ("file_selected", nameof(selected)), ("files_selected", nameof(selected_files)), ("canceled", nameof(cancel)), ("tree_exiting", nameof(cancel)) })
        {
            var callback = new Callable(this, item.Item2);
            if (dialog!.IsConnected(item.Item1, callback)) dialog.Disconnect(item.Item1, callback);
        }
    }
}
