using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class WorldSettlementOperations
{
    public Settings build(Resource document,Resource source,Settings generated,Settings cancellation)
    {
        bool enabled=Get(cancellation,"enabled",false).AsBool();var bridge=enabled?GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/world/world_settlement.gd"):null;
        return Build(document,source,generated,()=>enabled&&bridge!.Call("_cancel_requested",cancellation).AsBool());
    }
    internal Settings Build(Resource document,Resource source,Settings generated,Func<bool> cancelled)
    {
        var warnings=new List<string>();var errors=new List<string>();int count=0;var settings=new Settings();string owner=source.Get("world_id").AsString();
        var districts=new WorldDistrictOperations();var buildings=new BuildingSourceOperations();var geometry=new BuildingGeometryOperations();var sessions=new BuildingSessionOperations();
        Settings Stopped()=>new() {["errors"]=errors.ToArray(),["warnings"]=warnings.ToArray(),["cancelled"]=true};
        foreach(var value in source.Get("settlements").AsGodotArray())
        {
            var settlement=value.AsGodotDictionary();if(!Get(settlement,"enabled",true).AsBool())continue;var settlementGroup=group(document,owner+":settlement:"+settlement["id"].AsString(),Get(settlement,"name","Settlement").AsString(),owner,owner);settlementGroup.Get("parameters").AsGodotDictionary()["world_settlement"]=settlement["id"];
            foreach(var plotValue in generated["plots"].AsGodotArray())
            {
                var plot=plotValue.AsGodotDictionary();if(plot["settlement"].AsString()!=settlement["id"].AsString())continue;var plotSettings=districts.effective(settlement,Get(plot,"generation",new Settings()).AsGodotDictionary());var template=Get(plotSettings,"template").As<Resource>();if(template==null){errors.Add("Settlement "+settlement["id"].AsString()+" has no architectural template.");continue;}if(cancelled())return Stopped();
                var plotGroup=group(document,owner+":plot:"+plot["id"].AsString(),plot["district"].AsString()+" plot",settlementGroup.Get("id").AsString(),owner);var parameters=plotGroup.Get("parameters").AsGodotDictionary();parameters["world_plot"]=plot["id"];parameters["polygon"]=plot["polygon"];var pose=plot["pose"].AsTransform3D();string regionId=source.Call("region_at",new Vector2(pose.Origin.X,pose.Origin.Z)).AsString();bool visible=true;
                foreach(var regionValue in source.Get("regions").AsGodotArray()){var region=regionValue.AsGodotDictionary();if(region["id"].AsString()==regionId)visible=Get(region,"enabled",true).AsBool();}plotGroup.Set("visible",visible);parameters["world_region"]=regionId;parameters["world_generated_visible"]=visible;
                var overrides=source.Get("plot_overrides").AsGodotDictionary();if(Get(Get(overrides,plot["id"].AsString(),new Settings()).AsGodotDictionary(),"reserved",false).AsBool())continue;if(count>=source.Get("max_building_plots").AsInt32()){warnings.Add("World building-plot budget reached. Increase the plot budget or reduce layout density.");break;}
                using var rng=new RandomNumberGenerator();rng.Seed=unchecked((uint)GD.Hash(new GArray {Get(plotSettings,"seed",1),plot["id"]}));int maximum=Math.Clamp(Get(plotSettings,"height_max",2).AsInt32(),1,8);string district=plot["district"].AsString();if(Get(plot,"generation",new Settings()).AsGodotDictionary().Count==0){if(district is "Residential" or "Rural")maximum=Math.Min(2,maximum);if(district=="Industrial")maximum=1;}int minimum=Math.Clamp(Get(plotSettings,"height_min",1).AsInt32(),1,maximum);if(district=="Downtown"&&maximum>=3)minimum=Math.Max(3,minimum);int levels=rng.RandiRange(minimum,maximum);double width=plot["width"].AsDouble(),depth=plot["depth"].AsDouble();var authored=buildings.rectangular(width,depth,levels,false);string buildingId=owner+":building:"+plot["id"].AsString();authored.Set("source_id",buildingId);authored.Set("seed",rng.Randi());var materials=authored.Get("materials").AsGodotArray();foreach(var material in template.Get("materials").AsGodotArray())materials.Add(material);
                foreach(string key in new[]{"style","wall_thickness","facade_detail"})authored.Set(key,template.Get(key));authored.Set("roof_type",district=="Downtown"?0:district=="Industrial"?2:rng.RandiRange(1,3));authored.Set("roof_pitch",rng.RandfRange(20,45));var floors=authored.Get("floors").AsGodotArray();
                if(district=="Industrial"){var floor=floors[0].AsGodotDictionary();floor["height"]=3.6;var opening=floor["walls"].AsGodotArray()[0].AsGodotDictionary()["openings"].AsGodotArray()[0].AsGodotDictionary();opening["width"]=Math.Min(2.8,width*.6);opening["height"]=2.8;authored.Set("facade_detail",6);}
                for(int level=0;level<levels-1;level++)authored.Get("stairs").AsGodotArray().Add(new Settings {["id"]="core:"+level,["from"]=floors[level].AsGodotDictionary()["id"],["to"]=floors[level+1].AsGodotDictionary()["id"],["type"]=0,["position"]=new Vector2((float)(-width*.35),(float)(-depth*.3)),["width"]=.9,["length"]=Math.Min(4,depth-2),["steps"]=18});authored.Set("foundation_depth",Get(plot,"foundation_depth",.4));
                if(count>=source.Get("eager_building_limit").AsInt32())
                {
                    var lazy=new KiwiModelComponent();lazy.Set("id",buildingId);lazy.Set("parent_id",plotGroup.Get("id"));lazy.Set("title",authored.Get("title"));lazy.Set("transform",pose);lazy.Set("mesh",new WorldBuildingMassing().mesh(authored));var surfaces=lazy.Get("surface_materials").AsGodotArray();foreach(var material in materials)surfaces.Add(material);
                    lazy.Set("parameters",new Settings {["architecture_source"]=authored,["architecture_type"]="building",["architecture_owner"]=buildingId,["architecture_key"]="",["world_lazy_building"]=true,["world_owner"]=owner,["world_generated"]=true,["world_key"]=buildingId[owner.Length..],["world_pose"]=pose,["world_plot"]=plot["id"],["world_region"]=regionId,["world_generated_visible"]=visible,["world_materials"]=surfaces.Duplicate(),["world_structure"]=new Settings(),["world_architecture_source_key"]=sessions.source_key(authored)});lazy.Set("visible",visible);sessions.mark(lazy);document.Get("components").AsGodotArray().Add(lazy);settings[buildingId]=new Settings {["kind"]="building",["collision"]=true};count++;continue;
                }
                var output=geometry.Generate(authored,cancelled);if(Get(output,"cancelled",false).AsBool())return Stopped();var result=Get(output,"document").As<Resource>();if(result==null||output["errors"].AsStringArray().Length>0){errors.AddRange(output["errors"].AsStringArray());continue;}
                foreach(var partValue in result.Get("components").AsGodotArray())
                {
                    var part=partValue.As<Resource>();string partId=part.Get("id").AsString();if(partId==buildingId){part.Set("parent_id",plotGroup.Get("id"));part.Set("transform",pose);}sessions.mark(part);var data=part.Get("parameters").AsGodotDictionary();data["world_generated"]=true;data["world_owner"]=owner;data["world_key"]=partId.StartsWith(owner,StringComparison.Ordinal)?partId[owner.Length..]:partId;data["world_pose"]=part.Get("transform");var mesh=part.Get("mesh").As<Resource>();data["world_mesh_key"]=mesh==null?0:unchecked((uint)GD.Hash(new GArray {mesh.Get("vertices"),mesh.Get("faces")}));data["world_plot"]=plot["id"];data["world_generated_visible"]=part.Get("visible");data["world_materials"]=part.Get("surface_materials").AsGodotArray().Duplicate();data["world_structure"]=part.Get("structural").AsGodotDictionary().Duplicate(true);if(data.ContainsKey("architecture_source"))data["world_architecture_source_key"]=sessions.source_key(authored);data["world_region"]=regionId;document.Get("components").AsGodotArray().Add(part);
                }
                if(source.Get("terrain_field").As<RefCounted>()!=null)
                {var frontage=new Settings();var frontageRoads=source.Get("roads").AsGodotArray().Duplicate();frontageRoads.AddRange(generated["roads"].AsGodotArray());foreach(var roadValue in frontageRoads){var road=roadValue.AsGodotDictionary();if(road["id"].AsString()==plot["frontage"].AsString()){frontage=road;break;}}var steps=entry(authored,plot,frontage,owner);if(steps!=null)document.Get("components").AsGodotArray().Add(steps);}
                count++;
            }
        }
        return new Settings {["errors"]=errors.ToArray(),["warnings"]=warnings.ToArray(),["settings"]=settings};
    }
}
