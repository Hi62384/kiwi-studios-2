using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class TerrainDataOperations
{
    private readonly TerrainCaveOperations _caves=new();
    private readonly TerrainHydrologyOperations _hydrology=new();
    private static long Hash(Variant value)=>unchecked((uint)GD.Hash(value));
    public string[] validate(Resource source)
    {
        var errors=new List<string>();int geology=source.Get("geology").AsInt32(),n=source.Get("resolution").AsInt32();var dimensions=source.Get("dimensions").AsVector2();if(geology<0||geology>=6)errors.Add("Unknown terrain geology.");if(!dimensions.IsFinite()||dimensions.X<=0||dimensions.Y<=0)errors.Add("Terrain dimensions must be positive finite values.");if(n<3||n>1025)errors.Add("Terrain resolution must be from 3 to 1025 samples per side.");if(!double.IsFinite(source.Get("amplitude").AsDouble())||!double.IsFinite(source.Get("frequency").AsDouble())||!double.IsFinite(source.Get("base_height").AsDouble()))errors.Add("Terrain generation values must be finite.");var generation=source.Get("generation").As<Resource>();if(generation!=null)errors.AddRange(_generation.validate(generation));var hydrology=source.Get("hydrology").As<Resource>();if(hydrology!=null)errors.AddRange(_hydrology.validate(hydrology));var biomes=source.Get("biomes").As<Resource>();if(biomes!=null)errors.AddRange(_biomes.validate(biomes));foreach(var value in source.Get("caves").AsGodotArray()){var cave=value.As<Resource>();if(cave!=null)errors.AddRange(_caves.validate(cave));}return errors.ToArray();
    }
    public long cave_signature(Resource source)
    {using var values=new GArray();foreach(var value in source.Get("caves").AsGodotArray()){var cave=value.As<Resource>();values.Add(cave!=null?_caves.signature(cave):0);}using var fields=new GArray {values,source.Get("voxel_height"),source.Get("voxel_cell_budget")};return Hash(fields);}
    public long signature(Resource source)
    {
        using var fields=new GArray();foreach(string key in new[]{"dimensions","resolution","seed","geology","base_height","amplitude","frequency","edits","material_mask"})fields.Add(source.Get(key));var generation=source.Get("generation").As<Resource>();fields.Add(generation!=null?_generation.signature(generation):0);fields.Add(erosion_signature(source));fields.Add(cave_signature(source));foreach(string key in new[]{"lod_enabled","lod_bias","render_distance"})fields.Add(source.Get(key));var hydrology=source.Get("hydrology").As<Resource>();var biomes=source.Get("biomes").As<Resource>();fields.Add(hydrology!=null?_hydrology.signature(hydrology):0);fields.Add(biomes!=null?_biomes.signature(biomes):0);return Hash(fields);
    }
    public long climate_key(Resource source)
    {var biomes=source.Get("biomes").As<Resource>();using var values=new GArray {source.Get("_base_key"),source.Get("edits"),source.Get("water_key"),biomes!=null?_biomes.climate_signature(biomes):0};return Hash(values);}
    public long cave_climate_key(Resource source){using var values=new GArray {1,climate_key(source),cave_signature(source),source.Get("geology")};return Hash(values);}
    public long hydrology_key(Resource source){var hydrology=source.Get("hydrology").As<Resource>();using var values=new GArray {2,source.Get("_base_key"),source.Get("edits"),cave_signature(source),hydrology!=null?_hydrology.geometry_signature(hydrology):0};return Hash(values);}
    public long volume_signature(Resource source){using var values=new GArray {source.Get("_base_key"),source.Get("edits"),source.Get("water_delta"),cave_signature(source)};return Hash(values);}
    public long geometry_stamp(Resource source){using var values=new GArray {1,source.Get("_base_key"),source.Get("dimensions"),source.Get("resolution"),source.Get("edits"),source.Get("water_delta"),source.Get("material_mask"),cave_signature(source),source.Get("lod_enabled")};return Hash(values);}
    public Aabb chunk_bounds(Resource source,Vector2I coordinate)
    {int n=source.Get("resolution").AsInt32();var dimensions=source.Get("dimensions").AsVector2();var start=coordinate*32;var cells=new Vector2I(Math.Min(32,n-1-start.X),Math.Min(32,n-1-start.Y));var spacing=dimensions/(n-1);return new Aabb(new Vector3((float)((start.X/(double)(n-1)-.5)*dimensions.X),-100000,(float)((start.Y/(double)(n-1)-.5)*dimensions.Y)),new Vector3(cells.X*spacing.X,200000,cells.Y*spacing.Y)).Grow(.001f);}
    public bool needs_volume(Resource source,Vector2I coordinate)
    {var region=chunk_bounds(source,coordinate);foreach(var value in source.Get("caves").AsGodotArray()){var cave=value.As<Resource>();if(cave!=null&&cave.Get("enabled").AsBool()&&_caves.bounds(cave).Intersects(region))return true;}return false;}
    private static long LocalKey(Samples data,Vector2I coordinate,bool materials)
    {var start=(coordinate*32-Vector2I.One).Max(Vector2I.Zero);var end=((coordinate+Vector2I.One)*32+Vector2I.One).Min(Vector2I.One*(data.N-1));var values=new float[Math.Max(0,end.X-start.X+1)*Math.Max(0,end.Y-start.Y+1)];int index=0;for(int z=start.Y;z<=end.Y;z++)for(int x=start.X;x<=end.X;x++)values[index++]=materials?data.Mask[x+z*data.N]:(float)data.Height(x,z);return Hash(values);}
    public long local_samples_key(Resource source,Vector2I coordinate,bool materials)=>LocalKey(FreshSamples(source),coordinate,materials);
    private long VolumeKey(Resource source,Vector2I coordinate,Samples samples)
    {var region=chunk_bounds(source,coordinate);using var keys=new GArray();foreach(var value in source.Get("caves").AsGodotArray()){var cave=value.As<Resource>();if(cave!=null&&cave.Get("enabled").AsBool()&&_caves.bounds(cave).Intersects(region))keys.Add(_caves.local_signature(cave,region));}using var fields=new GArray {1,coordinate,samples.Dimensions,samples.N,source.Get("voxel_height"),LocalKey(samples,coordinate,false),keys};return Hash(fields);}
    public long volume_key(Resource source,Vector2I coordinate)=>VolumeKey(source,coordinate,FreshSamples(source));
    internal long PreparedVolumeKey(Resource source,Vector2I coordinate)=>VolumeKey(source,coordinate,ReadSamples(source));
    private long ChunkKey(Resource source,Vector2I coordinate,bool includePaint,Samples? samples=null)
    {
        var keys=source.Get("chunk_keys").AsGodotDictionary();if(!keys.TryGetValue(coordinate,out var cached)){samples??=ReadSamples(source);long heights=LocalKey(samples,coordinate,false),mask=LocalKey(samples,coordinate,true),cave=needs_volume(source,coordinate)?VolumeKey(source,coordinate,samples):0;using var noPaint=new GArray {coordinate,samples.Dimensions,samples.N,source.Get("lod_enabled"),heights,0,cave};using var paint=new GArray {coordinate,samples.Dimensions,samples.N,source.Get("lod_enabled"),heights,mask,cave};cached=new Settings {[false]=Hash(noPaint),[true]=Hash(paint)};keys[coordinate]=cached;}using var stamp=new GArray {cached.AsGodotDictionary()[includePaint],source.Get("lod_enabled")};return Hash(stamp);
    }
    public long chunk_geometry_key(Resource source,Vector2I coordinate,bool includePaint)=>ChunkKey(source,coordinate,includePaint);
    public bool prepare_geometry_keys(Resource source,Settings cancellation)
    {source.Call("prepare");long stamp=geometry_stamp(source),previous=source.Get("chunk_keys_stamp").AsInt64();var keys=source.Get("chunk_keys").AsGodotDictionary();if(stamp!=previous&&!source.Get("_tracked_key_edits").AsBool())keys.Clear();var samples=stamp!=previous?FreshSamples(source):ReadSamples(source);int side=(int)Math.Ceiling((samples.N-1)/32.0);for(int z=0;z<side;z++){if(Cancelled(cancellation))return false;for(int x=0;x<side;x++)ChunkKey(source,new Vector2I(x,z),true,samples);}source.Set("chunk_keys_stamp",stamp);source.Set("_tracked_key_edits",false);return true;}
    public void mark_all_dirty(Resource source)
    {if(source.Get("chunk_keys_stamp").AsInt64()!=geometry_stamp(source)){source.Get("chunk_keys").AsGodotDictionary().Clear();SampleCache.Remove(source);}source.Set("_tracked_key_edits",false);var dirty=source.Get("dirty_chunks").AsGodotDictionary();dirty.Clear();int side=(int)Math.Ceiling((source.Get("resolution").AsDouble()-1)/32);for(int z=0;z<side;z++)for(int x=0;x<side;x++)dirty[new Vector2I(x,z)]=0;}
}
