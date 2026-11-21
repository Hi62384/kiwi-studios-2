using Godot;
using System;
using System.Linq;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;

public partial class ModelModifiers : RefCounted
{
    private readonly ModelMeshOperations _mesh=new();
    private readonly ModelGeometryOperations _geometry=new();
    private static Variant Value(Settings values,string key,Variant fallback)=>values.TryGetValue(key,out var value)?value:fallback;
    private static Resource Empty()=>new KiwiModelMesh();
    public Resource evaluate(Resource component)
    {
        var source=component.Get("mesh").As<Resource>();var mesh=source==null?Empty():_mesh.copy_mesh(source);
        foreach(Variant value in component.Get("modifiers").AsGodotArray())
        {var settings=value.AsGodotDictionary();if(!Value(settings,"enabled",true).AsBool())continue;if(mesh.Get("vertices").AsVector3Array().Length>100000||mesh.Get("faces").AsGodotArray().Count>100000)break;mesh=apply(mesh,settings);}
        return mesh;
    }
    public Resource apply(Resource mesh,Settings settings)
    {
        var result=_mesh.copy_mesh(mesh);int axis=Math.Clamp(Value(settings,"axis",0).AsInt32(),0,2);float amount=(float)Value(settings,"amount",1.0).AsDouble();string kind=Value(settings,"type","").AsString();
        switch(kind)
        {
            case "Mirror":
            {
                var half=mesh;
                if(Value(settings,"bisect",true).AsBool())
                {
                    Vector3 direction=Vector3.Zero;direction[axis]=_mesh.bounds(mesh).GetCenter()[axis]>=0?-1:1;half=_geometry.clip_plane(mesh,direction,0);var data=new ModelMeshOperations.Snapshot(half);var cap=new List<int>();
                    for(int f=0;f<data.Faces.Length;f++)if(data.Faces[f].All(index=>Mathf.Abs(data.Vertices[index][axis])<=.00001f))cap.Add(f);
                    half=_geometry.remove_faces(half,cap.ToArray());
                }
                result=_mesh.copy_mesh(half);Vector3 scale=Vector3.One;scale[axis]=-1;_mesh.append_mesh(result,half,new Transform3D(Basis.FromScale(scale),Vector3.Zero),0);result=_geometry.weld(result,.0001);break;
            }
            case "Linear array":case "Radial array":
            {
                int count=Math.Clamp(Value(settings,"count",3).AsInt32(),1,64);Vector3 direction=Vector3.Zero;direction[axis]=1;
                if(kind=="Radial array"){result=Empty();result.Set("smooth",mesh.Get("smooth"));}
                int vertices=mesh.Get("vertices").AsVector3Array().Length;
                for(int i=kind=="Radial array"?0:1;i<count;i++)
                {
                    if(result.Get("vertices").AsVector3Array().Length+vertices>150000)break;var transform=new Transform3D(Basis.Identity,direction*amount*i);
                    if(kind=="Radial array"){var basis=new Basis(direction,Mathf.Tau*i/count);Vector3 offset=axis!=0?Vector3.Right:Vector3.Forward;transform=new Transform3D(basis,basis*offset*amount);}
                    _mesh.append_mesh(result,mesh,transform,0);
                }
                break;
            }
            case "Subdivision":
                for(int i=0,count=Math.Clamp(Value(settings,"count",1).AsInt32(),1,3);i<count;i++){if(result.Get("faces").AsGodotArray().Count>20000)break;result=_geometry.subdivide(result,Array.Empty<int>());}break;
            case "Smooth":result=_geometry.smooth_mesh(result,Mathf.Clamp(amount,0,1),Math.Clamp(Value(settings,"count",1).AsInt32(),1,8));result.Set("smooth",true);break;
            case "Solidify":
            {
                var data=new ModelMeshOperations.Snapshot(mesh);var normals=new Vector3[data.Vertices.Length];for(int f=0;f<data.Faces.Length;f++){Vector3 normal=data.Normal(f);foreach(int index in data.Faces[f])normals[index]+=normal;}
                int offset=data.Vertices.Length;var points=new Vector3[offset*2];Array.Copy(data.Vertices,points,offset);for(int i=0;i<offset;i++)points[offset+i]=data.Vertices[i]-normals[i].Normalized()*amount;result.Set("vertices",points);
                for(int f=0;f<data.Faces.Length;f++){int[] face=data.Faces[f].Select(index=>index+offset).ToArray();Vector2[] uv=data.Uv[f];Array.Reverse(face);Array.Reverse(uv);result.Call("add_face",face,uv,data.Materials[f]);}
                foreach(Variant value in mesh.Call("edges").AsGodotArray())
                {
                    var edge=value.AsGodotDictionary();int[] adjacent=edge["faces"].AsInt32Array();if(adjacent.Length!=1)continue;int[] face=data.Faces[adjacent[0]];int a=edge["a"].AsInt32(),b=edge["b"].AsInt32();if(face[(Array.IndexOf(face,a)+1)%face.Length]!=b)(a,b)=(b,a);result.Call("add_face",new[]{b,a,a+offset,b+offset});
                }
                break;
            }
            case "Twist":case "Taper":
            {
                var box=_mesh.bounds(mesh);float extent=Mathf.Max(.001f,box.Size[axis]);Vector3 direction=Vector3.Zero;direction[axis]=1;var points=result.Get("vertices").AsVector3Array();
                for(int i=0;i<points.Length;i++){Vector3 p=points[i];float t=(p[axis]-box.Position[axis])/extent;if(kind=="Twist")p=new Basis(direction,Mathf.DegToRad(amount)*t)*p;else for(int j=0;j<3;j++)if(j!=axis)p[j]*=Mathf.Max(.02f,1+amount*t);points[i]=p;}result.Set("vertices",points);break;
            }
            case "Bevel":var bevel=_geometry.bevel(mesh,Array.Empty<int>(),amount);if(bevel!=null)result=bevel;break;
        }
        return result;
    }
}
