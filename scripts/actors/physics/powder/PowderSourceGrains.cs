using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
public partial class PowderSourceOperations
{
    internal sealed class GrainBuffer
    {
        internal readonly Settings State;internal readonly Dictionary<string,List<Vector3>> Vectors=new();internal readonly Dictionary<string,List<float>> Floats=new();internal readonly Dictionary<string,List<int>> Ints=new();internal readonly Dictionary<string,List<byte>> Bytes=new();internal readonly List<double> Births;internal long Next,Emitted;
        internal GrainBuffer(Settings state){State=state;foreach(string key in new[]{"points","velocities","powder_birth_positions"})Vectors[key]=new List<Vector3>(state[key].AsVector3Array());foreach(string key in new[]{"powder_radii","powder_masses","powder_compaction","powder_sleep","powder_settle"})Floats[key]=new List<float>(state[key].AsFloat32Array());foreach(string key in new[]{"powder_ids","powder_contacts"})Ints[key]=new List<int>(state[key].AsInt32Array());foreach(string key in new[]{"powder_sources","powder_phase"})Bytes[key]=new List<byte>(state[key].AsByteArray());Births=new List<double>(state["powder_birth_times"].AsFloat64Array());Next=state["powder_next_id"].AsInt64();Emitted=state["powder_emitted"].AsInt64();}
        internal void Commit(){foreach(var entry in Vectors)State[entry.Key]=entry.Value.ToArray();foreach(var entry in Floats)State[entry.Key]=entry.Value.ToArray();foreach(var entry in Ints)State[entry.Key]=entry.Value.ToArray();foreach(var entry in Bytes)State[entry.Key]=entry.Value.ToArray();State["powder_birth_times"]=Births.ToArray();State["powder_next_id"]=Next;State["powder_emitted"]=Emitted;}
    }
    internal void Append(GrainBuffer buffer,Vector3 point,Vector3 velocity,Settings values,Transform3D pose,double birth,int source)
    {
        var scale=pose.Basis.Scale.Abs();double radius=Math.Max(.0001,values["powder_radius"].AsDouble()*Math.Min(scale.X,Math.Min(scale.Y,scale.Z)));using var rng=rng_for(values["powder_seed"].AsInt64(),buffer.Next+1000000);radius*=1+rng.RandfRange(-1,1)*Math.Clamp(Get(values,"powder_size_variation",0).AsDouble(),0,.5);buffer.Vectors["points"].Add(point);buffer.Vectors["velocities"].Add(velocity);buffer.Ints["powder_ids"].Add((int)buffer.Next++);buffer.Floats["powder_radii"].Add((float)radius);buffer.Floats["powder_masses"].Add((float)(Math.Max(.001,values["powder_density"].AsDouble())*4/3*Math.PI*radius*radius*radius));buffer.Births.Add(birth);buffer.Vectors["powder_birth_positions"].Add(point);buffer.Bytes["powder_sources"].Add((byte)source);foreach(string key in new[]{"powder_compaction","powder_sleep","powder_settle"})buffer.Floats[key].Add(0);buffer.Ints["powder_contacts"].Add(0);buffer.Bytes["powder_phase"].Add(0);
    }
    internal void Spawn(GrainBuffer buffer,Settings values,Transform3D pose,Vector3 velocity,double birth)
    {
        using var rng=rng_for(values["powder_seed"].AsInt64(),buffer.Next);var axis=values["powder_emit_direction"].AsVector3().Normalized();if(axis.IsZeroApprox())axis=Vector3.Down;var tangent=axis.Cross(Math.Abs(axis.X)<.9?Vector3.Right:Vector3.Up).Normalized();var bitangent=axis.Cross(tangent);double angle=rng.Randf()*Math.Tau;var radial=tangent*(float)Math.Cos(angle)+bitangent*(float)Math.Sin(angle);var offset=Vector3.Zero;switch(values["powder_emit_shape"].AsInt32()){case 1:offset=radial*(float)(Math.Sqrt(rng.Randf())*values["powder_emit_radius"].AsDouble());break;case 2:offset=new Vector3(rng.Randf()-.5f,rng.Randf()-.5f,rng.Randf()-.5f)*values["powder_emit_dimensions"].AsVector3();break;case 3:double y=rng.RandfRange(-1,1),r=Math.Sqrt(Math.Max(0,1-y*y));offset=new Vector3((float)(r*Math.Cos(angle)),(float)y,(float)(r*Math.Sin(angle)))*(float)(Math.Pow(rng.Randf(),1.0/3)*values["powder_emit_radius"].AsDouble());break;}var direction=(axis+radial*(float)(values["powder_spread"].AsDouble()*Math.Sqrt(rng.Randf()))).Normalized();Append(buffer,pose*offset,velocity+pose.Basis*(values["powder_emit_velocity"].AsVector3()+direction*values["powder_emit_speed"].AsSingle()),values,pose,birth,1);buffer.Emitted++;
    }
    public void append(Settings state,Vector3 point,Vector3 velocity,Settings values,Transform3D pose,double birth,int source){var buffer=new GrainBuffer(state);Append(buffer,point,velocity,values,pose,birth,source);buffer.Commit();}
    public void spawn(Settings state,Settings values,Transform3D pose,Vector3 velocity,double birth){var buffer=new GrainBuffer(state);Spawn(buffer,values,pose,velocity,birth);buffer.Commit();}
}
