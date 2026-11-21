using Godot;
using System;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class WorldTerrainFieldOperations : RefCounted
{
    private static long Hash(Variant value)=>unchecked((uint)GD.Hash(value));
    internal static long Signature(Resource source)=>Hash(new GArray {source.Call("signature"),source.Get("water_key"),source.Get("water_delta")});
    public long signature(Resource source)=>Signature(source);
    private static Settings Result(string error,WorldTerrainField? field=null)=>new() {["error"]=error,["field"]=field!=null?Variant.From(field):default};
    public Settings capture(RefCounted session,string id,Resource source,Settings cache)
    {
        string terrainId=source.Get("terrain_id").AsString();if(terrainId.Length==0)return Result("");var info=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/world/world_terrain.gd").Call("context",session,id,source).AsGodotDictionary();string error=info["error"].AsString();if(error.Length>0)return Result(error);var terrain=info["terrain"].As<Resource>();long sourceKey=Signature(terrain),snapshotKey=Hash(new GArray {sourceKey,info["to_ground"],info["to_world"],id,terrainId}),cacheKey=Hash(new GArray {unchecked((long)terrain.GetInstanceId()),snapshotKey});var hydrology=terrain.Get("hydrology").As<Resource>();bool wet=hydrology!=null&&hydrology.Get("enabled").AsBool();if(wet&&!terrain.Call("water_valid").AsBool())return Result("Wait for terrain and water generation to finish before updating this world.");if(cache.TryGetValue(cacheKey,out var existing))return Result("",existing.As<WorldTerrainField>());
        var field=new WorldTerrainField {key=snapshotKey,root_id=id,terrain_id=terrainId,terrain_input=GodotObject.WeakRef(terrain),source_signature=sourceKey,to_ground=info["to_ground"].AsTransform3D(),to_world=info["to_world"].AsTransform3D(),dimensions=terrain.Get("dimensions").AsVector2(),resolution=Math.Min(129,terrain.Get("resolution").AsInt32())};var native=terrain.Call("height_snapshot").AsGodotDictionary();field.native_resolution=native["resolution"].AsInt32();field.native_base=native["base"].AsFloat32Array();field.native_edits=native["edits"].AsFloat32Array();field.native_water=native["water"].AsFloat32Array();var samples=new float[field.resolution*field.resolution];
        for(int z=0;z<field.resolution;z++)for(int x=0;x<field.resolution;x++){var point=new Vector2(x,z)/(field.resolution-1)*(field.native_resolution-1);var cell=new Vector2I((int)Math.Floor(point.X),(int)Math.Floor(point.Y));var f=point-(Vector2)cell;samples[x+z*field.resolution]=(float)Mathf.Lerp(Mathf.Lerp(field._sample_height(cell.X,cell.Y),field._sample_height(cell.X+1,cell.Y),f.X),Mathf.Lerp(field._sample_height(cell.X,cell.Y+1),field._sample_height(cell.X+1,cell.Y+1),f.X),f.Y);}field.heights=samples;
        var water=terrain.Get("water_data").AsGodotDictionary();int count=field.native_resolution*field.native_resolution;if(wet&&water.TryGetValue("levels",out var levels)&&water.TryGetValue("depth",out var depths)){var levelData=levels.AsFloat32Array();var depthData=depths.AsFloat32Array();if(levelData.Length==count&&depthData.Length==count){field.water_resolution=field.native_resolution;field.water_levels=levelData;field.water_depths=depthData;}}
        if(cache.Count>=8)cache.Remove(cache.Keys.First());cache[cacheKey]=field;return Result("",field);
    }
}
