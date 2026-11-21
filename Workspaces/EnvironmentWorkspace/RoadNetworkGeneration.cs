using Godot;
using System;
using System.Linq;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class RoadNetworkOperations
{
    private static Settings Stopped()=>new() {["document"]=default,["errors"]=Array.Empty<string>(),["warnings"]=Array.Empty<string>(),["cancelled"]=true};
    private static Settings Failed(string[] errors,string[]? warnings=null)=>new() {["document"]=default,["errors"]=errors,["warnings"]=warnings??Array.Empty<string>()};
    public Settings generate(Resource source,Settings cancellation,Resource? development)=>Generate(source,cancellation,development);
    internal Settings Generate(Resource source,Settings cancellation,Resource? development)=>GenerateCore(source,cancellation,development,Cancellation(cancellation));
    internal Settings Generate(Resource source,Func<bool> cancelled,Resource? development=null)
    {
        var state=new Settings {["enabled"]=true,["callback"]=Callable.From(cancelled)};
        try{return GenerateCore(source,state,development,cancelled);}finally{state.Clear();}
    }
    private Settings GenerateCore(Resource source,Settings cancellation,Resource? development,Func<bool> cancelled)
    {
        var errors=source.Call("validate").AsStringArray();if(errors.Length>0)return Failed(errors);if(cancelled())return Stopped();
        var document=development??new KiwiModelDocument();
        string owner=source.Get("world_id").AsString();
        if(development!=null)
        {
            var existing=development.Call("component",owner).As<Resource>();var parameters=existing.Get("parameters").AsGodotDictionary();parameters["world_source"]=source;
            var population=Populate(development,source,new Settings {["plots"]=Get(parameters,"world_plots",new GArray())},parameters["world_graph"].AsGodotDictionary(),cancelled);
            if(Get(population,"cancelled",false).AsBool())return Stopped();var failures=population["errors"].AsStringArray().Concat(development.Call("validate").AsStringArray()).ToArray();
            return new Settings {["document"]=failures.Length==0?Variant.From(development):default,["errors"]=failures,["warnings"]=population["warnings"],["settings"]=population["settings"],["development_reused"]=true};
        }
        var settlement=new WorldSettlementOperations();
        var layout=settlement.Layout(source,cancelled);if(Get(layout,"cancelled",false).AsBool())return Stopped();
        if(Get(layout,"errors",Array.Empty<string>()).AsStringArray().Length>0)return Failed(layout["errors"].AsStringArray(),layout["warnings"].AsStringArray());
        var graphData=Graph(source,cancelled,layout);if(Get(graphData,"cancelled",false).AsBool())return Stopped();if(graphData.ContainsKey("errors"))return Failed(graphData["errors"].AsStringArray());
        var realJunctions=junction_plan(graphData);var junctions=new Settings();var visibleEdges=new Settings();
        var root=new KiwiModelComponent();root.Set("id",owner);root.Set("title","World");var rootParameters=root.Get("parameters").AsGodotDictionary();rootParameters["world_source"]=source;rootParameters["world_graph"]=graphData;document.Get("components").AsGodotArray().Add(root);
        var section=new RoadSectionOperations();var structures=new RoadStructureOperations();
        foreach(var value in graphData["edges"].AsGodotArray())
        {
            if(cancelled())return Stopped();var edge=value.AsGodotDictionary();double start=realJunctions.ContainsKey(edge["from"])?edge["width"].AsDouble():0,end=realJunctions.ContainsKey(edge["to"])?edge["width"].AsDouble():0;
            var points=_geometry.trim(edge["points"].AsVector3Array(),start,end);var sectionSource=edge.Duplicate();sectionSource["distance_start"]=Get(edge,"distance_start",0.0).AsDouble()+start;var generated=section.build(points,sectionSource,cancellation);
            if(Get(generated,"cancelled",false).AsBool())return Stopped();if(generated["errors"].AsStringArray().Length>0)return Failed(generated["errors"].AsStringArray());
            string id=owner+":road:"+edge["id"].AsString();var road=item(document,id,Get(edge,"name","Road").AsString(),owner,generated["surface"].As<Resource>(),section.material(source,edge,"surface"),"");var parameters=road.Get("parameters").AsGodotDictionary();parameters["world_road"]=edge["id"];var midpoint=points[points.Length/2];parameters["world_region"]=source.Call("region_at",new Vector2(midpoint.X,midpoint.Z));parameters["road_type"]=Get(edge,"type","Residential Street");if(edge.ContainsKey("connection"))parameters["world_connection"]=edge["connection"];
            foreach(var regionValue in source.Get("regions").AsGodotArray()){var region=regionValue.AsGodotDictionary();if(region["id"].AsString()==parameters["world_region"].AsString())road.Set("visible",Get(region,"enabled",true));}
            parameters["world_generated_visible"]=road.Get("visible");visibleEdges[edge["id"]]=road.Get("visible");string mode=Get(edge,"mode","Ground").AsString();
            void Detail(Resource child,string detail="") {child.Set("visible",road.Get("visible"));var data=child.Get("parameters").AsGodotDictionary();data["world_generated_visible"]=child.Get("visible");data["world_region"]=parameters["world_region"];if(detail.Length>0)data["road_detail"]=detail;}
            foreach(string detail in new[]{"shoulders","sidewalks","curbs","markings"})if(generated.ContainsKey(detail)&&(mode=="Ground"||detail=="markings"))Detail(item(document,id+":"+detail,detail.Capitalize(),id,generated[detail].As<Resource>(),section.material(source,edge,detail),owner),detail);
            if(mode=="Bridge")
            {
                var field=source.Get("terrain_field").As<RefCounted>();var ground=new Settings {["enabled"]=Get(edge,"auto_piers",false)};ground["callback"]=Callable.From<Vector2,Settings>(point=>field==null?new Settings():field is WorldTerrainField native?native.sample(point):field.Call("sample",point).AsGodotDictionary());
                var structure=structures.bridge(points,edge["width"].AsDouble(),Get(edge,"pier_height",8.0).AsDouble(),ground,Get(edge,"_cross_sections",new Settings()).AsGodotDictionary());ground.Clear();road.Set("mesh",structure["deck"]);var mesh=structure["deck"].As<Resource>();parameters["world_mesh_key"]=unchecked((uint)GD.Hash(new GArray {mesh.Get("vertices"),mesh.Get("faces")}));
                foreach(string part in new[]{"railings","supports"}){var geometry=structure[part].As<Resource>();if(geometry.Get("faces").AsGodotArray().Count>0)Detail(item(document,id+":"+part,part.Capitalize(),id,geometry,source.Get("shoulder_material").As<Material>()??source.Get("road_material").As<Material>(),owner));}
            }
            for(int side=0;side<2;side++){var nodeId=edge[side==0?"from":"to"];if(!realJunctions.ContainsKey(nodeId))continue;if(!junctions.ContainsKey(nodeId))junctions[nodeId]=new GArray();junctions[nodeId].AsGodotArray().Add(new Settings {["point"]=side==0?points[0]:points[^1],["direction"]=(side==0?points[1]-points[0]:points[^2]-points[^1]).Normalized(),["width"]=edge["width"],["road"]=edge});}
        }
        foreach(var pair in junctions)
        {
            var ends=pair.Value.AsGodotArray();var road=item(document,owner+":junction:"+pair.Key.AsString(),"Junction",owner,_geometry.junction(graphData["nodes"].AsGodotDictionary()[pair.Key].AsVector3(),ends),source.Get("road_material").As<Material>(),"");bool visible=false;foreach(var edgeId in graphData["adjacency"].AsGodotDictionary()[pair.Key].AsGodotArray())visible|=Get(visibleEdges,edgeId,false).AsBool();road.Set("visible",visible);road.Get("parameters").AsGodotDictionary()["world_generated_visible"]=visible;
            foreach(var detail in section.junction_details(ends)){var child=item(document,road.Get("id").AsString()+":"+detail.Key.AsString(),"Junction "+detail.Key.AsString(),road.Get("id").AsString(),detail.Value.As<Resource>(),section.material(source,new Settings(),detail.Key.AsString()),owner);child.Set("visible",visible);var data=child.Get("parameters").AsGodotDictionary();data["world_generated_visible"]=visible;data["road_detail"]=detail.Key;}
        }
        foreach(var value in source.Get("roads").AsGodotArray()){var road=value.AsGodotDictionary();if(!Get(road,"enabled",true).AsBool()||Get(road,"mode","Ground").AsString()!="Tunnel")continue;var portals=structures.portals(Get(road,"portal_points",road["points"]).AsVector3Array(),road["width"].AsDouble(),true,true,Get(road,"portal_frames",new GArray()).AsGodotArray());item(document,owner+":portals:"+road["id"].AsString(),"Tunnel portals",owner,portals,source.Get("shoulder_material").As<Material>()??source.Get("road_material").As<Material>(),"");}
        var architecture=settlement.Build(document,source,layout,cancelled);if(Get(architecture,"cancelled",false).AsBool())return Stopped();var forests=Populate(document,source,layout,graphData,cancelled);if(Get(forests,"cancelled",false).AsBool())return Stopped();forests["settings"].AsGodotDictionary().Merge(Get(architecture,"settings",new Settings()).AsGodotDictionary(),true);
        var failuresAll=errors.Concat(architecture["errors"].AsStringArray()).Concat(forests["errors"].AsStringArray()).Concat(document.Call("validate").AsStringArray()).ToArray();var warnings=graphData["warnings"].AsStringArray().Concat(layout["warnings"].AsStringArray()).Concat(architecture["warnings"].AsStringArray()).Concat(forests["warnings"].AsStringArray()).ToArray();rootParameters["world_plots"]=layout["plots"];rootParameters["world_blocks"]=layout["blocks"];rootParameters["world_connections"]=layout["connections"];
        return new Settings {["document"]=failuresAll.Length==0?Variant.From(document):default,["errors"]=failuresAll,["warnings"]=warnings,["settings"]=forests["settings"]};
    }
}
