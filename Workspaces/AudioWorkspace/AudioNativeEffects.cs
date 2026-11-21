using Godot;
using System;
using Settings=Godot.Collections.Dictionary;

public partial class AudioEffectsOperations
{
    public AudioEffect? native_effect(Settings effect)
    {
        if(!Enabled(effect))return null;var p=Parameters(effect);string kind=Text(effect,"type");AudioEffect Make(string name)=>ClassDB.Instantiate(name).As<AudioEffect>();void Set(AudioEffect target,string name,double value)=>target.Set(name,value);
        switch(kind)
        {
            case "gain":var gain=Make("AudioEffectAmplify");Set(gain,"volume_db",Value(p,"db"));return gain;
            case "limiter":var limiter=Make("AudioEffectHardLimiter");Set(limiter,"ceiling_db",Value(p,"ceiling",-1));Set(limiter,"release",Value(p,"release",.1));return limiter;
            case "compressor":var compressor=Make("AudioEffectCompressor");Set(compressor,"threshold",Value(p,"threshold",-18));Set(compressor,"ratio",Value(p,"ratio",4));Set(compressor,"attack_us",Math.Clamp(Value(p,"attack",10)*1000,20,2000));Set(compressor,"release_ms",Value(p,"release",180));Set(compressor,"gain",Value(p,"makeup"));if(p.TryGetValue("sidechain",out var sidechain))compressor.Set("sidechain",new StringName(sidechain.AsString()));return compressor;
            case "lowpass":case "highpass":case "bandpass":case "notch":var filter=Make(kind switch {"lowpass"=>"AudioEffectLowPassFilter","highpass"=>"AudioEffectHighPassFilter","bandpass"=>"AudioEffectBandPassFilter",_=>"AudioEffectNotchFilter"});Set(filter,"cutoff_hz",Value(p,"frequency",1000));Set(filter,"resonance",Math.Clamp(Value(p,"q",.707),0,1));return filter;
            case "delay":var delay=Make("AudioEffectDelay");double wet=Value(p,"mix",.3);Set(delay,"dry",1-wet*.3);Set(delay,"tap1_delay_ms",Value(p,"time",.25)*1000);Set(delay,"tap1_level_db",Mathf.LinearToDb(Math.Max(.00001,wet)));Set(delay,"tap1_pan",0);delay.Set("tap2_active",false);delay.Set("feedback_active",Value(p,"feedback",.35)>0);delay.Set("feedback_delay_ms",delay.Get("tap1_delay_ms"));Set(delay,"feedback_level_db",Mathf.LinearToDb(Math.Max(.00001,Value(p,"feedback",.35))));return delay;
            case "reverb":var reverb=Make("AudioEffectReverb");Set(reverb,"room_size",Value(p,"size",.6));Set(reverb,"damping",Value(p,"damping",.5));Set(reverb,"wet",Value(p,"mix",.25));Set(reverb,"dry",1);return reverb;
            case "chorus":var chorus=Make("AudioEffectChorus");chorus.Set("voice_count",2);Set(chorus,"wet",Value(p,"mix",.3));Set(chorus,"dry",1);for(int voice=0;voice<2;voice++){chorus.Call("set_voice_rate_hz",voice,Value(p,"rate",.8)*(1+voice*.13));chorus.Call("set_voice_depth_ms",voice,Value(p,"depth",4));chorus.Call("set_voice_delay_ms",voice,12+voice*7);chorus.Call("set_voice_pan",voice,voice==0?-.5:.5);}return chorus;
            case "phaser":var phaser=Make("AudioEffectPhaser");Set(phaser,"rate_hz",Value(p,"rate",.5));Set(phaser,"depth",Value(p,"depth",.6));return phaser;
            case "saturate":case "hardclip":var distortion=Make("AudioEffectDistortion");distortion.Set("mode",ClassDB.ClassGetIntegerConstant("AudioEffectDistortion",kind=="saturate"?"MODE_ATAN":"MODE_CLIP"));Set(distortion,"drive",kind=="saturate"?Value(p,"drive",.35):0);Set(distortion,"pre_gain",kind=="saturate"?12*distortion.Get("drive").AsDouble():Value(p,"drive",6));Set(distortion,"post_gain",Value(p,"output",-6));return distortion;
            case "pitch":var pitch=Make("AudioEffectPitchShift");Set(pitch,"pitch_scale",Math.Pow(2,Value(p,"semitones")/12));return pitch;
            case "stereo_width":var stereo=Make("AudioEffectStereoEnhance");Set(stereo,"pan_pullout",Value(p,"width",1.4));return stereo;
            case "pan":var pan=Make("AudioEffectPanner");Set(pan,"pan",Value(p,"pan"));return pan;
            default:return null;
        }
    }
    private static bool Equal(Variant first,Variant last){if(first.VariantType!=last.VariantType)return false;return first.VariantType switch {Variant.Type.String or Variant.Type.StringName=>first.AsString()==last.AsString(),Variant.Type.Float=>first.AsDouble()==last.AsDouble(),Variant.Type.Int=>first.AsInt64()==last.AsInt64(),Variant.Type.Bool=>first.AsBool()==last.AsBool(),Variant.Type.Object=>first.AsGodotObject()==last.AsGodotObject(),_=>first.Equals(last)};}
    public void update_native_properties(AudioEffect target,AudioEffect source){foreach(var raw in source.GetPropertyList()){var property=raw;string name=property["name"].AsString();if((property["usage"].AsInt64()&(long)PropertyUsageFlags.Storage)==0||name is "resource_local_to_scene" or "resource_name" or "script")continue;var value=source.Get(name);if(!Equal(target.Get(name),value))target.Set(name,value);}}
}
