using Godot;
using Settings = Godot.Collections.Dictionary;
[GlobalClass]
public partial class KiwiAudioDoppler : RefCounted
{
    public const double SOUND_SPEED=343, MAX_SPEED=100;
    public const int MIN_RATE=8000, MAX_RATE=192000, MAX_STAGE_BYTES=512*1024*1024, MAX_PROCESSING_MSEC=60000;
    public const string TIMEOUT_ERROR=AudioDopplerOperations.TimeoutError;
    public const int FRAME_BYTES=8, BLOCK_FRAMES=256, CACHE_FRAMES=4096, HALF_TAPS=16, TAPS=32, PHASES=1024;
    public static double _bounded(Settings p,string key,double fallback,double low,double high)
    {using var operations=new AudioDopplerOperations();return operations.bounded(p,key,fallback,low,high);}
    public static Settings parameters(Settings p)
    {using var operations=new AudioDopplerOperations();return operations.parameters(p);}
    public static double tail_seconds(Settings source_parameters)
    {using var operations=new AudioDopplerOperations();return operations.tail_seconds(source_parameters);}
    public static double _distance(double time,double speed,double closest,double travel,double pass_time)
    {using var operations=new AudioDopplerOperations();return operations.distance(time,speed,closest,travel,pass_time);}
    public static double[] _kernels(double speed,RefCounted? job,long started)
    {using var operations=new AudioDopplerOperations();return operations.kernels(speed,job,started);}
    public static Vector2 _resample(AudioFloatStageReader reader,double position,double[] table)
    {using var operations=new AudioDopplerOperations();return operations.resample(reader,position,table);}
    public static Settings _failure(string message,AudioFloatStageReader dry,AudioFloatStageReader wet,Godot.FileAccess? output,string output_path)
    {using var operations=new AudioDopplerOperations();return operations.failure(message,dry,wet,output,output_path);}
    public static Settings process_f32(string input_path,string output_path,Settings effect,int rate,RefCounted? job=null)
    {using var operations=new AudioDopplerOperations();return operations.process_f32(input_path,output_path,effect,rate,job);}
}
