using Godot;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;
[GlobalClass]
public partial class KiwiAudioInstruments : RefCounted
{
    public const double MAX_SECONDS=300;
    public const int MAX_NOTES=8192;
    public static Godot.Collections.Array<Settings> presets()
    {using var operations=new AudioInstrumentOperations();return operations.presets();}
    public static Settings _patch(string id,string label,string kind,double attack,double decay,double sustain,double release,double cutoff,Settings extra)
    {using var operations=new AudioInstrumentOperations();return operations.patch(id,label,kind,attack,decay,sustain,release,cutoff,extra);}
    public static Settings default_instrument(string id)
    {using var operations=new AudioInstrumentOperations();return operations.default_instrument(id);}
    public static double midi_frequency(double pitch)
    {using var operations=new AudioInstrumentOperations();return operations.midi_frequency(pitch);}
    public static double _number(Settings settings,string key,double fallback,double low,double high)
    {using var operations=new AudioInstrumentOperations();return operations.number(settings,key,fallback,low,high);}
    public static double envelope(double t,double gate,double attack,double decay,double sustain,double release)
    {using var operations=new AudioInstrumentOperations();return operations.envelope(t,gate,attack,decay,sustain,release);}
    public static double _held_envelope(double t,double attack,double decay,double sustain)
    {using var operations=new AudioInstrumentOperations();return operations.held_envelope(t,attack,decay,sustain);}
    public static AudioStreamWav? render_notes(GArray notes,Settings instrument,double bpm,long rate=44100,RefCounted? job=null,GArray? tempos=null,double tempo_scale=1)
    {using var operations=new AudioInstrumentOperations();return operations.render_notes(notes,instrument,bpm,(int)rate,job,tempos??new GArray(),tempo_scale);}
    public static Settings _sample_mapping(Settings patch,long pitch,double velocity)
    {using var operations=new AudioInstrumentOperations();return operations.sample_mapping(patch,(int)pitch,velocity);}
    public static Vector2 _sample_at(Vector2[] data,double position)
    {using var operations=new AudioInstrumentOperations();return operations.sample_at(data,position);}
    public static double _table(GArray table,double phase)
    {using var operations=new AudioInstrumentOperations();return operations.table(table,phase);}
    public static double _note_bend(GArray points,double beat)
    {using var operations=new AudioInstrumentOperations();return operations.note_bend(points,beat);}
    public static double[] _lowpass_coeff(double cutoff,double resonance,long rate)
    {using var operations=new AudioInstrumentOperations();return operations.lowpass_coeff(cutoff,resonance,(int)rate);}
    public static double _filter(double value,double[] coeff,Variant state)
    {
        if(state.VariantType!=Variant.Type.PackedFloat64Array)throw new System.ArgumentException("Filter state must be a packed float64 array.",nameof(state));
        var values=state.AsFloat64Array();
        double output=coeff[0]*value+coeff[1]*values[0]+coeff[2]*values[1]-coeff[3]*values[2]-coeff[4]*values[3];
        double next=double.IsFinite(output)?output:0;
        // Preserve updates to the engine-owned packed state across the language boundary.
        using var args=new GArray{1,values[0]};EngineVariantDispatch.BuiltinCall(state,"set",args);
        args[0]=0;args[1]=value;EngineVariantDispatch.BuiltinCall(state,"set",args);
        args[0]=3;args[1]=values[2];EngineVariantDispatch.BuiltinCall(state,"set",args);
        args[0]=2;args[1]=next;EngineVariantDispatch.BuiltinCall(state,"set",args);
        return next;
    }
    public static RefCounted _native()=>Engine.GetSingleton("KiwiNativeServices").Call("service","audio_instruments").As<RefCounted>();
}
