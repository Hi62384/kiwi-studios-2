using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class WorldSettlementOperations
{
    private static Settings Surface(RefCounted field,Vector2 point)=>field is WorldTerrainField native?native.sample(point):field.Call("sample",point).AsGodotDictionary();
    public Settings layout(Resource source,Settings cancellation)
    {bool enabled=Get(cancellation,"enabled",false).AsBool();var bridge=enabled?GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/world/world_settlement.gd"):null;return Layout(source,()=>enabled&&bridge!.Call("_cancel_requested",cancellation).AsBool());}
    internal Settings Layout(Resource source,Func<bool> cancelled)
    {
        var initial=layout_initial(source);var nodes=initial["nodes"].AsGodotDictionary();var roads=initial["roads"].AsGodotArray();var plots=initial["plots"].AsGodotArray();var blocks=initial["blocks"].AsGodotArray();var warnings=new List<string>(initial["warnings"].AsStringArray());var settlements=source.Get("settlements").AsGodotArray();var field=source.Get("terrain_field").As<RefCounted>();var districts=new WorldDistrictOperations();
        foreach(var roadValue in roads){var current=roadValue.AsGodotDictionary();foreach(var settlementValue in settlements){var settlement=settlementValue.AsGodotDictionary();if(Get(current,"settlement","").AsString()!=settlement["id"].AsString()||!settlement.ContainsKey("road_type"))continue;var width=current["width"];current.Merge(_section.defaults(settlement["road_type"].AsString()),true);current["width"]=width;}}
        if(field!=null)foreach(var roadValue in roads)
        {
            var current=roadValue.AsGodotDictionary();var points=_geometry.sample(current["points"].AsVector3Array(),2);bool usable=true;
            for(int index=0;index<points.Length;index++){var surface=Surface(field,new Vector2(points[index].X,points[index].Z));if(surface.Count==0||Get(surface,"water",false).AsBool()){usable=false;break;}points[index].Y=(float)(surface["height"].AsDouble()+.03);if(index>0){double horizontal=new Vector2(points[index].X,points[index].Z).DistanceTo(new Vector2(points[index-1].X,points[index-1].Z));if(Math.Abs(points[index].Y-points[index-1].Y)/Math.Max(.01,horizontal)>.2){usable=false;break;}}}
            current["enabled"]=usable;if(usable){current["points"]=points;nodes[current["from"]]=points[0];nodes[current["to"]]=points[^1];}else warnings.Add("Street "+current["id"].AsString()+" leaves the terrain, crosses water or exceeds its grade limit.");
        }
        var claimed=new HashSet<string>();var spatial=new WorldSpatialIndex();var blockSource=new WorldBlockOperations();
        foreach(var settlementValue in settlements)
        {
            var settlement=settlementValue.AsGodotDictionary();if(!Get(settlement,"enabled",true).AsBool()||Get(settlement,"layout_mode","Grid").AsString()!="Road network")continue;
            var graph=new RoadNetworkOperations().Graph(source,cancelled,new Settings {["nodes"]=nodes,["roads"]=roads});if(Get(graph,"cancelled",false).AsBool())return new Settings {["cancelled"]=true};if(graph.ContainsKey("errors")){warnings.AddRange(graph["errors"].AsStringArray());continue;}
            var generated=blockSource.Extract(graph,cancelled);if(Get(generated,"cancelled",false).AsBool())return new Settings {["cancelled"]=true};warnings.AddRange(generated["warnings"].AsStringArray());var center=settlement["center"].AsVector3();float radius=settlement["radius"].AsSingle();var region=new Rect2(new Vector2(center.X,center.Z)-Vector2.One*radius,Vector2.One*radius*2);int usableBlocks=0;
            foreach(var blockValue in generated["blocks"].AsGodotArray())
            {
                var block=blockValue.AsGodotDictionary();string id=block["id"].AsString();if(claimed.Contains(id)||!region.Encloses(spatial.polygon_bounds(block["polygon"].AsVector2Array())))continue;claimed.Add(id);block["settlement"]=settlement["id"];block["district"]="Residential";var settings=districts.rules(block,settlement);blocks.Add(block);usableBlocks++;if(Get(settings,"density",1.0).AsDouble()<=0)continue;
                var lots=blockSource.Plots(block,districts.effective(settlement,settings),Math.Max(0,source.Get("max_building_plots").AsInt32()-plots.Count),cancelled);foreach(var plot in lots){if(!districts.accept(plot,settings))continue;plot["district"]=block["district"];plot["district_id"]=Get(block,"district_id","");plot["generation"]=settings;plots.Add(plot);}
            }
            if(usableBlocks==0)warnings.Add(Get(settlement,"name","Settlement").AsString()+": no usable bounded ground-road blocks fit this area. Draw a closed road network or enlarge the settlement radius.");
        }
        var connections=new WorldConnectionOperations().Augment(source,nodes,roads,cancelled);if(Get(connections,"cancelled",false).AsBool())return new Settings {["cancelled"]=true};warnings.AddRange(connections["warnings"].AsStringArray());
        return AcceptPlots(source,nodes,roads,plots,blocks,connections["connections"],warnings,field,districts,cancelled);
    }
    private Settings AcceptPlots(Resource source,Settings nodes,GArray roads,GArray plots,GArray blocks,Variant connections,List<string> warnings,RefCounted? field,WorldDistrictOperations districts,Func<bool> cancelled)
    {
        var allRoads=source.Get("roads").AsGodotArray().Duplicate();allRoads.AddRange(roads);var accepted=new Godot.Collections.Array<Settings>();var roadIndex=new WorldSpatialIndex();var masks=new WorldSpatialIndex();var plotIndex=new WorldSpatialIndex();var frontageIndex=new Settings();int samples=0;
        foreach(var value in allRoads)
        {
            if(cancelled())return new Settings {["cancelled"]=true};var current=value.AsGodotDictionary();frontageIndex[current["id"].AsString()]=current;if(!Get(current,"enabled",true).AsBool())continue;var points=_geometry.sample(current["points"].AsVector3Array(),2);samples+=points.Length;if(samples>65536)return new Settings {["nodes"]=nodes,["roads"]=roads,["plots"]=new GArray(),["blocks"]=blocks,["warnings"]=warnings.ToArray(),["connections"]=connections,["errors"]=new[]{"Settlement road sampling exceeds 65,536 points. Simplify roads or generate a smaller region."}};var polygon=points.Select(point=>new Vector2(point.X,point.Z)).ToArray();roadIndex.add(roadIndex.polygon_bounds(polygon).Grow((float)(_section.outer_half(current)+.1)),new Settings {["road"]=current,["points"]=points});
        }
        foreach(var value in source.Get("exclusions").AsGodotArray()){var area=value.AsGodotDictionary();if(Get(area,"protected",true).AsBool()&&Get(area,"polygon",Array.Empty<Vector2>()).AsVector2Array().Length>=3)masks.add(masks.polygon_bounds(area["polygon"].AsVector2Array()),area);}
        foreach(var value in source.Get("occupied").AsGodotArray()){var area=value.AsGodotDictionary();masks.add(masks.polygon_bounds(area["polygon"].AsVector2Array()),area);}
        foreach(var value in plots)
        {
            if(cancelled())return new Settings {["cancelled"]=true};var plot=value.AsGodotDictionary();
            if(!plot.ContainsKey("generation"))foreach(var settlementValue in source.Get("settlements").AsGodotArray())
            {
                var settlement=settlementValue.AsGodotDictionary();if(settlement["id"].AsString()!=plot["settlement"].AsString())continue;var block=new Settings {["id"]=plot["block"],["polygon"]=plot["polygon"],["district"]=plot["district"]};var settings=districts.rules(block,settlement);plot["district"]=block["district"];plot["district_id"]=Get(block,"district_id","");plot["generation"]=settings;
                if(settings.Count>0){double limit=Math.Max(4,Get(settings,"lot_size",64.0).AsDouble()-2*Get(settings,"setback",0.0).AsDouble());plot["width"]=Math.Min(plot["width"].AsDouble(),limit);plot["depth"]=Math.Min(plot["depth"].AsDouble(),limit);}
                foreach(var storedValue in blocks){var stored=storedValue.AsGodotDictionary();if(stored["id"].AsString()==plot["block"].AsString()){stored["district"]=block["district"];stored["district_id"]=Get(block,"district_id","");}}break;
            }
            if(!districts.accept(plot,Get(plot,"generation",new Settings()).AsGodotDictionary()))continue;var polygon=plot["polygon"].AsVector2Array();var bounds=masks.polygon_bounds(polygon);var frontage=Get(frontageIndex,plot["frontage"].AsString(),new Settings()).AsGodotDictionary();if(frontage.Count==0||!Get(frontage,"enabled",true).AsBool())continue;
            if(field!=null)
            {
                double maximum=double.NegativeInfinity,minimum=double.PositiveInfinity;var pose=plot["pose"].AsTransform3D();bool terrainOk=true;for(int z=0;z<3;z++)for(int x=0;x<3;x++){var point=pose*new Vector3((float)((x*.5-.5)*plot["width"].AsDouble()),0,(float)((z*.5-.5)*plot["depth"].AsDouble()));var surface=Surface(field,new Vector2(point.X,point.Z));if(surface.Count==0||Get(surface,"water",false).AsBool()||surface["normal"].AsVector3().Y<.94){terrainOk=false;continue;}maximum=Math.Max(maximum,surface["height"].AsDouble());minimum=Math.Min(minimum,surface["height"].AsDouble());}
                if(!terrainOk||maximum-minimum>1.2){warnings.Add("Plot "+plot["id"].AsString()+" has unsuitable terrain or slope.");continue;}var access=road_access(pose*new Vector3(0,0,(float)(-plot["depth"].AsDouble()*.5)),frontage);if(access.Count>0)maximum=Math.Max(maximum,access["position"].AsVector3().Y);pose.Origin=new Vector3(pose.Origin.X,(float)(maximum+.15),pose.Origin.Z);plot["pose"]=pose;plot["foundation_depth"]=Math.Max(.4,maximum-minimum+.4);
            }
            bool blocked=false;foreach(var areaValue in masks.query(bounds)){var area=areaValue.AsGodotDictionary();if(Get(area,"world","").AsString()==source.Get("world_id").AsString()&&Get(area,"plot","").AsString()==plot["id"].AsString())continue;if(Geometry2D.IntersectPolygons(polygon,area["polygon"].AsVector2Array()).Count>0){blocked=true;break;}}
            if(!blocked)foreach(var previous in plotIndex.query(bounds))if(Geometry2D.IntersectPolygons(polygon,previous.AsGodotDictionary()["polygon"].AsVector2Array()).Count>0){blocked=true;break;}
            if(!blocked)foreach(var candidateValue in roadIndex.query(bounds)){var candidate=candidateValue.AsGodotDictionary();if(overlaps_road(polygon,candidate["road"].AsGodotDictionary(),candidate["points"].AsVector3Array())){blocked=true;break;}}
            if(!blocked){accepted.Add(plot);plotIndex.add(bounds,plot);if(accepted.Count>=source.Get("max_building_plots").AsInt32()){warnings.Add("World plot budget reached; increase the budget to populate more frontage.");break;}}
        }
        return new Settings {["nodes"]=nodes,["roads"]=roads,["plots"]=accepted,["blocks"]=blocks,["warnings"]=warnings.ToArray(),["connections"]=connections};
    }
}
