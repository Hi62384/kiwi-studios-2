using Godot;
using System;
using System.Collections.Generic;
using System.Runtime.CompilerServices;
using Settings=Godot.Collections.Dictionary;

public partial class TerrainDataOperations : RefCounted
{
    private static Variant Get(Settings values,Variant key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private sealed class Samples
    {
        internal readonly int N;internal readonly Vector2 Dimensions;internal readonly float[] Base,Edits,Water,Mask;
        internal Samples(Resource source)
        {N=source.Get("resolution").AsInt32();Dimensions=source.Get("dimensions").AsVector2();Base=source.Get("_base").AsFloat32Array();Edits=source.Get("edits").AsFloat32Array();Mask=source.Get("material_mask").AsFloat32Array();var hydrology=source.Get("hydrology").As<Resource>();Water=hydrology!=null&&hydrology.Get("enabled").AsBool()?source.Get("water_delta").AsFloat32Array():Array.Empty<float>();}
        internal double WaterAt(int index)=>Water.Length==N*N?Water[index]:0;
        internal double Height(int x,int z){int index=Math.Clamp(x,0,N-1)+Math.Clamp(z,0,N-1)*N;return(double)Base[index]+Edits[index]+WaterAt(index);}
        internal Vector3 Position(int x,int z)=>new((float)((x/(double)(N-1)-.5)*Dimensions.X),(float)Height(x,z),(float)((z/(double)(N-1)-.5)*Dimensions.Y));
        internal Vector3 Normal(int x,int z)=>new Vector3((float)(-(Height(x+1,z)-Height(x-1,z))/(Dimensions.X/(double)(N-1)*2)),1,(float)(-(Height(x,z+1)-Height(x,z-1))/(Dimensions.Y/(double)(N-1)*2))).Normalized();
        internal (Vector2 Center,Vector2 Spacing,Vector2I Low,Vector2I High) Bounds(Vector2 center,double radius)
        {var spacing=Dimensions/(N-1);var p=(center/Dimensions+Vector2.One*.5f)*(N-1);var extent=Vector2.One*(float)radius/spacing;return(p,spacing,((Vector2I)(p-extent).Floor()).Max(Vector2I.Zero),((Vector2I)(p+extent).Ceil()).Min(Vector2I.One*(N-1)));}
    }
    private sealed class SampleEntry
    {
        internal (long Base,long Revision,long Water,int N,Vector2 Dimensions,bool WaterEnabled) Key;
        internal Samples? Data;
    }
    private static readonly ConditionalWeakTable<Resource,SampleEntry> SampleCache=new();
    private static Samples ReadSamples(Resource source)
    {
        var hydrology=source.Get("hydrology").As<Resource>();var key=(source.Get("_base_key").AsInt64(),source.Get("revision").AsInt64(),source.Get("water_key").AsInt64(),source.Get("resolution").AsInt32(),source.Get("dimensions").AsVector2(),hydrology!=null&&hydrology.Get("enabled").AsBool());var entry=SampleCache.GetValue(source,_=>new SampleEntry());if(entry.Data==null||entry.Key!=key){entry.Key=key;entry.Data=new Samples(source);}return entry.Data;
    }
    private static Samples FreshSamples(Resource source){SampleCache.Remove(source);return ReadSamples(source);}
    public void mark_samples_dirty(Resource source,Settings samples)
    {
        int n=source.Get("resolution").AsInt32();long revision=source.Get("revision").AsInt64();var dirty=source.Get("dirty_chunks").AsGodotDictionary();var keys=source.Get("chunk_keys").AsGodotDictionary();foreach(var key in samples.Keys){int index=key.AsInt32(),x=index%n,z=index/n;for(int dz=-1;dz<=1;dz++)for(int dx=-1;dx<=1;dx++){var coordinate=new Vector2I(Math.Clamp(x+dx,0,n-2)/32,Math.Clamp(z+dz,0,n-2)/32);dirty[coordinate]=revision+1;keys.Remove(coordinate);}}if(samples.Count>0){source.Set("_tracked_key_edits",true);source.Set("revision",revision+1);source.EmitChanged();}
    }
    public void apply_samples(Resource source,Settings samples)
    {source.Call("prepare");var edits=source.Get("edits").AsFloat32Array();foreach(var pair in samples){int index=pair.Key.AsInt32();if(index>=0&&index<edits.Length)edits[index]=(float)pair.Value.AsDouble();}source.Set("edits",edits);mark_samples_dirty(source,samples);}
    public void apply_material_samples(Resource source,Settings samples)
    {source.Call("prepare");var mask=source.Get("material_mask").AsFloat32Array();foreach(var pair in samples){int index=pair.Key.AsInt32();if(index>=0&&index<mask.Length)mask[index]=(float)Math.Clamp(pair.Value.AsDouble(),0,1);}source.Set("material_mask",mask);mark_samples_dirty(source,samples);}
    public Settings paint_material(Resource source,Vector2 center,double radius,double strength,double falloff,bool erase)
    {
        source.Call("prepare");var data=ReadSamples(source);var bounds=data.Bounds(center,radius);var before=new Settings();var after=new Settings();for(int z=bounds.Low.Y;z<=bounds.High.Y;z++)for(int x=bounds.Low.X;x<=bounds.High.X;x++){double distance=((new Vector2(x,z)-bounds.Center)*bounds.Spacing).Length();if(distance>radius)continue;int index=x+z*data.N;double weight=Math.Pow(Math.Max(0,1-distance/Math.Max(.001,radius)),Math.Max(.01,falloff)),value=Math.Clamp(data.Mask[index]+strength*weight*(erase?-1:1),0,1);if(Mathf.IsEqualApprox(value,data.Mask[index]))continue;before[index]=data.Mask[index];after[index]=value;}apply_material_samples(source,after);return new Settings {["before"]=before,["after"]=after};
    }
    public Settings sculpt(Resource source,Vector2 center,double radius,double strength,double falloff,int mode,double flattenHeight,Settings options)
    {
        source.Call("prepare");var data=ReadSamples(source);var bounds=data.Bounds(center,radius);var before=new Settings();var after=new Settings();var targets=new Settings();using var noise=new FastNoiseLite {Seed=Get(options,"seed",source.Get("seed")).AsInt32(),Frequency=(float)(1/Math.Max(.01,radius*.25))};var transfers=new Dictionary<int,double>();bool square=Get(options,"square",false).AsBool();
        for(int z=bounds.Low.Y;z<=bounds.High.Y;z++)for(int x=bounds.Low.X;x<=bounds.High.X;x++)
        {
            var offset=(new Vector2(x,z)-bounds.Center)*bounds.Spacing;double distance=square?Math.Max(Math.Abs(offset.X),Math.Abs(offset.Y)):offset.Length();if(distance>radius)continue;double weight=Math.Pow(Math.Max(0,1-distance/Math.Max(.001,radius)),Math.Max(.01,falloff)),old=data.Height(x,z),next=old,blend=Math.Clamp(strength*weight,0,1);int index=x+z*data.N;
            switch(mode)
            {
                case 0:next=old+strength*weight;break;case 1:next=old-strength*weight;break;
                case 2:next=Mathf.Lerp(old,(data.Height(x-1,z)+data.Height(x+1,z)+data.Height(x,z-1)+data.Height(x,z+1))*.25,blend);break;
                case 3:next=Mathf.Lerp(old,flattenHeight,blend);break;case 4:next=Mathf.Lerp(old,Get(options,"target",0.0).AsDouble(),blend);break;
                case 5:next=Mathf.Lerp(old,Mathf.Snapped(old,Math.Max(.01,Get(options,"terrace_step",.5).AsDouble())),blend);break;
                case 6:next=old+noise.GetNoise2Dv(center+offset)*strength*weight;break;case 7:next=old+strength*weight*weight;break;case 8:next=old-strength*weight*weight;break;
                case 9:next=old+(old-(data.Height(x-1,z)+data.Height(x+1,z)+data.Height(x,z-1)+data.Height(x,z+1))*.25)*Math.Clamp(strength*weight,0,.5);break;
                case 10:double average=0;for(int dz=-1;dz<=1;dz++)for(int dx=-1;dx<=1;dx++)average+=data.Height(x+dx,z+dz);next=Mathf.Lerp(old,average/9,blend);break;
                case 11:
                    double lower=old;int destination=index;foreach(var direction in new[]{Vector2I.Left,Vector2I.Right,Vector2I.Up,Vector2I.Down}){int nx=x+direction.X,nz=z+direction.Y;if(nx<0||nz<0||nx>=data.N||nz>=data.N)continue;double neighbor=data.Height(nx,nz);if(neighbor<lower){lower=neighbor;destination=nx+nz*data.N;}}double amount=Math.Max(0,old-lower)*blend*.25;if(amount>0){transfers[index]=transfers.GetValueOrDefault(index)-amount;transfers[destination]=transfers.GetValueOrDefault(destination)+amount;}break;
                case 12:
                    var stampValue=Get(options,"stamp");if(stampValue.VariantType==Variant.Type.Object&&stampValue.AsGodotObject() is Image image&&!image.IsEmpty()){var uv=offset/(float)Math.Max(.001,radius)*.5f+Vector2.One*.5f;int px=Math.Clamp((int)Math.Round(uv.X*(image.GetWidth()-1),MidpointRounding.AwayFromZero),0,image.GetWidth()-1),py=Math.Clamp((int)Math.Round(uv.Y*(image.GetHeight()-1),MidpointRounding.AwayFromZero),0,image.GetHeight()-1);var color=image.GetPixel(px,py);next=old+color.Luminance*color.A*strength*weight;}break;
            }
            if(Mathf.IsEqualApprox(old,next))continue;before[index]=data.Edits[index];double edit=next-data.Base[index]-data.WaterAt(index);after[index]=edit;targets[index]=edit;
        }
        foreach(var transfer in transfers){before[transfer.Key]=data.Edits[transfer.Key];double edit=data.Edits[transfer.Key]+transfer.Value;after[transfer.Key]=edit;targets[transfer.Key]=edit;}apply_samples(source,targets);return new Settings {["before"]=before,["after"]=after};
    }
}
