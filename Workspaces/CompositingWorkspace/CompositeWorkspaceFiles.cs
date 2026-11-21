using Godot;
using Settings = Godot.Collections.Dictionary;

public partial class CompositeWorkspaceFiles : RefCounted
{
    private static bool IsDocument(Resource? value) => value is CompositingDocument || value?.GetScript().As<Script>()?.ResourcePath == "res://Workspaces/CompositingWorkspace/compositing_document.gd";

    public Settings open_source(Variant source)
    {
        Resource? document = null; string path = ""; bool failed = false;
        if (source.VariantType == Variant.Type.String)
        {
            path = source.AsString();
            document = ResourceLoader.Exists(path) ? ResourceLoader.Load(path, "", ResourceLoader.CacheMode.Ignore) : null;
            if (!IsDocument(document)) { document = null; failed = true; path = ""; }
        }
        else if (source.VariantType == Variant.Type.Object && source.AsGodotObject() is Resource candidate && IsDocument(candidate)) document = candidate;
        document ??= new CompositingDocument();
        return new Settings { ["document"] = document, ["path"] = path, ["source"] = failed ? Variant.From(document) : source, ["dirty"] = failed || source.VariantType != Variant.Type.String, ["failed"] = failed };
    }

    public Resource ensure_document(Resource? document)
    {
        document ??= new CompositingDocument();
        if (document.Get("layers").AsGodotArray().Count == 0)
        {
            using var rules = new CompositingDocument(); var background = rules.add_layer_resource(document, 1, "Background");
            background.Set("color", new Color(0, 0, 0, 0));
        }
        return document;
    }

    public Settings save_document(Resource document, string destination)
    {
        using var rules = new CompositingDocument(); var errors = rules.validate_resource(document);
        if (errors.Length > 0) return new Settings { ["success"] = false, ["message"] = "Cannot save: " + string.Join("; ", errors) };
        document.ResourceName = document.Get("title").AsString();
        Error error = ResourceSaver.Save(document, destination);
        return new Settings { ["success"] = error == Error.Ok, ["message"] = error == Error.Ok ? "Saved  ·  " + destination : "Save failed: " + error };
    }

    public FileDialog save_dialog(Node parent, string fileName)
    {
        var dialog = new FileDialog { FileMode = FileDialog.FileModeEnum.SaveFile, Access = FileDialog.AccessEnum.Resources, CurrentFile = fileName };
        dialog.AddFilter("*.tres", "Kiwi Compositing Document"); parent.AddChild(dialog);
        dialog.Canceled += dialog.QueueFree;
        return dialog;
    }

    public FileDialog sequence_dialog(Node parent, string format)
    {
        var dialog = new FileDialog { FileMode = FileDialog.FileModeEnum.OpenDir, Access = FileDialog.AccessEnum.Filesystem, Title = "Export " + format.ToUpperInvariant() + " sequence" };
        parent.AddChild(dialog); dialog.Canceled += dialog.QueueFree; return dialog;
    }
}
