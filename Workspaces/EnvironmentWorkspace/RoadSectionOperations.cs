using Godot;
using System;
using System.Linq;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;
using Topology=ModelGeometryOperations.Topology;

public partial class RoadSectionOperations : RefCounted
{
    private readonly RoadGeometryOperations _geometry=new();
    private readonly ModelModifiers _modifiers=new();
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private static double F(Settings values,string key,double fallback=0)=>Get(values,key,fallback).AsDouble();
    public Settings defaults(string type)
    {
        var source=new Settings {["type"]=type,["section"]=true,["width"]=6.0,["thickness"]=.12,["shoulder"]=.3,["sidewalk"]=1.5,["curb_height"]=.15,["curb_width"]=.14,["lanes"]=2,["markings"]=true,["speed_limit"]=30.0,["one_way"]=false,["surface"]="asphalt"};
        source.Merge(type switch {
            "Highway"=>new Settings {["width"]=20.0,["shoulder"]=2.5,["sidewalk"]=0.0,["curb_height"]=0.0,["lanes"]=6,["speed_limit"]=100.0},
            "Major Road"=>new Settings {["width"]=12.0,["shoulder"]=.5,["lanes"]=4,["speed_limit"]=60.0},
            "Secondary Road"=>new Settings {["width"]=8.0,["lanes"]=2,["speed_limit"]=50.0},
            "Rural Road"=>new Settings {["width"]=5.0,["shoulder"]=.75,["sidewalk"]=0.0,["curb_height"]=0.0,["speed_limit"]=60.0},
            "Dirt Road"=>new Settings {["width"]=4.0,["shoulder"]=.4,["sidewalk"]=0.0,["curb_height"]=0.0,["thickness"]=.04,["markings"]=false,["surface"]="dirt",["speed_limit"]=25.0},
            "Forest Track"=>new Settings {["width"]=2.5,["shoulder"]=.2,["sidewalk"]=0.0,["curb_height"]=0.0,["thickness"]=.02,["markings"]=false,["surface"]="gravel",["speed_limit"]=15.0},
            "Pedestrian Path"=>new Settings {["width"]=2.0,["shoulder"]=.1,["sidewalk"]=0.0,["curb_height"]=0.0,["thickness"]=.06,["markings"]=false,["surface"]="path",["lanes"]=1,["speed_limit"]=0.0},
            "Mountain Road"=>new Settings {["width"]=5.0,["shoulder"]=.5,["sidewalk"]=0.0,["curb_height"]=0.0,["speed_limit"]=35.0},_=>new Settings()},true);return source;
    }
    public void prepare(Resource source)
    {var materials=source.Get("road_materials").AsGodotDictionary();foreach(var entry in new[]{("gravel","77756c"),("dirt","786147"),("path","aaa594"),("concrete","a7aaa4"),("paint","eae5c7")})if(!materials.ContainsKey(entry.Item1))materials[entry.Item1]=new StandardMaterial3D {AlbedoColor=new Color(entry.Item2),Roughness=.95f};}
    public double outer_half(Settings road)=>F(road,"width")*.5+(Get(road,"section",false).AsBool()?F(road,"shoulder")+F(road,"sidewalk")+(F(road,"curb_height")>0?F(road,"curb_width",.14):0):0);
    public Material? material(Resource source,Settings road,string part)
    {
        var fallback=source.Get("road_material").As<Material>();var materials=source.Get("road_materials").AsGodotDictionary();Material? Find(string key)=>materials.TryGetValue(key,out var found)?found.As<Material>():fallback;
        if(part=="surface"){var value=Get(road,"material");if(value.VariantType==Variant.Type.Object&&value.AsGodotObject() is Material custom)return custom;return Get(road,"surface","asphalt").AsString()=="asphalt"?fallback:Find(road["surface"].AsString());}if(part=="markings")return Find("paint");if(part=="shoulders")return source.Get("shoulder_material").As<Material>()??Find("gravel");return Find("concrete");
    }
    public string[] validate(Settings road)
    {var errors=new List<string>();if(!Get(road,"section",false).AsBool())return errors.ToArray();foreach(var spec in new[]{("thickness",0.0,2.0),("shoulder",0.0,8.0),("sidewalk",0.0,8.0),("curb_height",0.0,.5),("curb_width",.05,1.0),("speed_limit",0.0,200.0)}){double value=F(road,spec.Item1);if(!double.IsFinite(value)||value<spec.Item2||value>spec.Item3)errors.Add("Road "+spec.Item1+" is outside its supported range.");}int lanes=Get(road,"lanes",2).AsInt32();if(lanes<1||lanes>12)errors.Add("Roads support one to twelve lanes.");return errors.ToArray();}
    private Topology Solid(Topology mesh,double depth)
    {using var input=mesh.Build();using var output=_modifiers.apply(input,new Settings {["type"]="Solidify",["amount"]=depth});return new Topology(new ModelMeshOperations.Snapshot(output));}
    public Resource solid(Resource mesh,double depth)
    {return _modifiers.apply(mesh,new Settings {["type"]="Solidify",["amount"]=depth});}
    private Topology Band(Vector3[] points,double width,double offset,double height,double depth,Settings sections)
    {var mesh=_geometry.Strip(points,width,offset,sections);for(int index=0;index<mesh.Points.Count;index++)mesh.Points[index]+=Vector3.Up*(float)height;return Solid(mesh,depth);}
    public Resource band(Vector3[] points,double width,double offset,double height,double depth,Settings sections)=>Band(points,width,offset,height,depth,sections).Build();
    private static void Append(Dictionary<string,Topology> parts,string key,Topology mesh)
    {if(!parts.TryGetValue(key,out var combined)){combined=new Topology();parts[key]=combined;}combined.Append(mesh,Transform3D.Identity);}
    private static Settings BuildParts(Dictionary<string,Topology> parts,bool errors)
    {var result=new Settings();foreach(var pair in parts)result[pair.Key]=pair.Value.Build();if(errors)result["errors"]=Array.Empty<string>();return result;}
    public Settings build(Vector3[] points,Settings road,Settings cancellation)
    {bool enabled=Get(cancellation,"enabled",false).AsBool();return Build(points,road,()=>enabled&&GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/world/road_section.gd").Call("_cancel_requested",cancellation).AsBool());}
    internal Settings Build(Vector3[] points,Settings road,Func<bool> cancelled)
    {
        points=StableSectionSamples(points);double width=F(road,"width");var sections=Get(road,"_cross_sections",new Settings()).AsGodotDictionary();var parts=new Dictionary<string,Topology>(StringComparer.Ordinal) {["surface"]=_geometry.Strip(points,width,0,sections)};if(!Get(road,"section",false).AsBool())return BuildParts(parts,true);double thickness=F(road,"thickness",.12);if(thickness>0)parts["surface"]=Solid(parts["surface"],thickness);double shoulder=F(road,"shoulder"),walk=F(road,"sidewalk"),curb=F(road,"curb_height"),curbWidth=curb>0?F(road,"curb_width",.14):0;
        foreach(double side in new[]{-1.0,1.0}){if(shoulder>0)Append(parts,"shoulders",Band(points,shoulder,side*(width+shoulder)*.5,0,Math.Max(.04,thickness),sections));if(curb>0)Append(parts,"curbs",Band(points,curbWidth,side*(width*.5+shoulder+curbWidth*.5),curb,curb+Math.Max(.04,thickness),sections));if(walk>0)Append(parts,"sidewalks",Band(points,walk,side*(width*.5+shoulder+curbWidth+walk*.5),curb,Math.Max(.06,thickness),sections));}
        if(Get(road,"markings",false).AsBool())
        {
            int lanes=Math.Clamp(Get(road,"lanes",2).AsInt32(),1,12);var paint=new Topology();var cumulative=new float[points.Length];for(int index=0;index<points.Length-1;index++)cumulative[index+1]=cumulative[index]+points[index].DistanceTo(points[index+1]);double length=cumulative.Length>0?cumulative[^1]:0,phase=Mathf.PosMod(F(road,"distance_start"),6);int marks=0;
            for(int lane=1;lane<lanes;lane++)for(double start=-phase;start<length;start+=6){if(cancelled())return new Settings {["cancelled"]=true};var path=slice(points,cumulative,Math.Max(0,start),Math.Min(length,start+3));if(path.Length>1){var strip=_geometry.Strip(path,Math.Min(.12,width/lanes*.2),-width*.5+width*lane/lanes,new Settings());for(int index=0;index<strip.Points.Count;index++)strip.Points[index]+=Vector3.Up*.008f;paint.Append(strip,Transform3D.Identity);marks++;}if(marks>32768)return new Settings {["errors"]=new[]{"Lane-marking budget exceeded. Split this road into smaller generated regions."}};}if(paint.Faces.Count>0)parts["markings"]=paint;
        }
        return BuildParts(parts,true);
    }
    public Vector3[] slice(Vector3[] points,float[] cumulative,double start,double end)
    {var result=new List<Vector3>();if(end-start<.01)return result.ToArray();for(int index=0;index<points.Length-1;index++){double a=cumulative[index],b=cumulative[index+1];if(b<=start||a>=end||b-a<.00001)continue;var first=points[index].Lerp(points[index+1],(float)Math.Clamp((start-a)/(b-a),0,1));var last=points[index].Lerp(points[index+1],(float)Math.Clamp((end-a)/(b-a),0,1));if(result.Count==0||!result[^1].IsEqualApprox(first))result.Add(first);if(!result[^1].IsEqualApprox(last))result.Add(last);}return result.ToArray();}
    public void append(Settings result,string key,Resource mesh)
    {var data=new Topology(new ModelMeshOperations.Snapshot(mesh));if(result.TryGetValue(key,out var existing)){var combined=new Topology(new ModelMeshOperations.Snapshot(existing.As<Resource>()));combined.Append(data,Transform3D.Identity);var resource=existing.As<Resource>();resource.Set("vertices",combined.Points.ToArray());resource.Set("faces",new Godot.Collections.Array<int[]>(combined.Faces));resource.Set("uv",new Godot.Collections.Array<Vector2[]>(combined.Uv));resource.Set("materials",combined.Materials.ToArray());}else result[key]=data.Build();}
}
