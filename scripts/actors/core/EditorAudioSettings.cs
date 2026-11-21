using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class EditorAudioSettings : RefCounted
{
    public const string PATH = "user://editor_audio_settings.cfg";
    public static Settings read() => new ActorAudioRecorderOperations().read_preferences();
    public static void write(Settings values) => new ActorAudioRecorderOperations().write_preferences(values);
}
