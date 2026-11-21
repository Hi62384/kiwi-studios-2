using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class WorldForestOperations : RefCounted
{
    private readonly WorldSourceOperations _sources=new();
    private readonly ModelNaturalSettings _natural=new();
    private readonly ModelNaturalGenerator _generator=new();
    private readonly RoadSectionOperations _sections=new();
    private readonly EnvironmentDataHash _hash=new();
    private static readonly string[] Layers={"Canopy","Subcanopy","Understory","Ground"};
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private static long Hash(GArray values)=>unchecked((uint)GD.Hash(values));
    public Resource create(Resource source,Vector3 center,string profile,Settings species)
    {
        var next=_sources.copy(source);var dimensions=source.Get("dimensions").AsVector2();var bounds=new Rect2(new Vector2(center.X,center.Z)-dimensions*.4f,dimensions*.8f).Intersection(new Rect2(-dimensions*.5f,dimensions));if(bounds.Size.X<1||bounds.Size.Y<1)bounds=new Rect2(-dimensions*.4f,dimensions*.8f);var forests=next.Get("forests").AsGodotArray();var variants=new GArray();long seed=source.Get("seed").AsInt64()+forests.Count*101;
        var forest=new Settings {["id"]=Guid.NewGuid().ToString("N"),["name"]=profile+" "+(forests.Count+1),["profile"]=profile,["bounds"]=bounds,["seed"]=seed,["density"]=profile=="Sparse Woodland"?.35:1.0,["enabled"]=true,["patch_scale"]=24.0,["patch_strength"]=.85,["budget"]=2000,["variants"]=variants,["biome_ids"]=Array.Empty<string>(),["height_range"]=new Vector2(-10000,10000),["slope_range"]=new Vector2(0,45),["humidity_range"]=new Vector2(0,1),["temperature_range"]=new Vector2(-10000,10000),["shore_range"]=new Vector2(0,1000000)};
        var choices=Get(species,profile,species["Temperate Forest"]).AsGodotArray();for(int layer=0;layer<Layers.Length;layer++)foreach(var value in choices[layer].AsGodotArray()){string kind=value.AsString();var settings=_natural.defaults(kind);settings["seed"]=Hash(new GArray {seed,layer,kind});settings["segments"]=6;settings["levels"]=1;settings["branches"]=5;settings["detail"]=6;settings["roots"]=2;settings["wind_strength"]=.12;if(layer==1){settings["height"]=settings["height"].AsDouble()*.55;settings["radius"]=settings["radius"].AsDouble()*.65;}variants.Add(new Settings {["layer"]=layer,["kind"]=kind,["settings"]=settings,["materials"]=_natural.materials(kind,settings)});}forests.Add(forest);return next;
    }
    public Resource component(Resource source,string key,string title,string parent)
    {string owner=source.Get("world_id").AsString(),id=owner+":forest:"+key;var item=new KiwiModelComponent();item.Set("id",id);item.Set("title",title);item.Set("parent_id",parent);item.Set("parameters",new Settings {["world_owner"]=owner,["world_generated"]=true,["world_key"]=id.StartsWith(owner,StringComparison.Ordinal)?id[owner.Length..]:id,["world_pose"]=item.Get("transform"),["world_structure"]=new Settings(),["world_materials"]=new GArray(),["world_mesh_key"]=0,["world_generated_visible"]=true});return item;}
    public Settings baseline(Resource rules)
    {var result=new Settings();foreach(var property in rules.GetPropertyList()){var usage=(PropertyUsageFlags)property["usage"].AsInt64();if((usage&PropertyUsageFlags.ScriptVariable)!=0&&(usage&PropertyUsageFlags.Storage)!=0){string name=property["name"].AsString();result[name]=_hash.value(rules.Get(name));}}return result;}
    public void preserve(Resource old,Resource rules,Settings defaults)
    {foreach(var key in baseline(old).Keys){string name=key.AsString();if(name is "terrain_id" or "exclude_polygons")continue;if(name is "paint_regions" or "erase_regions" or "overrides"||defaults.TryGetValue(name,out var expected)&&_hash.value(old.Get(name))!=expected.AsInt64())rules.Set(name,old.Get(name));}}
    public Vector2[] polygon(Vector2[] polygon,Transform3D pose)
    {var result=new Vector2[polygon.Length];for(int index=0;index<polygon.Length;index++){var local=pose*new Vector3(polygon[index].X,0,polygon[index].Y);result[index]=new Vector2(local.X,local.Z);}return result;}
    public Vector2[] rectangle(Rect2 bounds,Transform3D pose)=>polygon(new[]{bounds.Position,new Vector2(bounds.End.X,bounds.Position.Y),bounds.End,new Vector2(bounds.Position.X,bounds.End.Y)},pose);
    public Godot.Collections.Array<Vector2[]> development(Resource source,Settings layout,Settings graph,Transform3D pose,bool sidewalks)
    {
        var masks=new Godot.Collections.Array<Vector2[]>();foreach(var value in graph["edges"].AsGodotArray()){var road=value.AsGodotDictionary();if(Get(road,"mode","Ground").AsString()=="Tunnel")continue;var points=road["points"].AsVector3Array();for(int index=0;index<points.Length-1;index++){var a=new Vector2(points[index].X,points[index].Z);var b=new Vector2(points[index+1].X,points[index+1].Z);double clearance=sidewalks?road["width"].AsDouble()*.5+Get(road,"shoulder",0.0).AsDouble()+.1:_sections.outer_half(road)+.5;var side=(b-a).Orthogonal().Normalized()*(float)clearance;masks.Add(polygon(new[]{a-side,b-side,b+side,a+side},pose));}}
        foreach(var value in layout["plots"].AsGodotArray())masks.Add(polygon(value.AsGodotDictionary()["polygon"].AsVector2Array(),pose));foreach(var value in source.Get("exclusions").AsGodotArray()){var area=value.AsGodotDictionary();var points=Get(area,"polygon",Array.Empty<Vector2>()).AsVector2Array();if(Get(area,"exclude_vegetation",true).AsBool()&&points.Length>=3)masks.Add(polygon(points,pose));}foreach(var value in source.Get("occupied").AsGodotArray())masks.Add(polygon(value.AsGodotDictionary()["polygon"].AsVector2Array(),pose));foreach(var value in source.Get("regions").AsGodotArray()){var region=value.AsGodotDictionary();if(!Get(region,"enabled",true).AsBool())masks.Add(rectangle(region["bounds"].AsRect2(),pose));}return masks;
    }
}
