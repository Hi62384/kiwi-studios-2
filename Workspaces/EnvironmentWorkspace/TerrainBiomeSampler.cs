using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings=Godot.Collections.Dictionary;

internal sealed class TerrainBiomeSampler
{
    private static readonly string[] ExtraRanges={"cave_depth","submersion"};
    private sealed record Rule(string Id,Settings Values,FastNoiseLite Noise,float[] Mask);
    private readonly Rule[] _rules;
    private readonly string _fallback,_caveFallback;
    internal static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    internal TerrainBiomeSampler(Resource owner,Settings noises)
    {
        var masks=owner.Get("paint_masks").AsGodotDictionary();_fallback=owner.Get("fallback_id").AsString();_caveFallback=owner.Get("cave_fallback_id").AsString();var rules=new List<Rule>();
        foreach(var entry in owner.Get("definitions").AsGodotArray()){var values=entry.AsGodotDictionary();string id=values["id"].AsString();if(noises.TryGetValue(id,out var noise))rules.Add(new Rule(id,values,noise.As<FastNoiseLite>(),Get(masks,id,Array.Empty<float>()).AsFloat32Array()));}_rules=rules.ToArray();
    }
    internal static double Range(double value,Vector2 limits,double transition)
    {double fade=Math.Max(.0001,((double)limits.Y-limits.X)*transition);return Mathf.SmoothStep(limits.X-fade,limits.X,value)*(1-Mathf.SmoothStep(limits.Y,limits.Y+fade,value));}
    internal static double MaskAt(float[] mask,int x,int z,int n)
    {
        if(mask.Length==n*n)return mask[x+z*n];int old=(int)Math.Round(Math.Sqrt(mask.Length),MidpointRounding.AwayFromZero);if(old<2||old*old!=mask.Length)return 0;
        var p=new Vector2(x,z)/Math.Max(1,n-1)*(old-1);var cell=new Vector2I(Math.Min((int)Math.Floor(p.X),old-2),Math.Min((int)Math.Floor(p.Y),old-2));var f=p-(Vector2)cell;
        return Mathf.Lerp(Mathf.Lerp(mask[cell.X+cell.Y*old],mask[cell.X+1+cell.Y*old],f.X),Mathf.Lerp(mask[cell.X+(cell.Y+1)*old],mask[cell.X+1+(cell.Y+1)*old],f.X),f.Y);
    }
    internal Dictionary<string,double> Sample(Vector2 point,double elevation,double slope,double temperature,double humidity,double shore,double roughness,int index,int n,Settings features)
    {
        var result=new Dictionary<string,double>(StringComparer.Ordinal);double total=0;string fallback="";bool cave=Get(features,"domain","surface").AsString()=="cave";
        foreach(var rule in _rules)
        {
            string id=rule.Id;var definition=rule.Values;if(cave){if(id==_caveFallback)fallback=id;}else if(fallback.Length==0||id==_fallback)fallback=id;
            double transition=Math.Clamp(Get(definition,"transition",.2).AsDouble(),.001,1),suitability=Math.Max(0,Get(definition,"weight",1.0).AsDouble());
            suitability*=Range(temperature,Get(definition,"temperature",new Vector2(-100000,100000)).AsVector2(),transition);
            suitability*=Range(humidity,Get(definition,"humidity",new Vector2(-100000,100000)).AsVector2(),transition);
            suitability*=Range(elevation,Get(definition,"altitude",new Vector2(-100000,100000)).AsVector2(),transition);
            suitability*=Range(slope,Get(definition,"slope",new Vector2(-100000,100000)).AsVector2(),transition);
            suitability*=Range(shore,Get(definition,"shore_distance",new Vector2(-100000,100000)).AsVector2(),transition);
            suitability*=Range(roughness,Get(definition,"roughness",new Vector2(-100000,100000)).AsVector2(),transition);
            foreach(string key in ExtraRanges)if(definition.TryGetValue(key,out var limits)&&features.TryGetValue(key,out var sample))suitability*=Range(sample.AsDouble(),limits.AsVector2(),transition);
            if(definition.TryGetValue("geology",out var allowed)&&features.TryGetValue("geology",out var geology)&&!allowed.AsGodotArray().Any(value=>value.AsInt64()==geology.AsInt64()))suitability=0;
            if(definition.TryGetValue("surface_type",out var surface)&&surface.AsString()!="any"&&surface.AsString()!=Get(features,"surface_type","any").AsString())suitability=0;
            double frequency=Math.Clamp(Get(definition,"frequency",1.0).AsDouble(),0,1),sampled=features.TryGetValue("noise_position",out var position)?rule.Noise.GetNoise3Dv(position.AsVector3()):rule.Noise.GetNoise2Dv(point),region=Math.Clamp(.5+sampled*.75,0,1);
            if(frequency<1)suitability*=frequency>0?Mathf.SmoothStep(1-frequency-transition*.25,1-frequency+transition*.25,region):0;
            if(rule.Mask.Length>0)suitability=Mathf.Lerp(suitability,1,Math.Clamp(MaskAt(rule.Mask,index%n,index/n,n),0,1));result[id]=suitability;total+=suitability;
        }
        if(total<=.000001&&fallback.Length>0){result[fallback]=1;total=1;}if(total>0)foreach(string id in result.Keys.ToArray())result[id]/=total;return result;
    }
}
