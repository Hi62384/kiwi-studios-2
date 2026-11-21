using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class EnvironmentScatterOperations : RefCounted
{
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private static long Hash(Variant value)=>unchecked((uint)GD.Hash(value));
    private static bool ScriptType(Resource value,string path){var script=value.GetScript().As<Script>();while(script!=null){if(script.ResourcePath==path||script.ResourcePath==LegacyResourceLoader.NativeScriptPath(path))return true;script=script.GetBaseScript();}return false;}
    public long signature(Resource owner)
    {using var values=new GArray();foreach(string key in new[]{"terrain_id","palette","region","density","minimum_distance","seed","scale_range","yaw_range","align_normal","height_range","slope_range","budget","paint_regions","erase_regions","exclude_polygons","include_polygons","exclusion_margin","patch_scale","patch_strength","use_anchors","anchor_points","anchor_ids","anchor_height_mode","collisions","biome_ids","minimum_biome_weight","cluster_count","cluster_radius","temperature_range","humidity_range","shore_range","water_depth_range","overrides","surface_domain"})values.Add(owner.Get(key));return Hash(values);}
    public long render_signature(Resource owner)=>Hash(new GArray {owner.Get("render_cluster_size"),owner.Get("render_distance"),owner.Get("lod_enabled"),owner.Get("lod_bias"),owner.Get("stream_instances")});
    public int unique_anchor_count(Resource owner)=>owner.Get("anchor_ids").AsStringArray().Distinct(StringComparer.Ordinal).Count();
    public string[] validate(Resource owner)
    {
        double D(string key)=>owner.Get(key).AsDouble();var errors=new List<string>();int heightMode=owner.Get("anchor_height_mode").AsInt32();if(heightMode is <0 or >2)errors.Add("Choose terrain, offset or authored anchor height.");
        if(!double.IsFinite(D("render_cluster_size"))||D("render_cluster_size")<0||D("render_cluster_size")>4096||!double.IsFinite(D("render_distance"))||D("render_distance")<0||!double.IsFinite(D("lod_bias"))||D("lod_bias")<.05||D("lod_bias")>16)errors.Add("Scatter rendering needs a valid cluster size, distance and detail bias.");
        if(D("density")<0||!double.IsFinite(D("density")))errors.Add("Scatter density must be a finite positive value.");var palette=owner.Get("palette").AsGodotArray();if(palette.Count==0)errors.Add("Choose at least one scatter asset.");
        var anchors=owner.Get("anchor_points").AsGodotArray();var ids=owner.Get("anchor_ids").AsStringArray();if(anchors.Count>20000||(ids.Length>0&&ids.Length!=anchors.Count))errors.Add("Anchor placement needs matching IDs and no more than 20,000 points.");if(ids.Length>0&&unique_anchor_count(owner)!=ids.Length)errors.Add("Placement anchor IDs must be unique.");
        foreach(var value in anchors){var pose=value.AsTransform3D();if(!pose.Origin.IsFinite()||!pose.Basis.X.IsFinite()||!pose.Basis.Y.IsFinite()||!pose.Basis.Z.IsFinite())errors.Add("Placement anchors must be finite transforms.");}
        var excluded=owner.Get("exclude_polygons").AsGodotArray();var included=owner.Get("include_polygons").AsGodotArray();if(excluded.Count+included.Count>16384)errors.Add("Scatter masks exceed the editable polygon budget.");
        if(!double.IsFinite(D("exclusion_margin"))||D("exclusion_margin")<0||!double.IsFinite(D("patch_scale"))||D("patch_scale")<0||!double.IsFinite(D("patch_strength"))||D("patch_strength")<0||D("patch_strength")>1)errors.Add("Scatter clearing and margin settings must be finite and within their ranges.");
        foreach(var value in excluded.Concat(included)){var polygon=value.AsVector2Array();if(polygon.Length<3||polygon.Length>1024)errors.Add("Scatter masks need 3 to 1024 vertices.");foreach(var point in polygon)if(!point.IsFinite())errors.Add("Scatter mask points must be finite.");}
        foreach(var value in palette)
        {
            var source=Get(value.AsGodotDictionary(),"source", "");bool path=source.VariantType is Variant.Type.String or Variant.Type.StringName&&source.AsString().Length>0;var resource=source.VariantType==Variant.Type.Object?source.AsGodotObject() as Resource:null;
            if(resource!=null&&ScriptType(resource,"res://Workspaces/EnvironmentWorkspace/environment_document.gd")||!(resource!=null&&ScriptType(resource,"res://Workspaces/ModelWorkspace/model_document.gd")||path))errors.Add("Scatter palette contains an empty or unsupported source.");
        }
        return errors.ToArray();
    }
    public Settings mask_index(Resource owner)
    {
        var cells=new Settings();var large=new GArray();double margin=owner.Get("exclusion_margin").AsDouble();
        foreach(var value in owner.Get("exclude_polygons").AsGodotArray())
        {
            var polygon=value.AsVector2Array();if(polygon.Length<3)continue;var bounds=new Rect2(polygon[0],Vector2.Zero);foreach(var point in polygon)bounds=bounds.Expand(point);bounds=bounds.Grow((float)(margin+.001));var low=(Vector2I)(bounds.Position/16).Floor();var high=(Vector2I)(bounds.End/16).Floor();
            if((high.X-low.X+1)*(high.Y-low.Y+1)>256){large.Add(polygon);continue;}for(int y=low.Y;y<=high.Y;y++)for(int x=low.X;x<=high.X;x++){var cell=new Vector2I(x,y);if(!cells.TryGetValue(cell,out var list)){list=new GArray();cells[cell]=list;}list.AsGodotArray().Add(polygon);}
        }
        return new Settings {["cells"]=cells,["large"]=large};
    }
    public bool excluded(Resource owner,Vector2 point,Settings index)
    {
        var cells=index["cells"].AsGodotDictionary();var candidates=cells.TryGetValue((Vector2I)(point/16).Floor(),out var local)?local.AsGodotArray():new GArray();double margin=owner.Get("exclusion_margin").AsDouble();
        foreach(var value in candidates.Concat(index["large"].AsGodotArray())){var polygon=value.AsVector2Array();if(Geometry2D.IsPointInPolygon(point,polygon))return true;for(int edge=0;edge<polygon.Length;edge++)if(point.DistanceTo(Geometry2D.GetClosestPointToSegment(point,polygon[edge],polygon[(edge+1)%polygon.Length]))<=margin)return true;}return false;
    }
}
