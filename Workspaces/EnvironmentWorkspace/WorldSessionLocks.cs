using Godot;
using System;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class WorldSessionOperations
{
    private static Settings[] Items(Resource source,string key)=>source.Get(key).AsGodotArray().Select(value=>value.AsGodotDictionary()).ToArray();
    private static bool Same(Settings[] items,Settings target)=>items.Any(item=>item.RecursiveEqual(target));
    private static bool HasId(Settings[] items,Settings target)=>items.Any(item=>item["id"].AsString()==target["id"].AsString());
    private static Rect2 SettlementBounds(Settings value)
    {var center=value["center"].AsVector3();float radius=Get(value,"radius",48.0).AsSingle();return new Rect2(new Vector2(center.X,center.Z)-Vector2.One*radius,Vector2.One*radius*2);}
    public string locked_conflict(Resource current,Resource desired)
    {
        var oldOccupied=Items(current,"occupied");var newOccupied=Items(desired,"occupied");var oldRoads=Items(current,"roads");var newRoads=Items(desired,"roads");var oldSettlements=Items(current,"settlements");var newSettlements=Items(desired,"settlements");var oldForests=Items(current,"forests");var newForests=Items(desired,"forests");var oldProps=Items(current,"prop_rules");var newProps=Items(desired,"prop_rules");
        foreach(var region in Items(current,"regions"))
        {
            if(!Get(region,"locked",false).AsBool())continue;string prefix="Unlock "+region["name"].AsString()+" before ";var bounds=region["bounds"].AsRect2();
            if(current.Get("terrain_dependency_key").AsInt64()!=desired.Get("terrain_dependency_key").AsInt64())return prefix+"regenerating it against changed terrain or water.";
            if(current.Get("connect_settlements").AsBool()!=desired.Get("connect_settlements").AsBool()||current.Get("connection_bridges").AsBool()!=desired.Get("connection_bridges").AsBool()||current.Get("connection_road_type").AsString()!=desired.Get("connection_road_type").AsString()||!current.Get("connection_overrides").AsGodotDictionary().RecursiveEqual(desired.Get("connection_overrides").AsGodotDictionary()))return prefix+"changing global settlement-connection rules.";
            foreach(var area in oldOccupied.Concat(newOccupied)){if(Same(oldOccupied,area)&&Same(newOccupied,area))continue;var rectangle=new[]{bounds.Position,new Vector2(bounds.End.X,bounds.Position.Y),bounds.End,new Vector2(bounds.Position.X,bounds.End.Y)};if(Geometry2D.IntersectPolygons(rectangle,area["polygon"].AsVector2Array()).Count>0)return prefix+"refreshing changed existing-object footprints inside it.";}
            if(current.Get("dimensions").AsVector2()!=desired.Get("dimensions").AsVector2()||current.Get("region_size").AsDouble()!=desired.Get("region_size").AsDouble())return prefix+"changing world or region bounds.";
            foreach(var road in oldRoads){var replacement=newRoads.FirstOrDefault(candidate=>candidate["id"].AsString()==road["id"].AsString())??new Settings();if(replacement.RecursiveEqual(road))continue;if(touches(road["points"].AsVector3Array(),bounds))return prefix+"editing or removing its roads.";}
            foreach(var road in newRoads)if(!HasId(oldRoads,road)&&touches(road["points"].AsVector3Array(),bounds))return prefix+"adding roads through it.";
            foreach(var settlement in oldSettlements)if(SettlementBounds(settlement).Intersects(bounds)&&!Same(newSettlements,settlement))return prefix+"changing its settlement.";
            foreach(var settlement in newSettlements)if(!HasId(oldSettlements,settlement)&&SettlementBounds(settlement).Intersects(bounds))return prefix+"adding a settlement through it.";
            foreach(var forest in oldForests)if(forest["bounds"].AsRect2().Intersects(bounds)&&!Same(newForests,forest))return prefix+"changing its forests.";
            foreach(var forest in newForests)if(forest["bounds"].AsRect2().Intersects(bounds)&&!HasId(oldForests,forest))return prefix+"adding a forest through it.";
            foreach(var rule in oldProps)if(rule["bounds"].AsRect2().Intersects(bounds)&&!Same(newProps,rule))return prefix+"changing its object placement.";
            foreach(var rule in newProps)if(rule["bounds"].AsRect2().Intersects(bounds)&&!HasId(oldProps,rule))return prefix+"adding object placement through it.";
        }
        return "";
    }
    public bool touches(Vector3[] points,Rect2 bounds)
    {
        var corners=new[]{bounds.Position,new Vector2(bounds.End.X,bounds.Position.Y),bounds.End,new Vector2(bounds.Position.X,bounds.End.Y)};
        for(int index=0;index<points.Length;index++){var point=new Vector2(points[index].X,points[index].Z);if(bounds.HasPoint(point))return true;if(index==0)continue;for(int border=0;border<4;border++)if(Geometry2D.SegmentIntersectsSegment(new Vector2(points[index-1].X,points[index-1].Z),point,corners[border],corners[(border+1)%4]).VariantType!=Variant.Type.Nil)return true;}return false;
    }
}
