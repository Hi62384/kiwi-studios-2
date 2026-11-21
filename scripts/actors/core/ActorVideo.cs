using Godot;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

[GlobalClass]
public partial class ActorVideo : Node
{
    public const double PREVIEW_FPS = 24, WINDOW = 10;
    private static readonly string[] Extensions = { "mp4", "mov", "mkv", "webm", "avi", "m4v", "ogv", "mpeg", "mpg", "wmv", "ts" };
    private static ActorVideo? _instance;
    private static readonly Settings Metadata = new();
    private static readonly Settings Textures = new();
    public Settings _pending { get; set; } = new();
    public Settings _running { get; set; } = new();
    public Settings _completed { get; set; } = new();
    private readonly ActorVideoOperations _operations = new();
    public static GArray extensions()
    {
        var result = new GArray(); foreach (string extension in Extensions) result.Add(extension); return result;
    }
    public static string executable(string tool) => new ActorVideoOperations().executable(tool);
    public static Settings info(string path) => new ActorVideoOperations().info(Metadata, path);
    public static double length(ActorData actor) => new ActorVideoOperations().length(Metadata, actor);
    public static AudioStreamWav? audio(string path) => new ActorVideoOperations().audio(Metadata, path);
    public static ActorVideo manager()
    {
        if (GodotObject.IsInstanceValid(_instance) && !_instance!.IsQueuedForDeletion()) return _instance;
        if (Engine.GetMainLoop() is not SceneTree tree) throw new System.InvalidOperationException("Video preview requires an active scene tree.");
        _instance = new ActorVideo(); tree.Root.AddChild(_instance); return _instance;
    }
    public static Texture2D? frame(string path, double time, bool priority)
    {
        var source = info(path);
        return source.Count == 0 ? null : new ActorVideoOperations().frame(source, Textures, manager(), time, priority);
    }
    public override void _Process(double delta) => _operations.process(this);
    public override void _ExitTree()
    {
        _operations.exit_tree(this, Textures);
        if (_instance == this) _instance = null;
    }
    internal static void ClearCaches() { Metadata.Clear(); Textures.Clear(); }
}
