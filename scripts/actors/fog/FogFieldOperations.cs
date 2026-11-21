using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
public partial class FogFieldOperations:RefCounted
{
    private readonly FogGroundSamplerOperations _ground=new();
    private readonly FogCloudFieldOperations _cloud=new();
    private static double N(Settings v,string key,double fallback=0)=>v.GetValueOrDefault(key,fallback).AsDouble();
    private static Vector3 V(Settings v,string key,Vector3 fallback)=>v.GetValueOrDefault(key,fallback).AsVector3();
    public double sample_volume(Godot.Collections.Array<Image> images,Vector3 point,bool repeat)
    =>SampleVolume(Variant.From(images).AsGodotArray(),point,repeat);
    private static double SampleVolume(Godot.Collections.Array images,Vector3 point,bool repeat)
    {
        if(images.Count==0)return 0;var first=images[0].As<Image>();int width=first.GetWidth(),height=first.GetHeight(),depth=images.Count;var p=point*new Vector3(width,height,depth)-Vector3.One*.5f;var floor=p.Floor();var f=p-floor;double result=0;int Cell(int value,int size)=>repeat?((value%size)+size)%size:Math.Clamp(value,0,size-1);for(int z=0;z<2;z++)for(int y=0;y<2;y++)for(int x=0;x<2;x++){int cx=Cell((int)floor.X+x,width),cy=Cell((int)floor.Y+y,height),cz=Cell((int)floor.Z+z,depth);result+=images[cz].As<Image>().GetPixel(cx,cy).R*(x==1?f.X:1-f.X)*(y==1?f.Y:1-f.Y)*(z==1?f.Z:1-f.Z);}return result;
    }
    public double shape_distance(Vector3 p,Vector3 dimensions,int shape)
    {
        var e=dimensions.Abs().Max(Vector3.One*.001f)*.5f;float minimum=Math.Min(e.X,Math.Min(e.Y,e.Z));switch(shape){case 1:return p.Length()-minimum;case 2:return ((p/e).Length()-1)*minimum;case 3:return Math.Max(new Vector2(p.X/e.X,p.Z/e.Z).Length()-1,Math.Abs(p.Y)/e.Y-1)*minimum;case 4:return Math.Max(new Vector2(p.X/e.X,p.Z/e.Z).Length()-(.5-p.Y/(e.Y*2)),Math.Abs(p.Y)/e.Y-1)*minimum;case 5:float r=Math.Min(e.X,e.Z);p.Y-=Math.Clamp(p.Y,-Math.Max(0,e.Y-r),Math.Max(0,e.Y-r));return p.Length()-r;}var q=p.Abs()-e;return q.Max(Vector3.Zero).Length()+Math.Min(Math.Max(q.X,Math.Max(q.Y,q.Z)),0);
    }
    private static double Finish(Settings v,int kind,double value,bool clamp)
    {
        if(kind is 1 or 2 or 3)value=Math.Pow(Math.Clamp((value-N(v,"start"))/Math.Max(.0001,N(v,"end",1)-N(v,"start")),0,1),Math.Max(.01,N(v,"falloff",1)));if(kind>=4&&(clamp||kind!=6))value=Math.Pow(Math.Max(0,value-N(v,"threshold")),Math.Max(.01,N(v,"contrast",1)));if(v.GetValueOrDefault("invert",false).AsBool())value=1-value;return clamp?Math.Clamp(value,0,1):Math.Max(0,value);
    }
    private double Shape(Settings v,Vector3 p){double distance=shape_distance(Basis.FromEuler(V(v,"shape_rotation",Vector3.Zero)*(Mathf.Pi/180)).Inverse()*(p-Vector3.One*.5f),V(v,"shape_size",Vector3.One),(int)N(v,"shape"));return Mathf.SmoothStep(0,(float)Math.Max(.0001,N(v,"shape_edge",.05)),(float)-distance);}
    public double sample_prepared(Settings source,Vector3 unit,Vector3 world)
    {
        var v=source["values"].AsGodotDictionary();int kind=(int)N(v,"mode");var p=(v.GetValueOrDefault("world_space",false).AsBool()?world:unit)*V(v,"scale",Vector3.One)+V(v,"offset",Vector3.Zero);double value=N(v,"value",1);switch(kind){case 1:value=p.Y;break;case 2:value=1-(p-Vector3.One*.5f).Length()*2;break;case 3:value=p.Dot(V(v,"direction",Vector3.Up).Normalized());break;case 4:case 5:case 7:case 8:value=SampleVolume(source["images"].AsGodotArray(),p,kind!=7);if(kind==7&&!new Aabb(Vector3.Zero,Vector3.One).HasPoint(p))value=0;if(kind==8&&(int)N(v,"cloud_type") is 4 or 5){double ground=N(v,"cloud_ground_height");if(source.TryGetValue("ground",out var groundImage)&&groundImage.VariantType==Variant.Type.Object&&groundImage.AsGodotObject() is Image image)ground=_ground.sample_height(image,unit);double height=Math.Max(0,world.Y-ground),attenuation=Math.Exp(-height/Math.Max(.01,N(v,"cloud_ground_falloff",2)));value=(int)N(v,"cloud_type")==5?attenuation:value*attenuation;}break;case 6:value=Shape(v,p);break;}return Finish(v,kind,value,false);
    }
    public double sample_mask(Settings v,Vector3 point,FastNoiseLite noise,Settings paint,int size,Settings cloud)
    {
        var p=point*V(v,"scale",Vector3.One)+V(v,"offset",Vector3.Zero);int mode=(int)N(v,"mode");double value=N(v,"value",1);switch(mode){case 1:value=p.Y;break;case 2:value=1-(p-Vector3.One*.5f).Length()*2;break;case 3:value=p.Dot(V(v,"direction",Vector3.Up).Normalized());break;case 4:value=Math.Clamp(noise.GetNoise3Dv(p)*.5+.5,0,1);break;case 5:var q=(p*32).Floor();value=paint.GetValueOrDefault(new Vector3I(Math.Clamp((int)q.X,0,31),Math.Clamp((int)q.Y,0,31),Math.Clamp((int)q.Z,0,31)),0.0).AsDouble();break;case 6:value=Shape(v,p);break;case 8:value=cloud.Count>0?_cloud.sample_density(v,cloud,p,Vector3.Zero):0;break;}return Finish(v,mode,value,true);
    }
    public Settings paint_dab(Settings source,Vector3I center,double radius,double strength,double falloff,int mode)
    {
        var result=source.Duplicate();int extent=(int)Math.Ceiling(radius);for(int z=Math.Max(0,center.Z-extent);z<Math.Min(32,center.Z+extent+1);z++)for(int y=Math.Max(0,center.Y-extent);y<Math.Min(32,center.Y+extent+1);y++)for(int x=Math.Max(0,center.X-extent);x<Math.Min(32,center.X+extent+1);x++){var p=new Vector3I(x,y,z);double distance=new Vector3(x-center.X,y-center.Y,z-center.Z).Length()/Math.Max(.5,radius);if(distance>1)continue;double weight=Math.Pow(1-distance,falloff),value=source.GetValueOrDefault(p,0.0).AsDouble(),target=strength;switch(mode){case 0:target=value+strength*weight;break;case 1:target=value-strength*weight;break;case 2:target=value+(strength-value)*weight;break;case 3:double average=value;foreach(var delta in new[]{Vector3I.Left,Vector3I.Right,Vector3I.Up,Vector3I.Down,Vector3I.Forward,Vector3I.Back})average+=source.GetValueOrDefault(p+delta,0.0).AsDouble();target=value+(average/7-value)*strength*weight;break;case 4:target=value*(1-weight);break;}if(target<=.0001)result.Remove(p);else result[p]=Math.Clamp(target,0,1);}return result;
    }
    public double combine(double a,double b,int mode,double strength){double weight=Math.Clamp(strength,0,1);return mode switch{0=>Math.Max(0,a+b*strength),1=>Math.Max(0,a*(1+(b-1)*weight)),2=>a+(Math.Max(a,b)-a)*weight,3=>a+(Math.Min(a,b)-a)*weight,4=>Math.Max(0,a-b*strength),_=>Math.Max(0,a+(b-a)*weight)};}
}
