using Godot;
using System;
using System.Linq;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;
public partial class FogTransportOperations:RefCounted
{
    private static double Number(Settings d,string key,double fallback=0)=>d.GetValueOrDefault(key,fallback).AsDouble();
    private static Vector3 Vector(Settings d,string key,Vector3 fallback)=>d.GetValueOrDefault(key,fallback).AsVector3();
    public Settings grid(int n)
    {
        var cache=GD.Load<GDScript>("res://scripts/actors/fog/fog_transport_solver.gd").Get("grids").AsGodotDictionary();if(cache.TryGetValue(n,out var cached))return cached.AsGodotDictionary();var neighbors=new int[n*n*n*6];var positions=new Vector3[n*n*n];for(int z=0;z<n;z++)for(int y=0;y<n;y++)for(int x=0;x<n;x++){int i=x+n*(y+n*z);positions[i]=(new Vector3(x,y,z)+Vector3.One*.5f)/n-Vector3.One*.5f;for(int axis=0;axis<3;axis++){int coordinate=axis==0?x:axis==1?y:z,stride=axis==0?1:axis==1?n:n*n;neighbors[i*6+axis*2]=coordinate>0?i-stride:-1;neighbors[i*6+axis*2+1]=coordinate<n-1?i+stride:-1;}}var result=new Settings{["neighbors"]=neighbors,["positions"]=positions};cache[n]=result;return result;
    }
    public Settings initialize(int n,Vector3 size,float[] density)
    {
        n=Math.Clamp(n,4,32);size=size.Abs().Max(Vector3.One*.01f);int count=n*n*n;var rho=density.Length==count?(float[])density.Clone():new float[count];for(int i=0;i<count;i++)rho[i]=float.IsFinite(rho[i])?Math.Max(0,rho[i]):0;return new Settings{["fog_n"]=n,["fog_size"]=size,["fog_density"]=rho,["fog_velocity"]=new Vector3[count],["fog_solid"]=new byte[count],["fog_boundary_velocity"]=new Vector3[count],["fog_pressure"]=new float[count],["fog_time"]=0.0,["fog_step"]=0,["fog_emitted"]=0.0,["fog_lost"]=0.0,["fog_trapped"]=new Settings(),["fog_bursts"]=new Settings(),["fog_clamped"]=false};
    }
    public double total_mass(Settings state){double amount=state["fog_density"].AsFloat32Array().Sum(x=>(double)x);foreach(var value in state["fog_trapped"].AsGodotDictionary().Values)amount+=value.AsDouble();var size=state["fog_size"].AsVector3();return amount*size.X*size.Y*size.Z/Math.Pow(state["fog_n"].AsDouble(),3);}
    public void set_obstacles(Settings state,byte[] solid,Vector3[] boundary)
    {
        var rho=state["fog_density"].AsFloat32Array();if(solid.Length!=rho.Length||boundary.Length!=rho.Length)return;var neighbors=grid(state["fog_n"].AsInt32())["neighbors"].AsInt32Array();var trapped=state["fog_trapped"].AsGodotDictionary();foreach(var key in trapped.Keys.ToArray()){int i=key.AsInt32();if(solid[i]==0){rho[i]+=trapped[key].AsSingle();trapped.Remove(key);}}for(int i=0;i<rho.Length;i++){if(solid[i]==0||rho[i]<=0)continue;int free=0;for(int slot=0;slot<6;slot++){int j=neighbors[i*6+slot];if(j>=0&&solid[j]==0)free++;}if(free==0)trapped[i]=trapped.GetValueOrDefault(i,0.0).AsDouble()+rho[i];else{float share=rho[i]/free;for(int slot=0;slot<6;slot++){int j=neighbors[i*6+slot];if(j>=0&&solid[j]==0)rho[j]+=share;}}rho[i]=0;}state["fog_density"]=rho;state["fog_solid"]=(byte[])solid.Clone();state["fog_boundary_velocity"]=(Vector3[])boundary.Clone();state["fog_trapped"]=trapped;
    }
    public void inject(Settings state,int[] cells,float[] weights,double mass,Vector3 velocity)
    {
        if(cells.Length!=weights.Length||mass<=0||!double.IsFinite(mass))return;var rho=state["fog_density"].AsFloat32Array();var v=state["fog_velocity"].AsVector3Array();var solid=state["fog_solid"].AsByteArray();double sum=0;for(int k=0;k<cells.Length;k++)if(cells[k]>=0&&cells[k]<rho.Length&&solid[cells[k]]==0)sum+=Math.Max(0,weights[k]);if(sum<=0)return;var size=state["fog_size"].AsVector3();double cellVolume=(double)size.X*size.Y*size.Z/rho.Length;for(int k=0;k<cells.Length;k++){int i=cells[k];if(i<0||i>=rho.Length||solid[i]!=0)continue;float added=(float)(mass*Math.Max(0,weights[k])/sum/cellVolume),next=rho[i]+added;v[i]=(v[i]*rho[i]+velocity*added)/Math.Max(.000001f,next);rho[i]=next;}state["fog_density"]=rho;state["fog_velocity"]=v;state["fog_emitted"]=Number(state,"fog_emitted")+mass;
    }
    public Vector3 velocity_sample(Vector3[] velocities,byte[] solid,Vector3 point,Vector3 size,int n)
    {
        var p=((point/size+Vector3.One*.5f)*n-Vector3.One*.5f).Clamp(Vector3.Zero,Vector3.One*(n-1));var floor=p.Floor();var f=p-floor;var value=Vector3.Zero;float sum=0;for(int z=0;z<2;z++)for(int y=0;y<2;y++)for(int x=0;x<2;x++){int cx=Math.Min((int)floor.X+x,n-1),cy=Math.Min((int)floor.Y+y,n-1),cz=Math.Min((int)floor.Z+z,n-1),i=cx+n*(cy+n*cz);if(solid[i]!=0)continue;float weight=(x==1?f.X:1-f.X)*(y==1?f.Y:1-f.Y)*(z==1?f.Z:1-f.Z);value+=velocities[i]*weight;sum+=weight;}return value/Math.Max(.000001f,sum);
    }
    public Vector3 field_acceleration(GArray fields,Vector3 point,double time)
    {
        var value=Vector3.Zero;foreach(var item in fields){var field=item.AsGodotDictionary();if(!field.GetValueOrDefault("enabled",true).AsBool())continue;var offset=point-Vector(field,"center",Vector3.Zero);double radius=Math.Max(.001,Number(field,"radius",1)),distance=offset.Length()/radius;if(distance>1)continue;float strength=(float)(Number(field,"strength",1)*Math.Pow(1-distance,Math.Max(0,Number(field,"falloff",1))));var direction=Vector(field,"direction",Vector3.Up);switch((int)Number(field,"type")){case 1:direction=offset.Normalized();break;case 2:direction=-offset.Normalized();break;case 3:direction=direction.Normalized().Cross(offset)/(float)radius;break;case 4:direction=new Vector3((float)Math.Sin(point.Z+time),(float)Math.Cos(point.X-time),(float)Math.Sin(point.Y+time));break;}value+=direction*strength;}return value;
    }
}
