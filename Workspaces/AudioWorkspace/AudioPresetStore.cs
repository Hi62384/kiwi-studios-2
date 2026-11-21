using Godot;
using Settings=Godot.Collections.Dictionary;
[GlobalClass]
public partial class AudioPresetStore : RefCounted
{
    public const string ROOT="user://audio_workspace/presets",RECOVERY="user://audio_workspace/preset_recovery";
    public const int MAX_BYTES=128*1024*1024;
    public static string root()=>ROOT;
    public static string recovery_directory()=>RECOVERY;
    public static long max_bytes()=>MAX_BYTES;
    public static bool owned(string path)
    {using var operations=new AudioPresetStoreOperations();return operations.owned(path);}
    public static string remove(string path,string digest)
    {using var operations=new AudioPresetStoreOperations();return operations.remove(path,digest);}
    public static string rename(string path,string digest,string label,string folder="__preserve")
    {using var operations=new AudioPresetStoreOperations();return operations.rename(path,digest,label,folder);}
    public static Godot.Collections.Array<Settings> recoverable()
    {using var operations=new AudioPresetStoreOperations();return operations.recoverable();}
    public static string restore(Settings entry)
    {using var operations=new AudioPresetStoreOperations();return operations.restore(entry);}
    public static GodotObject _native()=>Engine.GetSingleton("KiwiNativeServices").Call("service","audio_preset_store").As<RefCounted>();
}
