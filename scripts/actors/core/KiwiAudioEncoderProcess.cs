using Godot;
using Settings = Godot.Collections.Dictionary;
[GlobalClass]
public partial class KiwiAudioEncoderProcess : RefCounted
{
    public const int LOG_BYTES=65536, PROGRESS_BYTES=8192, READ_CHUNK_BYTES=4096, READ_BURST=8;
    public const int QUIT_GRACE_MSEC=1500, STOP_WAIT_MSEC=2000, DRAIN_MSEC=250, DRAIN_BYTES=4*1024*1024;
    public const double MAX_WALL_SECONDS=86400;
    public static Settings run(string encoder,string[] arguments,double duration=1,RefCounted? job=null,double wall_seconds=0)
    { using var operations=new AudioEncoderProcessOperations(); return operations.run(encoder,arguments,duration,job,wall_seconds); }
    public static void _read_pipes(Godot.FileAccess stdio,Godot.FileAccess stderr,Settings state,double duration,RefCounted? job)
    { using var operations=new AudioEncoderProcessOperations(); operations.read_pipes(stdio,stderr,state,duration,job); }
    public static byte[] _available(Godot.FileAccess pipe)
    { using var operations=new AudioEncoderProcessOperations(); return operations.available(pipe); }
    public static byte[] _tail_bytes(byte[] previous,byte[] incoming,int limit)
    { using var operations=new AudioEncoderProcessOperations(); return operations.tail_bytes(previous,incoming,limit); }
}
