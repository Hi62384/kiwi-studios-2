using Godot;
using System;
using System.Buffers.Binary;
using Settings=Godot.Collections.Dictionary;

public partial class AudioSourceCacheOperations : RefCounted
{
    public const int MaxDecodeBytes=128*1024*1024;
    public string identity(AudioStream? stream)=>stream?.GetInstanceId().ToString()??"";
    public Settings decode(AudioStream? stream,int rate,double start,double duration,double limitSeconds)
    {
        var empty=new Settings {["samples"]=Array.Empty<Vector2>(),["rate"]=rate,["error"]=""};if(stream==null){empty["error"]="Missing or unreadable audio source.";return empty;}rate=Math.Clamp(rate,8000,192000);start=Math.Max(0,start);double length=Math.Max(0,stream.GetLength()-start);if(duration>=0)length=Math.Min(length,duration);if(!double.IsFinite(length)||length>limitSeconds){empty["error"]="This operation is limited to "+limitSeconds.ToString("F0",System.Globalization.CultureInfo.InvariantCulture)+" seconds per region; select a smaller region or use the streaming renderer.";return empty;}long requested=(long)Math.Round(length*rate,MidpointRounding.AwayFromZero);if(requested<=0)return empty;if(requested>MaxDecodeBytes/8){empty["error"]="This sample-edit region exceeds the 128 MiB working-buffer limit; select a shorter region or use streaming export.";return empty;}int count=(int)requested;var samples=new Vector2[count];
        if(stream is AudioStreamWav wav&&wav.MixRate==rate&&wav.Format is AudioStreamWav.FormatEnum.Format8Bits or AudioStreamWav.FormatEnum.Format16Bits){var bytes=wav.Data;int channels=wav.Stereo?2:1,width=wav.Format==AudioStreamWav.FormatEnum.Format16Bits?2:1,first=(int)Math.Round(start*rate,MidpointRounding.AwayFromZero);count=Math.Min(count,Math.Max(0,bytes.Length/(width*channels)-first));if(count!=samples.Length)Array.Resize(ref samples,count);double Sample(int at)=>width==2?BinaryPrimitives.ReadInt16LittleEndian(bytes.AsSpan(at,2))/32768.0:(bytes[at]<128?bytes[at]:bytes[at]-256)/128.0;for(int frame=0;frame<count;frame++){int offset=(first+frame)*channels*width;float left=(float)Sample(offset);samples[frame]=new Vector2(left,channels==2?(float)Sample(offset+width):left);}}
        else{using var playback=stream.InstantiatePlayback();if(playback==null){empty["error"]="The audio decoder could not be initialized.";return empty;}playback.Start(start);int cursor=0;try{while(cursor<count){var chunk=playback.MixAudio((float)(AudioServer.GetMixRate()/rate),Math.Min(8192,count-cursor));if(chunk.Length==0)break;foreach(var sample in chunk){if(cursor>=count)break;samples[cursor++]=new Vector2(float.IsFinite(sample.X)?sample.X:0,float.IsFinite(sample.Y)?sample.Y:0);}}}finally{playback.Stop();}if(cursor!=samples.Length)Array.Resize(ref samples,cursor);}return new Settings {["samples"]=samples,["rate"]=rate,["error"]=""};
    }
    public AudioStreamWav to_wav(Vector2[] samples,int rate,bool stereo)
    {
        var stream=new AudioStreamWav {Format=AudioStreamWav.FormatEnum.Format16Bits,MixRate=Math.Clamp(rate,8000,192000),Stereo=stereo};int channels=stereo?2:1;var bytes=new byte[checked(samples.Length*channels*2)];static short Pcm(double value){if(!double.IsFinite(value))value=0;return (short)Math.Clamp(Math.Round(value*32768,MidpointRounding.AwayFromZero),-32768,32767);}for(int index=0;index<samples.Length;index++){var sample=samples[index];double left=stereo?sample.X:((double)sample.X+sample.Y)*.5;BinaryPrimitives.WriteInt16LittleEndian(bytes.AsSpan(index*channels*2,2),Pcm(left));if(stereo)BinaryPrimitives.WriteInt16LittleEndian(bytes.AsSpan(index*4+2,2),Pcm(sample.Y));}stream.Data=bytes;return stream;
    }
    public AudioStreamWav? fit_pattern(AudioStreamWav stream,double seconds)
    {
        int rate=stream.MixRate;var decoded=decode(stream,rate,0,-1,300);if(decoded["error"].AsString().Length>0)return null;if(!double.IsFinite(seconds)||seconds<=0||seconds*rate*8>MaxDecodeBytes)return null;var samples=decoded["samples"].AsVector2Array();Array.Resize(ref samples,Math.Max(2,(int)Math.Round(seconds*rate,MidpointRounding.AwayFromZero)));int fade=Math.Min(samples.Length/2,Math.Max(1,(int)(rate*.002)));for(int index=0;index<fade;index++){float gain=(float)index/fade;samples[index]*=gain;samples[samples.Length-1-index]*=gain;}return to_wav(samples,rate,stream.Stereo);
    }
}
