using Godot;
using System;
using System.Linq;
using Settings=Godot.Collections.Dictionary;

public partial class TerrainDataOperations
{
    public bool volumes_valid(Resource source)
    {
        source.Call("prepare");long key=volume_signature(source);if(key==source.Get("_volume_validity_key").AsInt64())return source.Get("_volume_validity").AsBool();source.Set("_volume_validity_key",key);source.Set("_volume_validity",false);var samples=FreshSamples(source);int side=(int)Math.Ceiling((samples.N-1)/32.0);var volumes=source.Get("volume_chunks").AsGodotDictionary();for(int z=0;z<side;z++)for(int x=0;x<side;x++){var coordinate=new Vector2I(x,z);if(needs_volume(source,coordinate)&&(!volumes.TryGetValue(coordinate,out var data)||Get(data.AsGodotDictionary(),"key",-1).AsInt64()!=VolumeKey(source,coordinate,samples)))return false;}source.Set("_volume_validity",true);return true;
    }
    public bool prepare_volumes(Resource source,Settings cancellation,Settings progress)
    {
        Prepare(source,cancellation);source.Set("volume_status", "");source.Set("volume_chunks_rebuilt",0);var live=new System.Collections.Generic.HashSet<Vector2I>();long usedCells=0,usedVertices=0;int completed=0;var samples=FreshSamples(source);int side=(int)Math.Ceiling((samples.N-1)/32.0);var volumes=source.Get("volume_chunks").AsGodotDictionary();var keys=source.Get("chunk_keys").AsGodotDictionary();long budget=source.Get("voxel_cell_budget").AsInt64();
        for(int z=0;z<side;z++)for(int x=0;x<side;x++)
        {
            if(Cancelled(cancellation))return false;var coordinate=new Vector2I(x,z);if(needs_volume(source,coordinate))
            {
                live.Add(coordinate);long key=VolumeKey(source,coordinate,samples);var data=Get(volumes,coordinate,new Settings()).AsGodotDictionary();if(Get(data,"key",-1).AsInt64()!=key)
                {
                    using var mesher=new TerrainVolumeMesher();data=mesher.build(source,coordinate,source.Get("caves").AsGodotArray(),source.Get("voxel_height").AsDouble(),(int)Math.Clamp(budget-usedCells,1,int.MaxValue),cancellation);if(Get(data,"cancelled",false).AsBool())return false;string error=Get(data,"error", "").AsString();if(error.Length>0){source.Set("volume_status",error);return false;}data.Remove("caves");data.Remove("cave_bounds");data["key"]=key;volumes[coordinate]=data;source.Set("volume_chunks_rebuilt",source.Get("volume_chunks_rebuilt").AsInt64()+1);keys.Remove(coordinate);source.Set("_tracked_key_edits",true);
                }
                usedCells+=Get(data,"cells",0).AsInt64();usedVertices+=Get(data,"vertices",Array.Empty<Vector3>()).AsVector3Array().LongLength;if(usedCells>budget||usedVertices>500000){source.Set("volume_status","Cave geometry budget exceeded. Reduce its extent or voxel detail.");return false;}
            }
            completed++;if(Get(progress,"enabled",false).AsBool())GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/environment_terrain.gd").Call("_report_progress",progress,completed/(double)Math.Max(1,side*side));
        }
        foreach(var coordinate in volumes.Keys.ToArray())if(!live.Contains(coordinate.AsVector2I())){volumes.Remove(coordinate);keys.Remove(coordinate);source.Set("_tracked_key_edits",true);}source.Set("_volume_validity_key",volume_signature(source));source.Set("_volume_validity",true);return true;
    }
}
