using Godot;
using System;
using Settings=Godot.Collections.Dictionary;

public partial class AudioImpulseOperations : RefCounted
{
    private static double Value(Settings values,string key,double fallback)=>values.TryGetValue(key,out var value)?value.AsDouble():fallback;
    private static bool Cancelled(RefCounted? job)=>job!=null&&job.Call("is_cancelled").AsBool();
    public double duration(string type,Settings parameters)=>type=="pingpong"?Math.Clamp(Value(parameters,"time",.25),.01,1.5)*8:type=="convolution"?Math.Clamp(Value(parameters,"length",3),.1,20):Math.Clamp(Value(parameters,"decay",2),.1,8);
    public AudioStreamWav? generate(string type,Settings parameters,int rate,RefCounted? job)
    {
        double seconds=duration(type,parameters);int frames=Math.Max(2,(int)Math.Round(seconds*rate,MidpointRounding.AwayFromZero));var samples=new Vector2[frames];using var cache=new AudioSourceCacheOperations();if(type=="pingpong"){int delay=Math.Max(1,(int)Math.Round(Value(parameters,"time",.25)*rate,MidpointRounding.AwayFromZero));double feedback=Math.Clamp(Value(parameters,"feedback",.45),0,.85);for(int index=0;index<8;index++){int at=Math.Min(frames-1,delay*(index+1)-1);float gain=(float)Math.Pow(feedback,index);samples[at]=index%2==0?new Vector2(gain,0):new Vector2(0,gain);}return cache.to_wav(samples,rate,true);}using var random=new RandomNumberGenerator {Seed=unchecked((ulong)(parameters.TryGetValue("seed",out var seed)?seed.AsInt64():137))};double damping=Math.Clamp(Value(parameters,"damping",.5),0,1);var filtered=Vector2.Zero;
        if(type=="plate")
        {
            var delays=new[]{4.3,7.1,11.7,17.3};var buffers=new Vector2[4][];var indices=new int[4];for(int stage=0;stage<4;stage++)buffers[stage]=new Vector2[Math.Max(1,(int)(delays[stage]*rate/1000))];float coefficient=(float)Mathf.Lerp(.85,.09,damping);for(int index=0;index<frames;index++){if(index%8192==0&&job!=null){if(Cancelled(job))return null;job.Call("update",.02+.06*index/frames,"Preparing plate response");}double time=(double)index/rate,envelope=Math.Exp(-6.907755*time/seconds)*(1-Math.Exp(-time*120));var value=new Vector2(random.RandfRange(-1,1),random.RandfRange(-1,1))*(float)envelope;filtered=filtered.Lerp(value,coefficient);value=filtered;for(int stage=0;stage<buffers.Length;stage++){int at=indices[stage];var delayed=buffers[stage][at];var next=delayed-value*.62f;buffers[stage][at]=value+next*.62f;indices[stage]=(at+1)%buffers[stage].Length;value=next;}samples[index]=value;}double energy=0;foreach(var value in samples)energy+=value.LengthSquared()*.5;float gain=(float)(.65/Math.Sqrt(Math.Max(.000001,energy)));for(int index=0;index<samples.Length;index++)samples[index]*=gain;foreach(var tap in new[]{new[]{.013,.28,-.1},new[]{.023,-.12,.26},new[]{.037,.16,.19}}){int index=(int)(tap[0]*rate);if(index<frames)samples[index]+=new Vector2((float)tap[1],(float)tap[2]);}
        }
        else if(type=="spring")
        {
            double tension=Math.Clamp(Value(parameters,"tension",1),.5,2);for(int mode=0;mode<24;mode++){if(Cancelled(job))return null;double frequency=(97+mode*mode*18.7+mode*43.1)*tension;if(frequency>=rate*.43)continue;double arrival=.009+mode*.0007,decay=seconds/(1+mode*damping*.075),amplitude=1/Math.Pow(mode+1,.7),pan=random.RandfRange(-.7f,.7f);for(int index=(int)(arrival*rate);index<frames;index++){double time=(double)index/rate-arrival,phase=Math.Tau*(frequency*time+25*tension*(1-Math.Exp(-time*20))),value=Math.Sin(phase)*Math.Exp(-6.907755*time/decay)*(1-Math.Exp(-time*500))*amplitude;samples[index]+=new Vector2((float)(value*(1-pan*.4)),(float)(value*(1+pan*.4)));}}var area=Vector2.Zero;foreach(var value in samples)area+=value.Abs();float divisor=(float)Math.Max(1,Math.Max(area.X,area.Y)*.35);for(int index=0;index<samples.Length;index++)samples[index]/=divisor;
        }
        else return null;int fade=Math.Min(frames,Math.Max(1,(int)(rate*.005)));for(int index=0;index<fade;index++)samples[frames-1-index]*=(float)index/fade;return cache.to_wav(samples,rate,true);
    }
}
