using Godot;
using System;
using System.IO;
using System.Collections.Generic;
using System.Threading;
using System.Buffers.Binary;
using Settings=Godot.Collections.Dictionary;
[GlobalClass]
public partial class NativeAudioTakeWriter:RefCounted
{
    public const int MAX_PENDING_BYTES = 2 * 1024 * 1024;
    public const long MAX_FILE_BYTES = 2L * 1024 * 1024 * 1024 - 44;
    public static int max_pending_bytes() => MAX_PENDING_BYTES;
    public override Variant _Get(StringName property) => property.ToString() switch
    {
        "path" => get_path(), "rate" => get_rate(), "mono" => get_mono(),
        "bytes_written" => get_bytes_written(), "_native_writer" => Variant.From(this), _ => default
    };
    public override bool _Set(StringName property, Variant value)
    {
        switch (property.ToString())
        {
            case "path": set_path(value.AsString()); return true;
            case "rate": set_rate(value.AsInt32()); return true;
            case "mono": set_mono(value.AsBool()); return true;
            case "bytes_written": set_bytes_written(value.AsInt64()); return true;
            default: return false;
        }
    }
    public override Godot.Collections.Array<Settings> _GetPropertyList() => new()
    {
        new Settings { ["name"] = "path", ["type"] = (int)Variant.Type.String, ["usage"] = (int)PropertyUsageFlags.ScriptVariable },
        new Settings { ["name"] = "rate", ["type"] = (int)Variant.Type.Int, ["usage"] = (int)PropertyUsageFlags.ScriptVariable },
        new Settings { ["name"] = "mono", ["type"] = (int)Variant.Type.Bool, ["usage"] = (int)PropertyUsageFlags.ScriptVariable },
        new Settings { ["name"] = "bytes_written", ["type"] = (int)Variant.Type.Int, ["usage"] = (int)PropertyUsageFlags.ScriptVariable }
    };
    public void _run() => run();
    public void _write_header(Godot.FileAccess file, long length) => write_header(file, length);
    private const int MaxPendingBytes=MAX_PENDING_BYTES;private const long MaxFileBytes=MAX_FILE_BYTES;
    private readonly object _gate=new();private readonly Queue<byte[]> _pending=new();private AutoResetEvent _wake=new(false);private System.Threading.Thread? _worker;private string _path="",_problem="";private int _rate=44100,_pendingBytes;private bool _mono,_closing;private long _written;
    public string get_path()=>_path;public int get_rate()=>_rate;public bool get_mono()=>_mono;public long get_bytes_written()=>Interlocked.Read(ref _written);
    public void set_path(string value)=>_path=value;public void set_rate(int value)=>_rate=value;public void set_mono(bool value)=>_mono=value;public void set_bytes_written(long value)=>Interlocked.Exchange(ref _written,value);
    public string start(string destination,int rate,bool mono)
    {
        if(_worker!=null)return "The take writer is already active.";_path=destination;_rate=rate;_mono=mono;if(rate<8000||rate>192000)return "Unsupported recording sample rate.";string absolute=ProjectSettings.GlobalizePath(destination);if(File.Exists(absolute))return "The take destination already exists.";
        lock(_gate){_written=0;_pending.Clear();_pendingBytes=0;_closing=false;_problem="";}_wake.Dispose();_wake=new AutoResetEvent(false);
        try{using var file=new FileStream(absolute,FileMode.CreateNew,FileAccessMode,FileShare.ReadWrite);file.Write(Header(0));}catch(Exception ex) when(ex is IOException or UnauthorizedAccessException or ArgumentException){return "Could not create the take file.";}
        try{_worker=new System.Threading.Thread(()=>Run(absolute)){IsBackground=true,Name="Kiwi PCM capture"};_worker.Start();}catch(Exception ex){_worker=null;return "Could not start the disk capture worker: "+ex.Message;}return "";
    }
    private const System.IO.FileAccess FileAccessMode=System.IO.FileAccess.ReadWrite;
    private static short Pcm(float sample)=>!float.IsFinite(sample)?(short)0:(short)Math.Clamp((int)MathF.Round(Math.Clamp(sample,-1,1)*32768,MidpointRounding.AwayFromZero),-32768,32767);
    public void append_frames(Vector2[] samples)
    {
        if(samples.Length==0)return;if(_worker==null){fail("The take writer is not active.");return;}if(samples.Length>16384){fail("Capture block exceeded its frame budget.");return;}int channels=_mono?1:2;var bytes=new byte[samples.Length*channels*2];for(int i=0;i<samples.Length;i++){BinaryPrimitives.WriteInt16LittleEndian(bytes.AsSpan(i*channels*2,2),Pcm(_mono?(samples[i].X+samples[i].Y)*.5f:samples[i].X));if(!_mono)BinaryPrimitives.WriteInt16LittleEndian(bytes.AsSpan(i*4+2,2),Pcm(samples[i].Y));}
        lock(_gate){if(!_closing&&_problem.Length==0){if(_pendingBytes+bytes.Length>MaxPendingBytes)_problem="The recording disk could not keep up. The captured prefix has been preserved.";else{_pending.Enqueue(bytes);_pendingBytes+=bytes.Length;}}}_wake.Set();
    }
    public void fail(string message){lock(_gate)if(_problem.Length==0)_problem=message;}
    public string error(){lock(_gate)return _problem;}
    public int pending_bytes(){lock(_gate)return _pendingBytes;}
    public void request_finish(){lock(_gate)_closing=true;_wake.Set();}
    public bool busy()=>_worker?.IsAlive??false;
    public Settings finish(){request_finish();_worker?.Join();_worker=null;return new Settings{["path"]=_path,["frames"]=get_bytes_written()/(_mono?2:4),["rate"]=_rate,["channels"]=_mono?1:2,["error"]=error()};}
    private void Run(string absolute)
    {
        FileStream file;try{file=new FileStream(absolute,FileMode.Open,FileAccessMode,FileShare.ReadWrite);}catch(Exception){fail("The take file could not be opened by the capture worker.");return;}using(file){file.Position=44;long checkpoint=System.Environment.TickCount64;try{while(true){_wake.WaitOne();while(true){byte[]? block;bool closing;lock(_gate){block=_pending.Count>0?_pending.Dequeue():null;if(block!=null)_pendingBytes-=block.Length;closing=_closing;}if(block==null){if(closing){file.Position=0;file.Write(Header(_written));file.Flush();return;}break;}if(_written+block.Length>MaxFileBytes){fail("The 2 GiB per-source recording limit was reached; the take prefix is retained.");continue;}file.Write(block);Interlocked.Add(ref _written,block.Length);if(System.Environment.TickCount64>=checkpoint){file.Position=0;file.Write(Header(_written));file.Flush();file.Position=44+_written;checkpoint=System.Environment.TickCount64+1000;}}}}catch(Exception){fail("Recording write failed; the last checkpoint is retained.");}}
    }
    private byte[] Header(long length)
    {
        var bytes=new byte[44];System.Text.Encoding.ASCII.GetBytes("RIFF").CopyTo(bytes,0);BinaryPrimitives.WriteUInt32LittleEndian(bytes.AsSpan(4,4),(uint)(36+length));System.Text.Encoding.ASCII.GetBytes("WAVEfmt ").CopyTo(bytes,8);BinaryPrimitives.WriteUInt32LittleEndian(bytes.AsSpan(16,4),16);BinaryPrimitives.WriteUInt16LittleEndian(bytes.AsSpan(20,2),1);ushort channels=(ushort)(_mono?1:2);BinaryPrimitives.WriteUInt16LittleEndian(bytes.AsSpan(22,2),channels);BinaryPrimitives.WriteUInt32LittleEndian(bytes.AsSpan(24,4),(uint)_rate);BinaryPrimitives.WriteUInt32LittleEndian(bytes.AsSpan(28,4),(uint)(_rate*channels*2));BinaryPrimitives.WriteUInt16LittleEndian(bytes.AsSpan(32,2),(ushort)(channels*2));BinaryPrimitives.WriteUInt16LittleEndian(bytes.AsSpan(34,2),16);System.Text.Encoding.ASCII.GetBytes("data").CopyTo(bytes,36);BinaryPrimitives.WriteUInt32LittleEndian(bytes.AsSpan(40,4),(uint)length);return bytes;
    }
    public void write_header(Godot.FileAccess file,long length){file.Seek(0);file.StoreBuffer(Header(length));}
    public void run()=>Run(ProjectSettings.GlobalizePath(_path));
}
