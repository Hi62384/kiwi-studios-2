using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class BuildingSourceOperations : RefCounted
{
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    public Resource copy(Resource authored)
    {
        var result=authored.GetScript().As<Script>().Call("new").As<Resource>();foreach(string key in new[]{"source_id","title","seed","footprint","floors","wall_thickness","slab_thickness","roof_type","roof_pitch","roof_overhang","materials","stairs","physics_enabled","foundation_depth","style","facade_detail","detail_width","baseboard_height","crown_height","interior_trim_depth"})
        {var value=authored.Get(key);result.Set(key,value.VariantType==Variant.Type.Array?Variant.From(value.AsGodotArray().Duplicate(true)):value.VariantType==Variant.Type.Dictionary?Variant.From(value.AsGodotDictionary().Duplicate(true)):value);}return result;
    }
    public Resource rectangular(double width,double depth,int levels,bool withMaterials)
    {
        var source=new BuildingSource();var footprint=new[]{new Vector2((float)(-width/2),(float)(-depth/2)),new Vector2((float)(width/2),(float)(-depth/2)),new Vector2((float)(width/2),(float)(depth/2)),new Vector2((float)(-width/2),(float)(depth/2))};source.Set("footprint",footprint);var floors=source.Get("floors").AsGodotArray();
        for(int level=0;level<Math.Clamp(levels,1,8);level++)
        {
            var walls=new GArray();for(int edge=0;edge<4;edge++){var openings=new GArray();if(level==0&&edge==0)openings.Add(new Settings {["id"]="door"+edge,["type"]="door",["t"]=.5,["width"]=1.0,["height"]=2.1,["bottom"]=0.0,["angle"]=0.0});else openings.Add(new Settings {["id"]="window"+edge,["type"]="window",["t"]=.5,["width"]=1.4,["height"]=1.2,["bottom"]=1.0});walls.Add(new Settings {["id"]="wall"+edge,["a"]=footprint[edge],["b"]=footprint[(edge+1)%4],["height"]=3.0,["height_mode"]="level",["openings"]=openings});}
            floors.Add(new Settings {["id"]="floor"+level,["name"]="Level "+(level+1),["elevation"]=level*3.0,["height"]=3.0,["walls"]=walls,["rooms"]=new GArray {new Settings {["id"]="room0",["name"]="Room",["polygon"]=footprint}},["cuts"]=new GArray()});
        }
        if(!withMaterials)return source;var engine=GD.Load<GDScript>("res://scripts/materials/natural_material_engine.gd");var materials=source.Get("materials").AsGodotArray();foreach(string preset in new[]{"stone/brick","wood/wood_planks","stone/slate","wood/oak"})materials.Add(engine.Call("create_spatial_material",engine.Call("defaults",preset)));
        materials.Add(new StandardMaterial3D {AlbedoColor=new Color(.65f,.85f,.9f,.28f),Transparency=BaseMaterial3D.TransparencyEnum.Alpha,Roughness=.12f,CullMode=BaseMaterial3D.CullModeEnum.Disabled});materials.Add(materials[0]);materials.Add(materials[1]);return source;
    }
    public double wall_height(Resource source,Settings floor,Settings wall)
    {
        if(Get(wall,"height_mode","level").AsString()!="level")return Get(wall,"height",Get(floor,"height",3.0)).AsDouble();double height=Get(floor,"height",3.0).AsDouble();
        foreach(var entry in source.Get("floors").AsGodotArray())if(Mathf.IsEqualApprox(Get(entry.AsGodotDictionary(),"elevation",0.0).AsDouble(),Get(floor,"elevation",0.0).AsDouble()+height))return Math.Max(.1,height-source.Get("slab_thickness").AsDouble());return height;
    }
    public string[] validate(Resource source)
    {
        var errors=new List<string>();var ids=new HashSet<string>(StringComparer.Ordinal);double D(string key)=>source.Get(key).AsDouble();
        foreach(string field in new[]{"wall_thickness","slab_thickness","roof_pitch","roof_overhang","foundation_depth","detail_width","baseboard_height","crown_height","interior_trim_depth"})if(!double.IsFinite(D(field))){errors.Add("Building dimensions must be finite.");break;}
        int roof=source.Get("roof_type").AsInt32(),facade=source.Get("facade_detail").AsInt32();if(roof<0||roof>3||facade<0||facade>7)errors.Add("Choose a supported roof and facade type.");if(D("foundation_depth")<0||D("roof_overhang")<0||D("roof_pitch")<0||D("roof_pitch")>=85||D("detail_width")<=0)errors.Add("Foundation, roof and detail dimensions are outside their supported ranges.");if(D("baseboard_height")<0||D("baseboard_height")>.5||D("crown_height")<0||D("crown_height")>.5||D("interior_trim_depth")<.005||D("interior_trim_depth")>.3)errors.Add("Interior trim must fit the supported wall profile.");
        var footprint=source.Get("footprint").AsVector2Array();var floors=source.Get("floors").AsGodotArray();if(footprint.Length>256)errors.Add("A footprint supports up to 256 authored corners.");if(footprint.Length<3||Geometry2D.TriangulatePolygon(footprint).Length==0)errors.Add("The footprint must be a simple closed polygon.");if(floors.Count==0||floors.Count>8)errors.Add("A building supports one to eight levels.");if(source.Get("stairs").AsGodotArray().Count>16)errors.Add("A building supports up to sixteen staircases.");if(D("wall_thickness")<.02||D("slab_thickness")<.02)errors.Add("Wall and slab thickness must be at least 0.02 m.");
        foreach(var entry in floors)
        {
            var floor=entry.AsGodotDictionary();var polygon=Get(floor,"footprint",footprint).AsVector2Array();double elevation=Get(floor,"elevation",0.0).AsDouble(),floorHeight=Get(floor,"height",3.0).AsDouble();if(!double.IsFinite(elevation)||!double.IsFinite(floorHeight)||floorHeight<.5)errors.Add("Levels require finite elevations and a height of at least 0.5 m.");foreach(var point in polygon)if(!point.IsFinite()){errors.Add("Footprint corners must be finite.");break;}if(polygon.Length>256)errors.Add("A level footprint supports up to 256 authored corners.");if(polygon.Length<3||Geometry2D.TriangulatePolygon(polygon).Length==0)errors.Add("A level footprint must be a simple closed polygon.");
            var rooms=Get(floor,"rooms",new GArray()).AsGodotArray();if(rooms.Count>64||Get(floor,"cuts",new GArray()).AsGodotArray().Count>32)errors.Add("A level supports up to 64 rooms and 32 floor cuts.");string id=Get(floor,"id", "").AsString();if(id.Length==0||!ids.Add(id))errors.Add("Levels need unique stable identities.");var walls=Get(floor,"walls",new GArray()).AsGodotArray();var wallIds=new HashSet<string>(StringComparer.Ordinal);var openingIds=new HashSet<string>(StringComparer.Ordinal);var roomIds=new HashSet<string>(StringComparer.Ordinal);
            foreach(var roomEntry in rooms){var room=roomEntry.AsGodotDictionary();string identity=Get(room,"id", "").AsString();var region=Get(room,"polygon",Array.Empty<Vector2>()).AsVector2Array();if(identity.Length==0||!roomIds.Add(identity))errors.Add("Rooms need unique stable identities within a level.");if(region.Length<3||Geometry2D.TriangulatePolygon(region).Length==0)errors.Add("Room regions must be closed simple polygons.");}
            if(walls.Count>128)errors.Add("A level supports up to 128 authored wall segments.");foreach(var wallEntry in walls)
            {
                var wall=wallEntry.AsGodotDictionary();var openings=Get(wall,"openings",new GArray()).AsGodotArray();if(openings.Count>32)errors.Add("A wall supports up to 32 openings.");string key=Get(wall,"id", "").AsString();var a=Get(wall,"a",Vector2.Zero).AsVector2();var b=Get(wall,"b",Vector2.Zero).AsVector2();double length=a.DistanceTo(b),height=wall_height(source,floor,wall);if(key.Length==0||!wallIds.Add(key))errors.Add("Wall identities must be unique within a level.");if(length<.1||height<.1||!a.IsFinite()||!b.IsFinite())errors.Add("Wall segments need finite endpoints and positive dimensions.");
                foreach(var openingEntry in openings){var opening=openingEntry.AsGodotDictionary();string identity=Get(opening,"id", "").AsString();if(identity.Length==0||!openingIds.Add(identity))errors.Add("Openings need unique stable identities within a level.");double width=Get(opening,"width",1.0).AsDouble(),center=Get(opening,"t",.5).AsDouble()*length,bottom=Get(opening,"bottom",0.0).AsDouble(),top=bottom+Get(opening,"height",2.0).AsDouble();if(width<.05||center-width/2<-.0001||center+width/2>length+.0001||bottom<0||top>height+.0001)errors.Add("An opening no longer fits its wall. Resize or move it before rebuilding.");}
            }
        }
        return errors.ToArray();
    }
}
