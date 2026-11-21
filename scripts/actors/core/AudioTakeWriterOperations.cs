using Godot;
public partial class AudioTakeWriterOperations:RefCounted
{
    public NativeAudioTakeWriter create()=>new NativeAudioTakeWriter();
}
