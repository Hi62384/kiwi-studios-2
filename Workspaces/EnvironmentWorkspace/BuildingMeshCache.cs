using Godot;
using System;
using System.Collections.Generic;
using System.Security.Cryptography;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class BuildingMeshCache : RefCounted
{
    public const long Limit=64*1024*1024;
    private sealed record Entry(Resource Mesh,long Bytes);
    private static readonly Dictionary<string,Entry> Entries=new(StringComparer.Ordinal);
    private static readonly LinkedList<string> Order=new();
    private static readonly object Gate=new();
    private static long _bytes,_hits,_misses;
    private readonly ModelMeshOperations _meshes=new();
    private static string Key(string kind,GArray fields)=>kind+":"+Convert.ToHexString(SHA256.HashData(GD.VarToBytes(fields))).ToLowerInvariant();
    public Settings lookup(string kind,GArray fields)
    {
        string key=Key(kind,fields);lock(Gate){if(Entries.TryGetValue(key,out var found)){_hits++;Order.Remove(key);Order.AddLast(key);return new Settings {["key"]=key,["mesh"]=_meshes.copy_mesh(found.Mesh)};}_misses++;return new Settings {["key"]=key,["mesh"]=default};}
    }
    public void store(string key,Resource result)
    {
        long bytes=result.Get("vertices").AsVector3Array().LongLength*12+result.Get("materials").AsInt32Array().LongLength*4;foreach(var face in result.Get("faces").AsGodotArray())bytes+=face.AsInt32Array().LongLength*4+32;foreach(var uv in result.Get("uv").AsGodotArray())bytes+=uv.AsVector2Array().LongLength*8+32;
        lock(Gate)
        {
            if(bytes>Limit||Entries.ContainsKey(key))return;
            while(Order.Count>0&&(_bytes+bytes>Limit||Order.Count>=256)){string oldest=Order.First!.Value;Order.RemoveFirst();var removed=Entries[oldest];_bytes-=removed.Bytes;Entries.Remove(oldest);removed.Mesh.Dispose();}
            Entries[key]=new Entry(_meshes.copy_mesh(result),bytes);_bytes+=bytes;Order.AddLast(key);
        }
    }
    internal Resource? GetOrBuild(string kind,GArray fields,Func<Resource?> build)
    {var found=lookup(kind,fields);var cached=found["mesh"].As<Resource>();if(cached!=null)return cached;var result=build();if(result!=null)store(found["key"].AsString(),result);return result;}
    public Settings statistics(){lock(Gate)return new Settings {["bytes"]=_bytes,["entries"]=Entries.Count,["hits"]=_hits,["misses"]=_misses};}
    public void clear()=>ClearCache();
    internal static void ClearCache(){lock(Gate){foreach(var entry in Entries.Values)entry.Mesh.Dispose();Entries.Clear();Order.Clear();_bytes=0;_hits=0;_misses=0;}}
}
