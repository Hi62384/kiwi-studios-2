using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class WorldSpatialIndex : RefCounted
{
    public double cell_size {get;set;}=64;
    public Godot.Collections.Array<Settings> entries {get;set;}=new();
    public Settings bins {get;set;}=new();
    public Godot.Collections.Array<int> large {get;set;}=new();
    private Vector2I Cell(Vector2 point)=>new((int)Math.Floor(point.X/cell_size),(int)Math.Floor(point.Y/cell_size));
    public void add(Rect2 bounds,Variant value)
    {
        int index=entries.Count;bounds=bounds.Abs();entries.Add(new Settings {["bounds"]=bounds,["value"]=value});var low=Cell(bounds.Position);var high=Cell(bounds.End);if((double)(high.X-low.X+1)*(high.Y-low.Y+1)>256){large.Add(index);return;}for(int z=low.Y;z<=high.Y;z++)for(int x=low.X;x<=high.X;x++){var cell=new Vector2I(x,z);if(!bins.ContainsKey(cell))bins[cell]=new GArray();bins[cell].AsGodotArray().Add(index);}
    }
    public GArray query(Rect2 bounds)
    {
        bounds=bounds.Abs();var found=new HashSet<int>();var result=new GArray();var low=Cell(bounds.Position);var high=Cell(bounds.End);var candidates=new List<int>(large);if((double)(high.X-low.X+1)*(high.Y-low.Y+1)>Math.Max(256,bins.Count*2)){for(int index=0;index<entries.Count;index++)candidates.Add(index);}else for(int z=low.Y;z<=high.Y;z++)for(int x=low.X;x<=high.X;x++)if(bins.TryGetValue(new Vector2I(x,z),out var values))foreach(var value in values.AsGodotArray())candidates.Add(value.AsInt32());foreach(int index in candidates){if(!found.Add(index))continue;var entry=entries[index];if(entry["bounds"].AsRect2().Intersects(bounds,true))result.Add(entry["value"]);}return result;
    }
    public Rect2 polygon_bounds(Vector2[] polygon)
    {if(polygon.Length==0)return new Rect2();var bounds=new Rect2(polygon[0],Vector2.Zero);foreach(var point in polygon)bounds=bounds.Expand(point);return bounds;}
}
