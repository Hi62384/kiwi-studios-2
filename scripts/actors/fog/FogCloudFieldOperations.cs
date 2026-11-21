using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;
public partial class FogCloudFieldOperations:RefCounted
{
    private readonly ActorPropertyOperations _properties=new();private readonly ActorDefinitionOperations _definitions=new();
    private static double N(Settings v,string key,double fallback=0)=>v.GetValueOrDefault(key,fallback).AsDouble();
    private static double Smooth(double a,double b,double value){double t=Math.Clamp((value-a)/(b-a),0,1);return t*t*(3-2*t);}
    public void extend_definition(Resource d)
    {
        _definitions.find_property(d,new StringName("mode"))!.Get("options").AsGodotDictionary()["choices"].AsGodotArray().Add("Cloud / atmospheric structure");var rows=GD.Load<GDScript>("res://scripts/actors/fog/fog_cloud_field.gd").GetScriptConstantMap()["FIELD_ROWS"].AsGodotArray();foreach(var item in rows){var row=item.AsGodotArray();var p=_properties.create(new StringName(row[0].AsString()),row[1].AsString(),row[2],true);var options=p.Get("options").AsGodotDictionary();options.Merge(row[3].AsGodotDictionary());options["group"]="Cloud shape";options["visible_when"]=new Settings{["property"]="mode",["values"]=new GArray{8}};d.Get("properties").AsGodotArray().Add(p);}foreach(string key in new[]{"seed","contrast","threshold"})_definitions.find_property(d,new StringName(key))!.Get("options").AsGodotDictionary()["visible_when"]=new Settings{["property"]="mode",["values"]=key=="seed"?new GArray{4,8}:new GArray{4,5,7,8}};
    }
    public Settings prepare(Settings v)
    {
        var macro=new FastNoiseLite{Seed=(int)N(v,"seed",1),NoiseType=FastNoiseLite.NoiseTypeEnum.SimplexSmooth,Frequency=(float)(2.4/Math.Max(.05,N(v,"cloud_size",1))),FractalType=FastNoiseLite.FractalTypeEnum.Fbm,FractalOctaves=3};var detail=new FastNoiseLite{Seed=macro.Seed+7919,Frequency=macro.Frequency*3.2f,FractalType=FastNoiseLite.FractalTypeEnum.Fbm,FractalOctaves=2};var fine=new FastNoiseLite{Seed=macro.Seed+104729,Frequency=macro.Frequency*9};var rng=new RandomNumberGenerator{Seed=unchecked((ulong)(long)macro.Seed)};var lobes=new Godot.Collections.Array<Vector4>();for(int i=0;i<10;i++)lobes.Add(new Vector4(.5f+rng.RandfRange(-.23f,.23f),rng.RandfRange(.24f,.68f),.5f+rng.RandfRange(-.23f,.23f),rng.RandfRange(.16f,.27f)));return new Settings{["macro"]=macro,["detail"]=detail,["fine"]=fine,["lobes"]=lobes};
    }
    public double sample_density(Settings v,Settings noise,Vector3 p,Vector3 world)
    {
        int kind=(int)N(v,"cloud_type");double baseHeight=N(v,"cloud_base",.1),thickness=Math.Max(.01,N(v,"cloud_thickness",.8)),height=(p.Y-baseHeight)/thickness;if(height<0||height>1)return 0;var q=p;double softness=Math.Max(.005,N(v,"cloud_softness",.12)),coverage=Math.Clamp(N(v,"cloud_coverage",.55),0,1);if(coverage<=0)return 0;if(kind==2)q/=v.GetValueOrDefault("cloud_stretch",new Vector3(5,1,1)).AsVector3().Abs().Max(Vector3.One*.05f);var macroNoise=noise["macro"].As<FastNoiseLite>();double macro=macroNoise.GetNoise3Dv(q)*.5+.5,detail=noise["detail"].As<FastNoiseLite>().GetNoise3Dv(q)*.5+.5,fine=noise["fine"].As<FastNoiseLite>().GetNoise3Dv(q)*.5+.5,shape=0,horizontal=new Vector2(p.X-.5f,p.Z-.5f).Length()*2,vertical=Smooth(0,softness,height)*(1-Smooth(1-softness,1,height));
        switch(kind){case 0:var point=new Vector3(p.X,(float)height,p.Z);double radiusScale=.55+coverage*.7;shape=(1-((point-new Vector3(.5f,.26f,.5f))/new Vector3(.38f,.27f,.38f)/(float)radiusScale).Length())*.25;foreach(var item in noise["lobes"].AsGodotArray()){var lobe=item.AsVector4();double distance=lobe.W*radiusScale-(point-new Vector3(lobe.X,lobe.Y,lobe.Z)).Length(),blend=Math.Clamp(.5+.5*(distance-shape)/.07,0,1);shape=shape+(distance-shape)*blend+.07*blend*(1-blend);}shape+=(macro-.5)*N(v,"cloud_macro",.65)*.18+(detail-.5)*N(v,"cloud_detail",.35)*.12;break;case 1:shape=macro-(1-coverage)*.8-Math.Abs(height-.5)*.25+(detail-.5)*N(v,"cloud_detail",.35)*.3;break;case 2:double streak=Math.Abs(macroNoise.GetNoise3Dv(q*new Vector3(1,3,5)));shape=coverage*.35-streak-Math.Abs(height-.5)*.3+(detail-.5)*.08;break;case 3:shape=macro+detail*.3-(1-coverage)*1.1-horizontal*.15+(1-height)*.15;break;case 4:shape=macro+coverage-.7;break;case 5:shape=1;vertical*=Math.Exp(-height*N(v,"cloud_profile",1));break;}double edge=1-Smooth(softness,softness*4,Math.Abs(shape));shape-=fine*N(v,"cloud_erosion",.25)*edge*.35;return Math.Clamp(Smooth(-softness,softness,shape)*Math.Pow(Math.Max(0,vertical),N(v,"cloud_profile",1)),0,1);
    }
}
