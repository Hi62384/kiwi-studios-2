using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class TerrainDataOperations
{
    private const long CacheLimit=64*1024*1024;
    private sealed record BaseEntry(float[] Heights,Settings Fields,long Bytes);
    private static readonly Dictionary<long,BaseEntry> BaseCache=new();
    private static readonly Queue<long> BaseOrder=new();
    private static readonly object BaseLock=new();
    private static long _baseBytes;
    private readonly TerrainGenerationOperations _generation=new();
    private readonly TerrainBiomeOperations _biomes=new();
    private readonly TerrainErosionOperations _erosion=new();
    public long cache_bytes(){lock(BaseLock)return _baseBytes;}
    internal static void ClearCache(){lock(BaseLock){foreach(var entry in BaseCache.Values)entry.Fields.Dispose();BaseCache.Clear();BaseOrder.Clear();_baseBytes=0;SampleCache.Clear();BiomeCache.Clear();WaterCache.Clear();}}
    public long data_bytes(Variant data)
    {
        switch(data.VariantType)
        {
            case Variant.Type.PackedFloat32Array:return data.AsFloat32Array().LongLength*4;case Variant.Type.PackedInt32Array:return data.AsInt32Array().LongLength*4;
            case Variant.Type.PackedVector2Array:return data.AsVector2Array().LongLength*8;case Variant.Type.PackedFloat64Array:return data.AsFloat64Array().LongLength*8;case Variant.Type.PackedInt64Array:return data.AsInt64Array().LongLength*8;
            case Variant.Type.PackedVector3Array:return data.AsVector3Array().LongLength*12;case Variant.Type.PackedColorArray:return data.AsColorArray().LongLength*16;case Variant.Type.PackedVector4Array:return data.AsVector4Array().LongLength*16;case Variant.Type.PackedByteArray:return data.AsByteArray().LongLength;
            case Variant.Type.Dictionary:long dictionary=0;foreach(var value in data.AsGodotDictionary().Values)dictionary+=data_bytes(value);return dictionary;
            case Variant.Type.Array:long array=0;foreach(var value in data.AsGodotArray())array+=data_bytes(value);return array;default:return 0;
        }
    }
    public long erosion_signature(Resource source)
    {using var values=new GArray();foreach(var operation in source.Get("erosion").AsGodotArray())values.Add(operation.As<Resource>().Call("signature"));return unchecked((uint)GD.Hash(values));}
    public long base_signature(Resource source)
    {
        int n=Math.Clamp(source.Get("resolution").AsInt32(),3,1025);var dimensions=source.Get("dimensions").AsVector2().Abs().Max(Vector2.One*.01f);source.Set("resolution",n);source.Set("dimensions",dimensions);var generation=source.Get("generation").As<Resource>();var biomes=source.Get("biomes").As<Resource>();using var fields=new GArray {dimensions,n,source.Get("seed"),source.Get("geology"),source.Get("base_height"),source.Get("amplitude"),source.Get("frequency"),generation!=null?_generation.signature(generation):0,erosion_signature(source),biomes!=null?_biomes.landform_signature(biomes):0};return unchecked((uint)GD.Hash(fields));
    }
    private static float[] ResizeMask(float[] old,int n)
    {
        if(old.Length==n*n)return old;var result=new float[n*n];int oldN=(int)Math.Floor(Math.Sqrt(old.Length));if(oldN<=1||oldN*oldN!=old.Length)return result;for(int z=0;z<n;z++)for(int x=0;x<n;x++){int ox=(int)Math.Round(x/(double)(n-1)*(oldN-1),MidpointRounding.AwayFromZero),oz=(int)Math.Round(z/(double)(n-1)*(oldN-1),MidpointRounding.AwayFromZero);result[x+z*n]=old[ox+oz*oldN];}return result;
    }
    private static float[] ResizeEdits(float[] old,int n)
    {
        if(old.Length==n*n)return old;var result=new float[n*n];int oldN=(int)Math.Floor(Math.Sqrt(old.Length));if(oldN<=1||oldN*oldN!=old.Length)return result;for(int z=0;z<n;z++)for(int x=0;x<n;x++){var p=new Vector2(x,z)/(n-1)*(oldN-1);var a=(Vector2I)p.Floor();var b=a.Min(Vector2I.One*(oldN-2));var f=p-(Vector2)b;result[x+z*n]=(float)Mathf.Lerp(Mathf.Lerp((double)old[b.X+b.Y*oldN],old[b.X+1+b.Y*oldN],f.X),Mathf.Lerp((double)old[b.X+(b.Y+1)*oldN],old[b.X+1+(b.Y+1)*oldN],f.X),f.Y);}return result;
    }
    public void prepare_data(Resource source,long key,Settings cancellation)
    {
        SampleCache.Remove(source);int n=source.Get("resolution").AsInt32();var dimensions=source.Get("dimensions").AsVector2();source.Set("_base_key",key);var heights=new float[n*n];source.Set("_base",heights);source.Get("_chunk_cache").AsGodotDictionary().Clear();source.Set("material_mask",ResizeMask(source.Get("material_mask").AsFloat32Array(),n));source.Set("edits",ResizeEdits(source.Get("edits").AsFloat32Array(),n));
        lock(BaseLock){if(BaseCache.TryGetValue(key,out var cached)){source.Set("_base",cached.Heights);source.Set("derived_fields",cached.Fields.Duplicate());source.Call("mark_all_dirty");return;}}
        long seed=source.Get("seed").AsInt64();double frequency=source.Get("frequency").AsDouble(),amplitude=source.Get("amplitude").AsDouble(),baseHeight=source.Get("base_height").AsDouble();using var noise=new FastNoiseLite {Seed=unchecked((int)seed),Frequency=(float)Math.Max(.000001,frequency),FractalType=FastNoiseLite.FractalTypeEnum.Fbm,FractalOctaves=4};var generation=source.Get("generation").As<Resource>();if(generation!=null)_generation.prepare(generation,seed,frequency);
        for(int z=0;z<n;z++){if(Cancelled(cancellation)){source.Set("_base",heights);return;}for(int x=0;x<n;x++){var point=new Vector2((float)(x/(double)(n-1)-.5),(float)(z/(double)(n-1)-.5))*dimensions;heights[x+z*n]=(float)(generation!=null?_generation.value(generation,point,dimensions,amplitude,baseHeight):baseHeight+noise.GetNoise2Dv(point)*amplitude);}}source.Set("_base",heights);var fields=new Settings();source.Set("derived_fields",fields);var biomes=source.Get("biomes").As<Resource>();int geology=source.Get("geology").AsInt32();if(biomes!=null&&_biomes.landform_signature(biomes)!=0){var modified=_biomes.apply_landforms(biomes,heights,n,dimensions,seed,cancellation,geology);if(Get(modified,"cancelled",false).AsBool()||!modified.ContainsKey("heights"))return;heights=modified["heights"].AsFloat32Array();source.Set("_base",heights);fields["initial_biomes"]=Get(modified,"initial_biomes",new Settings());}
        foreach(var value in source.Get("erosion").AsGodotArray())
        {
            var operation=value.As<Resource>();if(!operation.Get("enabled").AsBool())continue;using var effective=operation.Duplicate(true);double resistance=new[]{1.0,.35,.7,1.3,.25,.9}[Math.Clamp(geology,0,5)];effective.Set("strength",effective.Get("strength").AsDouble()*resistance);effective.Set("mobility",effective.Get("mobility").AsDouble()*resistance);var result=_erosion.apply(effective,heights,n,dimensions,cancellation);if(Get(result,"cancelled",false).AsBool())return;heights=result["heights"].AsFloat32Array();source.Set("_base",heights);var derived=result.Duplicate();derived.Remove("heights");fields[operation.Get("operation_id")]=derived;
        }
        if(generation!=null){var foundations=_generation.apply_foundations(generation,heights,n,dimensions,cancellation);if(foundations.Length!=heights.Length)return;heights=foundations;source.Set("_base",heights);}long bytes=heights.LongLength*4+data_bytes(fields);if(bytes<=CacheLimit)
        {
            lock(BaseLock){if(!BaseCache.ContainsKey(key)){while(BaseCache.Count>0&&(_baseBytes+bytes>CacheLimit||BaseCache.Count>=16)){long oldest=BaseOrder.Dequeue();var entry=BaseCache[oldest];_baseBytes-=entry.Bytes;BaseCache.Remove(oldest);entry.Fields.Dispose();}BaseCache[key]=new BaseEntry(heights,fields.Duplicate(),bytes);BaseOrder.Enqueue(key);_baseBytes+=bytes;}}
        }
        source.Call("mark_all_dirty");
    }
}
