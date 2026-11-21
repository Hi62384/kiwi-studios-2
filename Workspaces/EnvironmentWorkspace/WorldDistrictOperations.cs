using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class WorldDistrictOperations : RefCounted
{
    private static readonly string[] Categories={"Residential","Commercial","Industrial","Downtown","Suburban","Mixed Use","Civic","Park/Green Space","Agricultural","Custom"};
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    public Settings create(string category,Vector2[] polygon,Settings presets)
    {
        int minimum=1,maximum=2;double lot=18,density=1,setback=2;string style="Modern";
        switch(category){case "Commercial":minimum=2;maximum=4;lot=24;break;case "Industrial":maximum=1;lot=30;style="Industrial";setback=3;break;case "Downtown":minimum=3;maximum=8;lot=16;setback=1;break;case "Suburban":lot=22;density=.7;style="Traditional";setback=3;break;case "Mixed Use":minimum=2;maximum=5;break;case "Civic":minimum=2;maximum=3;lot=28;style="Classical-Inspired";setback=4;break;case "Park/Green Space":density=0;break;case "Agricultural":maximum=1;lot=32;density=.35;style="Cabin";setback=4;break;}
        var template=new BuildingStyleOperations().apply(new BuildingSourceOperations().rectangular(6,8,1,true),style,presets);
        return new Settings {["id"]=Guid.NewGuid().ToString("N"),["name"]=category,["category"]=category,["polygon"]=(Vector2[])polygon.Clone(),["enabled"]=true,["density"]=density,["height_min"]=minimum,["height_max"]=maximum,["lot_size"]=lot,["setback"]=setback,["seed"]=1,["template"]=template!=null?Variant.From(template):default};
    }
    public string[] validate_rules(Settings settings)
    {
        var errors=new List<string>();foreach(var spec in new[]{("density",0.0,1.0),("lot_size",10.0,64.0),("setback",0.0,10.0),("height_min",1.0,8.0),("height_max",1.0,8.0)})if(settings.TryGetValue(spec.Item1,out var value)){double number=value.AsDouble();if(!double.IsFinite(number)||number<spec.Item2||number>spec.Item3)errors.Add("District or block "+spec.Item1+" is outside its supported range.");}
        if(Get(settings,"height_min",1).AsInt64()>Get(settings,"height_max",8).AsInt64())errors.Add("Minimum building height cannot exceed maximum height.");return errors.ToArray();
    }
    public string[] validate(Settings settlement)
    {
        var errors=new List<string>();var seen=new HashSet<string>();var districts=Get(settlement,"districts",new GArray()).AsGodotArray();if(districts.Count>32)errors.Add("A settlement supports at most 32 editable districts.");
        foreach(var value in districts){var district=value.AsGodotDictionary();string id=Get(district,"id","").AsString();var polygon=Get(district,"polygon",Array.Empty<Vector2>()).AsVector2Array();if(id.Length==0||!seen.Add(id))errors.Add("District IDs must be unique within their settlement.");if(!Categories.Contains(Get(district,"category","").AsString()))errors.Add("Choose a supported district category.");if(polygon.Any(point=>!point.IsFinite())||polygon.Length<3||polygon.Length>512||Math.Abs(area(polygon))<.01||Geometry2D.TriangulatePolygon(polygon).Length==0||!simple(polygon))errors.Add("District boundaries need a simple polygon with 3 to 512 finite points.");errors.AddRange(validate_rules(district));}
        var overrides=Get(settlement,"block_overrides",new Settings()).AsGodotDictionary();if(overrides.Count>4096)errors.Add("This settlement exceeds its editable block-override budget.");foreach(var value in overrides.Values){var settings=value.AsGodotDictionary();errors.AddRange(validate_rules(settings));if(settings.ContainsKey("district_id")&&!seen.Contains(settings["district_id"].AsString()))errors.Add("Block overrides must reference an existing district.");}return errors.ToArray();
    }
    public Settings rules(Settings block,Settings settlement)
    {
        var result=new Settings();var polygon=block["polygon"].AsVector2Array();double size=Math.Abs(area(polygon));var districts=Get(settlement,"districts",new GArray()).AsGodotArray();
        foreach(var value in districts){var district=value.AsGodotDictionary();if(!Get(district,"enabled",true).AsBool())continue;double covered=0;foreach(var intersection in Geometry2D.IntersectPolygons(polygon,district["polygon"].AsVector2Array()))covered+=Math.Abs(area(intersection));if(covered<size*.5)continue;result=district.Duplicate();result.Remove("polygon");result["district_id"]=district["id"];}
        var overrides=Get(settlement,"block_overrides",new Settings()).AsGodotDictionary();var replacement=Get(overrides,block["id"].AsString(),new Settings()).AsGodotDictionary();if(replacement.ContainsKey("district_id"))foreach(var value in districts){var district=value.AsGodotDictionary();if(district["id"].AsString()!=replacement["district_id"].AsString()||!Get(district,"enabled",true).AsBool())continue;result=district.Duplicate();result.Remove("polygon");result["district_id"]=district["id"];break;}
        result.Merge(replacement,true);if(result.Count==0)return result;if(Get(result,"category","").AsString()=="Park/Green Space")result["density"]=0.0;block["district"]=Get(result,"category",Get(block,"district","Residential"));block["district_id"]=Get(result,"district_id","");return result;
    }
    public Settings effective(Settings settlement,Settings settings)
    {var result=settlement.Duplicate();result.Remove("districts");result.Remove("block_overrides");result.Merge(settings,true);result["id"]=settlement["id"];return result;}
    public bool accept(Settings plot,Settings settings)
    {if(settings.Count==0)return true;long hash=unchecked((uint)GD.Hash(new GArray {plot["id"],Get(settings,"seed",1).AsInt64()}));return (double)(hash&0x7fffffff)/2147483647<Get(settings,"density",1.0).AsDouble();}
    public double area(Vector2[] polygon)
    {double result=0;for(int i=0;i<polygon.Length;i++)result+=polygon[i].Cross(polygon[(i+1)%polygon.Length]);return result*.5;}
    public bool simple(Vector2[] polygon)
    {for(int i=0;i<polygon.Length;i++){if(polygon[i].DistanceSquaredTo(polygon[(i+1)%polygon.Length])<.000001)return false;for(int j=i+2;j<polygon.Length;j++){if((j+1)%polygon.Length==i)continue;if(Geometry2D.SegmentIntersectsSegment(polygon[i],polygon[(i+1)%polygon.Length],polygon[j],polygon[(j+1)%polygon.Length]).VariantType!=Variant.Type.Nil)return false;}}return true;}
}
