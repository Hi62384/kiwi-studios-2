using Godot;
using System;
using System.Linq;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using Topology=ModelGeometryOperations.Topology;

public partial class ModelPrimitives : RefCounted
{
    private readonly ModelMeshOperations _mesh=new();
    private readonly ModelNaturalSettings _naturalSettings=new();
    private readonly ModelNaturalGenerator _natural=new();
    private static Variant Value(Settings values,string key,Variant fallback)=>values.TryGetValue(key,out var value)?value:fallback;
    public Settings defaults(string kind)
    {
        if(ModelNaturalSettings.Accepts(kind))return _naturalSettings.defaults(kind);
        return new Settings{["size"]=kind=="Beam"?new Vector3(.25f,.25f,3):kind=="Panel"?new Vector3(2,.1f,2):Vector3.One,["radius"]=.5,["height"]=1.0,["segments"]=24,["teeth"]=16,["tooth_depth"]=.12,["hole"]=kind=="Pipe"?.325:0,["steps"]=6,["inner_ratio"]=.7};
    }
    public Resource create(string kind,Settings parameters)
    {
        if(ModelNaturalSettings.Accepts(kind))return _natural.Generate(kind,parameters,()=>false)["mesh"].As<Resource>();
        var settings=defaults(kind);settings.Merge(parameters,true);parameters=settings;Vector3 dimensions=Value(parameters,"size",Vector3.One).AsVector3();float radius=(float)Value(parameters,"radius",.5).AsDouble(),height=(float)Value(parameters,"height",1.0).AsDouble();int segments=Math.Clamp(Value(parameters,"segments",24).AsInt32(),3,128);
        if(kind is "Box" or "Beam" or "Panel")return box(dimensions);
        if(kind is "Cylinder" or "Cone" or "Gear" or "Pipe" or "Bolt")
        {
            var profile=new List<Vector2>();
            if(kind=="Gear")
            {int teeth=Math.Clamp(Value(parameters,"teeth",16).AsInt32(),4,64);for(int i=0;i<teeth*4;i++){double angle=Math.Tau*i/(teeth*4.0),r=radius+(i%4 is 1 or 2?Value(parameters,"tooth_depth",.12).AsDouble():0);profile.Add(new Vector2((float)Math.Cos(angle),(float)Math.Sin(angle))*(float)r);}}
            else {if(kind=="Bolt")segments=6;for(int i=0;i<segments;i++){double angle=Math.Tau*i/segments;profile.Add(new Vector2((float)Math.Cos(angle),(float)Math.Sin(angle))*radius);}}
            if(kind=="Bolt")
            {
                var bolt=Prism(profile.ToArray(),height*.2,0,1);for(int i=0;i<bolt.Points.Count;i++){Vector3 p=bolt.Points[i];p.Y+=height*.4f;bolt.Points[i]=p;}
                var shaftProfile=new Vector2[24];for(int i=0;i<24;i++){double angle=Math.Tau*i/24;shaftProfile[i]=new Vector2((float)Math.Cos(angle),(float)Math.Sin(angle))*(radius*.45f);}
                bolt.Append(Prism(shaftProfile,height*.85,0,1),new Transform3D(Basis.Identity,new Vector3(0,-height*.1f,0)));return bolt.Build();
            }
            return prism(profile.ToArray(),height,Value(parameters,"hole",0.0).AsDouble(),kind=="Cone"?0:1);
        }
        if(kind=="Arch")
        {
            var profile=new List<Vector2>();double inner=radius*Value(parameters,"inner_ratio",.7).AsDouble();
            for(int i=0;i<=segments;i++){double angle=Math.PI*i/segments;profile.Add(new Vector2((float)Math.Cos(angle),(float)Math.Sin(angle))*radius);}
            for(int i=segments;i>=0;i--){double angle=Math.PI*i/segments;profile.Add(new Vector2((float)Math.Cos(angle),(float)Math.Sin(angle))*(float)inner);}
            var result=Prism(profile.ToArray(),height,0,1);for(int i=0;i<result.Points.Count;i++){Vector3 p=result.Points[i];result.Points[i]=new Vector3(p.X,p.Z,p.Y);}for(int f=0;f<result.Faces.Count;f++){Array.Reverse(result.Faces[f]);Array.Reverse(result.Uv[f]);}return result.Build();
        }
        if(kind=="Stairs")
        {
            var result=new Topology();int count=Math.Clamp(Value(parameters,"steps",6).AsInt32(),1,64);
            for(int i=0;i<count;i++){Vector3 size=new(dimensions.X,dimensions.Y*(i+1f)/count,dimensions.Z/count);result.Append(Box(size),new Transform3D(Basis.Identity,new Vector3(0,size.Y*.5f,dimensions.Z*((i+.5f)/count-.5f))));}
            return result.Build();
        }
        using PrimitiveMesh? primitive=kind switch
        {
            "Sphere"=>new SphereMesh{Radius=radius,Height=radius*2,RadialSegments=segments,Rings=Math.Max(4,segments/2)},
            "Capsule"=>new CapsuleMesh{Radius=radius,Height=Mathf.Max(height,radius*2),RadialSegments=segments},
            "Plane"=>new PlaneMesh{Size=new Vector2(dimensions.X,dimensions.Z)},
            "Torus"=>new TorusMesh{InnerRadius=radius*.65f,OuterRadius=radius,Rings=segments,RingSegments=12},
            "Prism"=>new PrismMesh{Size=dimensions},_=>null
        };
        var mesh=_mesh.from_mesh(primitive);mesh.Set("smooth",kind is "Sphere" or "Capsule" or "Torus");return mesh;
    }
    public Resource box(Vector3 size)=>Box(size).Build();
    internal static Topology Box(Vector3 size)
    {
        var result=new Topology();for(int i=0;i<8;i++)result.Points.Add((new Vector3(i&1,(i>>1)&1,(i>>2)&1)-Vector3.One*.5f)*size);
        foreach(int[] face in new[]{new[]{0,1,3,2},new[]{4,6,7,5},new[]{0,4,5,1},new[]{2,3,7,6},new[]{0,2,6,4},new[]{1,5,7,3}})
        {int f=result.AddFace(face,new[]{Vector2.Zero,Vector2.Right,Vector2.One,Vector2.Down});Vector3 center=Vector3.Zero;foreach(int index in face)center+=result.Points[index];center/=face.Length;if(ModelGeometryOperations.Normal(result.Points,face).Dot(center)<0){Array.Reverse(face);Array.Reverse(result.Uv[f]);}}
        return result;
    }
    public Resource prism(Vector2[] profile,double height,double hole,double topScale)=>Prism(profile,height,hole,topScale).Build();
    internal static Topology Prism(Vector2[] profile,double height,double hole,double topScale)
    {
        var result=new Topology();int count=profile.Length;
        for(int level=0;level<2;level++)foreach(Vector2 p in profile)result.Points.Add(new Vector3(p.X*(float)(level==1?topScale:1),(float)((level-.5)*height),p.Y*(float)(level==1?topScale:1)));
        if(topScale==0){result.Points.RemoveRange(count,count);result.Points.Add(new Vector3(0,(float)(height*.5),0));}
        for(int i=0;i<count;i++){int j=(i+1)%count;result.AddFace(topScale==0?new[]{i,j,count}:new[]{i,j,j+count,i+count});}
        if(hole>0&&topScale>0)
        {
            int offset=result.Points.Count;for(int level=0;level<2;level++)foreach(Vector2 p in profile){Vector2 q=p.Normalized()*(float)Math.Min(hole,p.Length()*.95);result.Points.Add(new Vector3(q.X,(float)((level-.5)*height),q.Y));}
            for(int i=0;i<count;i++){int j=(i+1)%count;result.AddFace(new[]{offset+j,offset+i,offset+i+count,offset+j+count});result.AddFace(new[]{i,offset+i,offset+j,j});result.AddFace(new[]{i+count,j+count,offset+j+count,offset+i+count});}
        }
        else {result.AddFace(Enumerable.Range(0,count).Select(i=>count-1-i).ToArray());if(topScale>0)result.AddFace(Enumerable.Range(count,count).ToArray());}
        double area=0;for(int i=0;i<count;i++)area+=profile[i].Cross(profile[(i+1)%count]);
        for(int f=0;f<result.Faces.Count;f++)
        {
            Vector3 expected=Vector3.Zero;
            if(f<count){Vector2 edge=profile[(f+1)%count]-profile[f];expected=new Vector3(edge.Y,0,-edge.X)*(area>=0?1:-1);}else if(hole<=0)expected=f==count?Vector3.Down:Vector3.Up;
            if(!expected.IsZeroApprox()&&ModelGeometryOperations.Normal(result.Points,result.Faces[f]).Dot(expected)<0){Array.Reverse(result.Faces[f]);Array.Reverse(result.Uv[f]);}
        }
        return result;
    }
}
