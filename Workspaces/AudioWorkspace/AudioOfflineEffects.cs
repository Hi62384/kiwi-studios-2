using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class AudioEffectsOperations
{
    public string offline_filter(Settings effect,int rate)
    {
        if(!Enabled(effect))return "";var p=Parameters(effect);string kind=Text(effect,"type");double D(string key,double fallback=0)=>Value(p,key,fallback);string N(string key,double fallback=0)=>number(D(key,fallback));string Num(double value)=>number(value);
        switch(kind)
        {
            case "doppler":return "";
            case "hq_pitch":return "rubberband=pitch="+Num(Math.Pow(2,D("semitones")/12))+":formant="+(D("preserve")>=.5?"preserved":"shifted")+":pitchq=quality:channels=together";
            case "formant":{double ratio=Math.Pow(2,D("semitones")/12);return "rubberband=pitch="+Num(1/ratio)+":formant=preserved:pitchq=quality:channels=together,asetrate="+Num(rate*ratio)+",aresample="+rate+","+tempo_filter(1/ratio);}
            case "time_warp":return "rubberband=tempo="+N("tempo",1)+":pitch=1:channels=together";
            case "audio_fm":return "vibrato=f="+N("rate",120)+":d="+N("depth",.15);
            case "distance":{double distance=Math.Max(1,D("distance",8)),reference=Math.Max(1,D("reference",1));return "volume="+Num(Math.Min(1,reference/distance))+",lowpass=f="+Num(Math.Min(rate*.45,20000/(1+D("air",.5)*Math.Max(0,distance-reference)*.08)));}
            case "multiband":{double threshold=D("threshold",-18),ratio=Math.Max(1,D("ratio",3));string transfer="-90/-90,"+Num(threshold)+"/"+Num(threshold)+",0/"+Num(threshold*(1-1/ratio));string envelope=Num(D("attack",10)/1000)+","+Num(D("release",150)/1000)+" 6 "+transfer;return "mcompand=args='"+envelope+" "+Num(Math.Min(rate*.1,D("low",200)))+" | "+envelope+" "+Num(Math.Min(rate*.4,D("high",3000)))+" | "+envelope+" "+Num(Math.Min(22000,rate*.49))+"',volume="+N("makeup")+"dB";}
            case "graphic_eq":{var filters=new List<string>();foreach(int frequency in new[]{63,125,250,500,1000,2000,4000,8000})filters.Add("equalizer=f="+Num(Math.Min(rate*.45,frequency))+":t=o:w=1:g="+N("b"+frequency));return string.Join(',',filters);}
            case "early_reflections":{double wet=D("mix",.25);if(wet<=0)return "";double size=D("size",.5);var times=new List<string>();var gains=new List<string>();for(int index=0;index<4;index++){times.Add(Num(new[]{17,29,43,67}[index]*(.5+size)));gains.Add(Num(wet*new[]{.5,.35,.23,.15}[index]));}return "aecho=1:1:"+string.Join('|',times)+":"+string.Join('|',gains);}
            case "stereo_delay":return "adelay="+N("left",20)+"|"+N("right",65);
            case "frequency_shift":return "afreqshift=shift="+N("shift",30)+":order=12";
            case "tube":{string drive=N("drive",3),bias=N("bias",.1),expression="(atan((val(CH)+"+bias+")*"+drive+")-atan("+bias+"*"+drive+"))";return "aeval='"+expression.Replace("CH","0")+"|"+expression.Replace("CH","1")+"',highpass=f=15,volume="+N("output",-6)+"dB";}
            case "tape":return "volume="+N("drive",2)+",asoftclip=type=tanh,lowpass=f="+Num(Math.Min(rate*.45,D("cutoff",12000)))+",vibrato=f="+N("rate",.5)+":d="+N("wow",.03)+",volume="+N("output",-6)+"dB";
            case "gain":return "volume="+N("db")+"dB";
            case "normalize":return "loudnorm=I="+N("lufs",-16)+":TP="+N("peak",-1)+":LRA=11,aresample="+rate;
            case "limiter":return "alimiter=limit="+Num(Mathf.DbToLinear(D("ceiling",-1)))+":attack=5:release="+Num(D("release",.1)*1000)+":level=false:latency=true";
            case "compressor":return "acompressor=threshold="+Num(Mathf.DbToLinear(D("threshold",-18)))+":ratio="+N("ratio",4)+":attack="+N("attack",10)+":release="+N("release",180)+":makeup="+Num(Mathf.DbToLinear(D("makeup")));
            case "gate":case "breath":return "agate=threshold="+Num(Mathf.DbToLinear(D("threshold",-40)))+":ratio="+N("ratio",4)+":attack="+N("attack",5)+":release="+N("release",150);
            case "deesser":return "deesser=i="+N("intensity",.5)+":m="+N("amount",.5);
            case "leveler":return "dynaudnorm=f="+N("window",500)+":g=31:m="+N("strength",5);
            case "transient":return "crystalizer=i="+N("amount",2);
            case "lowpass":case "highpass":return kind+"=f="+Num(Math.Min(rate*.45,D("frequency",1000)))+":t=q:w="+N("q",.707);
            case "bandpass":case "notch":return (kind=="notch"?"bandreject":"bandpass")+"=f="+Num(Math.Min(rate*.45,D("frequency",1000)))+":t=q:w="+N("q",1);
            case "eq":return "equalizer=f="+N("frequency",1500)+":t=q:w="+N("q",1)+":g="+N("db",3);
            case "low_shelf":case "high_shelf":return (kind=="low_shelf"?"bass":"treble")+"=f="+N("frequency",150)+":g="+N("db",3);
            case "telephone":return "highpass=f="+N("low",300)+",lowpass=f="+N("high",3400);
            case "dynamic_eq":return "adynamicequalizer=dfrequency="+N("frequency",3500)+":tfrequency="+N("frequency",3500)+":threshold="+N("threshold",3)+":ratio="+N("ratio",2);
            case "delay":{double wet=Math.Clamp(D("mix",.3),0,1);if(wet<=0)return "";var delays=new List<string>();var gains=new List<string>();double feedback=Math.Clamp(D("feedback",.35),0,.85);for(int tap=0;tap<8;tap++){double decay=wet*Math.Pow(feedback,tap);if(decay<.00000001)break;delays.Add(Num(D("time",.25)*1000*(tap+1)));gains.Add(Num(decay));}return "aecho=1:1:"+string.Join('|',delays)+":"+string.Join('|',gains);}
            case "reverb":{if(D("mix",.25)<=0)return "";var times=new List<string>();var gains=new List<string>();double size=D("size",.6),damping=D("damping",.5);for(int tap=0;tap<32;tap++){double time=19+(tap*tap*1.71+tap*13.7)*(.2+size);times.Add(Num(time));gains.Add(Num(D("mix",.25)*Math.Exp(-time/(250+size*1100))*.35));}return "aecho=1:1:"+string.Join('|',times)+":"+string.Join('|',gains)+",lowpass=f="+Num(19000-damping*5000);}
            case "chorus":{double wet=Math.Clamp(D("mix",.3),0,1);if(wet<=0)return "";return "chorus=1:1:40|53:"+Num(wet*.5)+"|"+Num(wet*.5)+":"+N("rate",.8)+"|"+Num(D("rate",.8)*1.13)+":"+N("depth",4)+"|"+Num(D("depth",4)*.8);}
            case "flanger":return "flanger=delay=0:depth="+N("depth",3)+":regen="+Num(D("feedback",.4)*90)+":speed="+N("rate",.3);
            case "phaser":return "aphaser=0.6:0.7:3:"+Num(D("depth",.6)*.9)+":"+Num(Math.Clamp(D("rate",.5),.1,2))+":t";
            case "tremolo":case "vibrato":return kind+"=f="+N("rate",4)+":d="+N("depth",.5);
            case "ring":{string expression="val(CH)*(1-"+N("mix",.8)+"+"+N("mix",.8)+"*sin(2*PI*"+N("frequency",65)+"*t))";return "aeval='"+expression.Replace("CH","0")+"|"+expression.Replace("CH","1")+"'";}
            case "autopan":{string phase=N("depth",.8)+"*sin(2*PI*"+Num(Math.Clamp(D("rate",.5),.05,10))+"*t)";return "aeval='val(0)*sqrt(0.5*(1-("+phase+")))|val(1)*sqrt(0.5*(1+("+phase+")))'";}
            case "saturate":return "volume="+Num(1+D("drive",.35)*8)+",asoftclip=type=tanh,volume="+N("output",-6)+"dB";
            case "hardclip":return "volume="+N("drive",6)+"dB,asoftclip=type=hard,volume="+N("output",-6)+"dB";
            case "bitcrusher":return "acrusher=bits="+N("bits",8)+":samples="+N("reduction",1);
            case "wavefold":{string expression="asin(sin(val(CH)*"+N("drive",3)+"*PI/2))*2/PI";return "aeval='"+expression.Replace("CH","0")+"|"+expression.Replace("CH","1")+"',volume="+N("output",-6)+"dB";}
            case "pitch":{double ratio=Math.Pow(2,D("semitones")/12);return "asetrate="+Num(rate*ratio)+",aresample="+rate+","+tempo_filter(1/ratio);}
            case "stretch":return tempo_filter(1/Math.Max(.05,D("factor",1.25)));
            case "reverse":return "areverse";
            case "stereo_width":{double width=D("width",1.4);return "pan=stereo|c0="+Num((1+width)*.5)+"*c0+"+Num((1-width)*.5)+"*c1|c1="+Num((1+width)*.5)+"*c1+"+Num((1-width)*.5)+"*c0";}
            case "pan":return pan_filter(D("pan"));
            case "noise_reduce":{var bands=Get(p,"noise_profile",new GArray());string profile="";if(bands.VariantType==Variant.Type.Array&&bands.AsGodotArray().Count==15){var values=new List<string>();foreach(var value in bands.AsGodotArray())values.Add(Num(Math.Clamp(value.AsDouble(),-24,24)));profile=":nt=c:bn='"+string.Join(' ',values)+"'";}return "afftdn=nr="+N("reduction",12)+":nf="+N("floor",-45)+":tn="+(profile.Length==0?1:0)+":gs=5"+profile;}
            case "hum_remove":{var filters=new List<string>();for(int harmonic=0;harmonic<(int)D("harmonics",4);harmonic++)filters.Add("bandreject=f="+Num(D("frequency",60)*(harmonic+1))+":t=q:w=20");return string.Join(',',filters);}
            case "declick":return "adeclick=t="+N("threshold",2)+":w="+N("window",30);
            case "declip":return "adeclip=t="+N("threshold",10);
            default:return "";
        }
    }
}
