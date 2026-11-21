using Godot;
using System;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class WorldSettlementOperations : RefCounted
{
    private readonly RoadGeometryOperations _geometry=new();
    private readonly RoadSectionOperations _section=new();
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    public Resource create(Resource source,Vector3 center,string profile,Settings presets)
    {
        var next=new WorldSourceOperations().copy(source);string id=Guid.NewGuid().ToString("N");var template=new BuildingStyleOperations().apply(new BuildingSourceOperations().rectangular(6,8,1,true),profile=="Village"?"Cottage":"Modern",presets);var dimensions=source.Get("dimensions").AsVector2();double radius=Math.Clamp(Math.Min(dimensions.X,dimensions.Y)*.4,8,48),width=profile=="City"&&radius>=24?8:5;int blocks=Math.Clamp((int)Math.Floor(radius*2/(width+12)),1,3);
        var settlements=next.Get("settlements").AsGodotArray();settlements.Add(new Settings {["id"]=id,["name"]=profile+" "+(settlements.Count+1),["profile"]=profile,["center"]=center,["radius"]=radius,["blocks"]=blocks,["seed"]=unchecked((uint)GD.Hash(new GArray {source.Get("seed"),id})),["enabled"]=true,["locked"]=false,["template"]=template!=null?Variant.From(template):default,["height_min"]=1,["height_max"]=profile=="City"?6:2,["setback"]=2.0});return next;
    }
    public bool overlaps_road(Vector2[] polygon,Settings road,Vector3[] points)
    {
        if(points.Length==0)points=_geometry.sample(road["points"].AsVector3Array(),2);double margin=_section.outer_half(road)+.05;
        for(int segment=0;segment<points.Length-1;segment++)
        {
            var a=new Vector2(points[segment].X,points[segment].Z);var b=new Vector2(points[segment+1].X,points[segment+1].Z);if(Geometry2D.IsPointInPolygon(a,polygon))return true;
            for(int edge=0;edge<polygon.Length;edge++){var c=polygon[edge];var d=polygon[(edge+1)%polygon.Length];if(Geometry2D.SegmentIntersectsSegment(a,b,c,d).VariantType!=Variant.Type.Nil)return true;double distance=Math.Min(Math.Min(a.DistanceTo(Geometry2D.GetClosestPointToSegment(a,c,d)),b.DistanceTo(Geometry2D.GetClosestPointToSegment(b,c,d))),Math.Min(c.DistanceTo(Geometry2D.GetClosestPointToSegment(c,a,b)),d.DistanceTo(Geometry2D.GetClosestPointToSegment(d,a,b))));if(distance<margin)return true;}
        }
        return false;
    }
    public Settings road_access(Vector3 door,Settings road)
    {
        if(road.Count==0)return new Settings();var points=road["points"].AsVector3Array();double best=double.PositiveInfinity;var position=Vector3.Zero;
        for(int segment=0;segment<points.Length-1;segment++){var a=new Vector2(points[segment].X,points[segment].Z);var b=new Vector2(points[segment+1].X,points[segment+1].Z);var closest=Geometry2D.GetClosestPointToSegment(new Vector2(door.X,door.Z),a,b);double distance=closest.DistanceTo(new Vector2(door.X,door.Z));if(distance>=best)continue;best=distance;double t=a.DistanceTo(closest)/Math.Max(.001,a.DistanceTo(b));position=points[segment].Lerp(points[segment+1],(float)t);}
        var direction=new Vector3(door.X-position.X,0,door.Z-position.Z).Normalized();position+=direction*(float)(road["width"].AsDouble()*.5);return new Settings {["position"]=position,["direction"]=direction};
    }
    public Resource group(Resource document,string id,string title,string parent,string owner)
    {var item=new KiwiModelComponent();item.Set("id",id);item.Set("title",title);item.Set("parent_id",parent);item.Set("parameters",new Settings {["world_generated"]=true,["world_owner"]=owner,["world_key"]=id.StartsWith(owner,StringComparison.Ordinal)?id[owner.Length..]:id,["world_mesh_key"]=0,["world_pose"]=Transform3D.Identity});document.Get("components").AsGodotArray().Add(item);return item;}
    public Settings road(string id,string from,string to,Vector3[] points,double width,string settlement)
    {var result=_section.defaults(width<=3?"Rural Road":"Residential Street");result.Merge(new Settings {["id"]=id,["name"]="Street",["from"]=from,["to"]=to,["points"]=points,["width"]=width,["enabled"]=true,["mode"]="Ground",["settlement"]=settlement},true);return result;}
    public Vector2[] rectangle(Transform3D pose,double width,double depth)
    {var corners=new[]{new Vector2(-1,-1),new Vector2(1,-1),new Vector2(1,1),new Vector2(-1,1)};for(int i=0;i<corners.Length;i++){var point=pose*new Vector3((float)(corners[i].X*width*.5),0,(float)(corners[i].Y*depth*.5));corners[i]=new Vector2(point.X,point.Z);}return corners;}
}
