using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class TerrainGenerationOperations : RefCounted
{
    private readonly EnvironmentDataHash _hash=new();
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private static double D(Resource owner,string key)=>owner.Get(key).AsDouble();
    private static double Number(Settings values,string key,double fallback)=>Get(values,key,fallback).AsDouble();
    private static double Smooth(double from,double to,double value)=>Mathf.SmoothStep(from,to,value);
    public string[] validate(Resource owner)
    {
        var errors=new List<string>();
        foreach(string field in new[]{"lacunarity","gain","medium_weight","fine_weight","warp_strength","sharpness","direction","island_radius","transition"})
            if(!double.IsFinite(D(owner,field))) {errors.Add("Terrain generator values must be finite.");break;}
        foreach(var entry in owner.Get("layers").AsGodotArray())
        {
            var layer=entry.AsGodotDictionary();
            if(Get(layer,"type", "").AsString()=="Foundation")
            {
                var polygon=Get(layer,"polygon",Array.Empty<Vector2>()).AsVector2Array();var plane=Get(layer,"plane",new Plane(Vector3.Up,0)).AsPlane();double feather=Number(layer,"feather",1);
                if(polygon.Length<3 || Geometry2D.TriangulatePolygon(polygon).Length==0 || !plane.Normal.IsFinite() || !float.IsFinite(plane.D) || Math.Abs(plane.Normal.Y)<.2) errors.Add("Foundation modifiers need a valid footprint and a near-horizontal finite plane.");
                if(!double.IsFinite(feather)||feather<0)errors.Add("Foundation blending distance must be finite and nonnegative.");
            }
            foreach(string field in new[]{"width","length","height","direction","sharpness"})if(!double.IsFinite(Number(layer,field,1))) {errors.Add("Landform values must be finite.");break;}
            if(!Get(layer,"center",Vector2.Zero).AsVector2().IsFinite())errors.Add("Landform positions must be finite.");
        }
        return errors.ToArray();
    }
    public long signature(Resource owner)
    {
        using var values=new GArray();foreach(string field in new[]{"profile","noise_type","octaves","lacunarity","gain","medium_weight","fine_weight","warp_strength","sharpness","direction","island_radius","transition","layers","foundation_edits"})values.Add(owner.Get(field));return _hash.value(values);
    }
    public void prepare(Resource owner,long seed,double frequency)
    {
        long key=unchecked((uint)GD.Hash(new GArray {signature(owner),seed,frequency}));var noises=owner.Get("_noise").AsGodotArray();if(owner.Get("_key").AsInt64()==key && noises.Count==3)return;
        owner.Set("_key",key);noises.Clear();int type=owner.Get("noise_type").AsInt32();
        for(int scale=0;scale<3;scale++)
        {
            var noise=new FastNoiseLite {Seed=unchecked((int)(seed+scale*173)),Frequency=(float)Math.Max(.000001,frequency*Math.Pow(3,scale)),NoiseType=type==1?FastNoiseLite.NoiseTypeEnum.Perlin:type==3?FastNoiseLite.NoiseTypeEnum.Cellular:FastNoiseLite.NoiseTypeEnum.SimplexSmooth,FractalType=FastNoiseLite.FractalTypeEnum.Fbm,FractalOctaves=Math.Clamp(owner.Get("octaves").AsInt32(),1,10),FractalLacunarity=(float)Math.Clamp(D(owner,"lacunarity"),1,5),FractalGain=(float)Math.Clamp(D(owner,"gain"),.01,1)};
            noises.Add(noise);
        }
        owner.Set("_warp",new FastNoiseLite {Seed=unchecked((int)(seed+971)),Frequency=(float)Math.Max(.000001,frequency*.7)});
    }
    public double value(Resource owner,Vector2 point,Vector2 dimensions,double amplitude,double baseHeight)
    {
        var p=point;int type=owner.Get("noise_type").AsInt32(),profile=owner.Get("profile").AsInt32();double warpStrength=D(owner,"warp_strength");
        if(warpStrength>0 || type==4) {var warp=owner.Get("_warp").As<FastNoiseLite>();p+=new Vector2(warp.GetNoise2Dv(point),warp.GetNoise2Dv(point+new Vector2(74,193)))*(float)Math.Max(warpStrength,type==4?1:0);}
        var noise=owner.Get("_noise").AsGodotArray();double macro=noise[0].As<FastNoiseLite>().GetNoise2Dv(p),medium=noise[1].As<FastNoiseLite>().GetNoise2Dv(p)*D(owner,"medium_weight"),fine=noise[2].As<FastNoiseLite>().GetNoise2Dv(p)*D(owner,"fine_weight"),result=macro+medium+fine;
        var rotated=p.Rotated((float)-Mathf.DegToRad(D(owner,"direction")));var unit=point/dimensions*2;
        if(type==2)result=Math.Pow(Math.Max(0,1-Math.Abs(macro)),Math.Max(.1,D(owner,"sharpness")))-.5+medium+fine;
        switch(profile)
        {
            case 0:result=0;break;
            case 2:result=Math.Pow(Math.Max(0,1-Math.Abs(macro)),Math.Max(.1,D(owner,"sharpness")))-.4+medium+fine;break;
            case 3:double radius=D(owner,"island_radius");result=(result+.7)*(1-Smooth(Math.Max(.01,radius-D(owner,"transition")),Math.Max(.02,radius),unit.Length()))-.4;break;
            case 4:result=Math.Pow(Math.Clamp(result+.6,0,1),1.8)*1.8-.5;break;
            case 5:result=Math.Pow((Math.Sin(rotated.X*.7+macro*3)+1)*.5,2.5)*.7+medium*.3+fine*.2;break;
            case 6:result=.5+medium-1.2*Math.Exp(-Math.Pow((rotated.X-Math.Sin(rotated.Y*.12)*dimensions.X*.12)/Math.Max(.1,dimensions.X*.07),2));break;
            case 7:result=Mathf.Lerp(result,Math.Floor(result/.25+.5)*.25,.85);break;
            case 8:result=unit.X*.7+medium+fine;break;
        }
        double elevation=baseHeight+result*amplitude;
        foreach(var entry in owner.Get("layers").AsGodotArray())
        {
            var layer=entry.AsGodotDictionary();if(!Get(layer,"enabled",true).AsBool()||Get(layer,"type", "").AsString()=="Foundation")continue;
            double contribution=landform(point,layer),weight=mask(point,Get(layer,"mask",new Settings()).AsGodotDictionary());
            elevation=Get(layer,"blend","add").AsString() switch {"maximum"=>Mathf.Lerp(elevation,Math.Max(elevation,baseHeight+contribution),weight),"minimum"=>Mathf.Lerp(elevation,Math.Min(elevation,baseHeight+contribution),weight),"replace"=>Mathf.Lerp(elevation,baseHeight+contribution,weight),_=>elevation+contribution*weight};
        }
        return elevation;
    }
    public double mask(Vector2 point,Settings settings)
    {if(settings.Count==0)return 1;double radius=Math.Max(.001,Number(settings,"radius",1)),distance=point.DistanceTo(Get(settings,"center",Vector2.Zero).AsVector2())/radius,weight=1-Smooth(Math.Clamp(1-Number(settings,"falloff",.25),0,.999),1,distance);return Get(settings,"invert",false).AsBool()?1-weight:weight;}
    public double landform(Vector2 point,Settings settings)
    {
        var p=(point-Get(settings,"center",Vector2.Zero).AsVector2()).Rotated((float)-Mathf.DegToRad(Number(settings,"direction",0)));
        double width=Math.Max(.01,Number(settings,"width",5)),length=Math.Max(.01,Number(settings,"length",20)),height=Number(settings,"height",5),sharp=Math.Max(.1,Number(settings,"sharpness",2));
        double radial=new Vector2((float)(p.X/width),(float)(p.Y/length)).Length(),axial=p.X/width,winding=Math.Sin(p.Y/Math.Max(1,length)*Math.Tau)*width*.35;
        switch(Get(settings,"type","Hill").AsString())
        {
            case "Mountain range":double ridge=Math.Pow(Math.Max(0,1-Math.Abs((p.X-winding)/width)),sharp),fork=Math.Pow(Math.Max(0,1-Math.Abs((p.X+p.Y*.4+winding*.5)/(width*.7))),sharp)*.6;return height*Math.Max(ridge,fork)*(1-Smooth(.65,1,Math.Abs(p.Y)/length));
            case "Mountain":return height*Math.Pow(Math.Max(0,1-radial),sharp);
            case "Ridge":return height*Math.Pow(Math.Max(0,1-Math.Abs(axial)),sharp)*(1-Smooth(.7,1,Math.Abs(p.Y)/length));
            case "Valley":return -height*Math.Exp(-Math.Pow((p.X-winding)/width,2))*(1-Smooth(.7,1,Math.Abs(p.Y)/length));
            case "Canyon":return -height*(1-Smooth(.55,1,Math.Abs((p.X-winding)/width)))*(1-Smooth(.7,1,Math.Abs(p.Y)/length));
            case "Cliff":return height*Smooth(-.05,.05,axial)*(1-Smooth(.7,1,radial));
            case "Plateau":case "Mesa":return height*(1-Smooth(.65,1,radial));
            case "Basin":return -height*Math.Pow(Math.Max(0,1-radial*radial),2);
            case "Crater":return height*(Math.Exp(-Math.Pow((radial-.7)*8,2))*.6-Math.Exp(-Math.Pow(radial*2,2)));
            case "Dunes":return height*Math.Pow((Math.Sin(axial*Math.Tau)+1)*.5,sharp)*(1-Smooth(.7,1,Math.Abs(p.Y)/length));
            default:return height*Math.Exp(-radial*radial*3);
        }
    }
    public Resource preset(int index)
    {
        var result=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/terrain/terrain_generator.gd").New().As<Resource>();result.Set("profile",Math.Clamp(index,0,9));
        if(index is 2 or 3 or 4)result.Set("warp_strength",2.0);if(index==2){result.Set("noise_type",2);result.Set("sharpness",2.5);}if(index==5){result.Set("direction",30.0);result.Set("fine_weight",.02);}return result;
    }
}
