using Godot;
using System;
using System.Linq;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;

public partial class WorldSiteOperations : RefCounted
{
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private static Settings Error(string message)=>new() {["error"]=message};
    private static Settings Cancelled()=>new() {["cancelled"]=true,["error"]="Site search canceled."};
    public Settings find(Resource source,int index,Settings cancellation)
    {if(!Get(cancellation,"enabled",false).AsBool())return Find(source,index,()=>false);var bridge=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/world/world_sites.gd");return Find(source,index,()=>bridge.Call("_cancel_requested",cancellation).AsBool());}
    internal Settings Find(Resource source,int index,Func<bool> cancelled)
    {
        var field=source.Get("terrain_field").As<RefCounted>();var settlements=source.Get("settlements").AsGodotArray();if(field==null||index<0||index>=settlements.Count)return Error("Choose a terrain and settlement before finding a site.");var settlement=settlements[index].AsGodotDictionary();double radius=settlement["radius"].AsDouble(),margin=radius+8;var dimensions=source.Get("dimensions").AsVector2();var bounds=new Rect2(-dimensions*.5f+Vector2.One*(float)margin,dimensions-Vector2.One*(float)margin*2);if(bounds.Size.X<=0||bounds.Size.Y<=0)return Error("This settlement is too large for the world. Reduce its radius or enlarge the world.");var masks=new List<(Rect2 Bounds,Vector2[] Polygon)>();
        foreach(var value in source.Get("exclusions").AsGodotArray().Concat(source.Get("occupied").AsGodotArray())){var area=value.AsGodotDictionary();if(!Get(area,"protected",true).AsBool())continue;var polygon=Get(area,"polygon",Array.Empty<Vector2>()).AsVector2Array();if(polygon.Length<3)continue;var rectangle=new Rect2(polygon[0],Vector2.Zero);foreach(var point in polygon)rectangle=rectangle.Expand(point);masks.Add((rectangle,polygon));}
        var otherBounds=new List<Rect2>();for(int other=0;other<settlements.Count;other++){var item=settlements[other].AsGodotDictionary();if(other==index||!Get(item,"enabled",true).AsBool())continue;var point=item["center"].AsVector3();float otherRadius=item["radius"].AsSingle();otherBounds.Add(new Rect2(new Vector2(point.X,point.Z)-Vector2.One*otherRadius,Vector2.One*otherRadius*2).Grow(6));}var locked=new List<Rect2>();foreach(var value in source.Get("regions").AsGodotArray()){var region=value.AsGodotDictionary();if(Get(region,"locked",false).AsBool())locked.Add(region["bounds"].AsRect2());}var nodes=source.Get("nodes").AsGodotDictionary().Values.Select(value=>value.AsVector3()).ToArray();
        Settings Sample(Vector2 point)=>field is WorldTerrainField native?native.sample(point):field.Call("sample",point).AsGodotDictionary();double best=double.PositiveInfinity;var chosen=Vector3.Zero;bool found=false;using var rng=new RandomNumberGenerator {Seed=unchecked((ulong)Get(settlement,"seed",source.Get("seed")).AsInt64())};var preferred=settlement["center"].AsVector3();bool water=field.Get("water_resolution").AsInt32()>0;double diagonal=Math.Max(1,dimensions.Length());
        for(int z=0;z<17;z++)
        {
            if(cancelled())return Cancelled();for(int x=0;x<17;x++)
            {
                var center=bounds.Position+new Vector2(x,z)/16*bounds.Size;var footprint=new Rect2(center-Vector2.One*(float)radius,Vector2.One*(float)radius*2);if(otherBounds.Any(other=>footprint.Grow(6).Intersects(other))||locked.Any(region=>region.Intersects(footprint)))continue;bool blocked=false;var rectangle=new[]{footprint.Position,new Vector2(footprint.End.X,footprint.Position.Y),footprint.End,new Vector2(footprint.Position.X,footprint.End.Y)};for(int mask=0;mask<masks.Count;mask++){if(mask%64==0&&cancelled())return Cancelled();var area=masks[mask];if(area.Bounds.Intersects(footprint)&&Geometry2D.IntersectPolygons(rectangle,area.Polygon).Count>0){blocked=true;break;}}if(blocked)continue;
                double low=double.PositiveInfinity,high=double.NegativeInfinity,slope=0,height=0;for(int sz=0;sz<3;sz++){for(int sx=0;sx<3;sx++){var point=center+new Vector2(sx-1,sz-1)*(float)radius;var surface=Sample(point);if(surface.Count==0||Get(surface,"water",false).AsBool()||surface["normal"].AsVector3().Y<.97){blocked=true;break;}double value=surface["height"].AsDouble();low=Math.Min(low,value);high=Math.Max(high,value);height+=value/9;slope+=1.0-surface["normal"].AsVector3().Y;}if(blocked)break;}if(blocked||high-low>Math.Max(.5,radius*.12))continue;
                double score=slope*30+(high-low)*2+center.DistanceTo(new Vector2(preferred.X,preferred.Z))/diagonal+rng.Randf()*.02;if(nodes.Length>0){double distance=double.PositiveInfinity;foreach(var node in nodes)distance=Math.Min(distance,center.DistanceTo(new Vector2(node.X,node.Z)));score+=distance/diagonal*.5;}if(water){double access=1;for(int direction=0;direction<8;direction++){var surface=Sample(center+Vector2.FromAngle((float)(direction*Math.Tau/8))*(float)radius*1.5f);if(Get(surface,"water",false).AsBool()){access=0;break;}}score+=access*.2;}if(score<best){best=score;chosen=new Vector3(center.X,(float)height,center.Y);found=true;}
            }
        }
        return new Settings {["position"]=chosen,["score"]=best,["error"]=found?"":"No dry, sufficiently flat site fits the settlement and its clearance. Reduce its radius or edit the terrain and exclusion masks."};
    }
}
