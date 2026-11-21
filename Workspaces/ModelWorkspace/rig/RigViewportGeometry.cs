using Godot;
using System;
using Settings = Godot.Collections.Dictionary;
using Transforms = Godot.Collections.Array<Godot.Transform3D>;

public partial class RigViewportGeometry : RefCounted
{
    private readonly RigMath _math=new();
    public Transforms world_bones(Control canvas,RigEditor editor,bool compareRest)
    {
        var armature=editor.rig(); if(armature==null) return new();
        var result=_math.globals(armature.Get("bones").AsGodotArray(),!compareRest && editor.mode is "Pose" or "Weight");
        var document=canvas.Get("session").As<RefCounted>().Get("document").As<Resource>(); var transform=document.Call("world_transform",armature).AsTransform3D();
        for(int i=0;i<result.Count;i++) result[i]=transform*result[i]; return result;
    }
    private static Vector2 Project(Control canvas,Vector3 point)=>canvas.Call("project",point).AsVector2();
    public Settings pick_bone(Control canvas,RigEditor editor,bool compareRest,Vector2 point,bool jointsOnly)
    {
        if(!editor.show_bones && editor.mode!="Draw") return new(); var armature=editor.rig(); if(armature==null) return new();
        var bones=armature.Get("bones").AsGodotArray(); var world=world_bones(canvas,editor,compareRest); var camera=canvas.Get("camera").As<Camera3D>(); float best=11; var result=new Settings();
        for(int i=0;i<world.Count;i++)
        {
            Vector3 end=_math.tail(bones[i].AsGodotDictionary(),world[i]);
            for(int endpoint=0;endpoint<2;endpoint++)
            {
                Vector3 p=endpoint==1?end:world[i].Origin; if(camera.IsPositionBehind(p)) continue; float distance=Project(canvas,p).DistanceTo(point);
                if(distance<best) { best=distance; result=new Settings { ["bone"]=i,["end"]=endpoint==1 }; }
            }
        }
        if(result.Count>0 || jointsOnly) return result;
        for(int i=0;i<world.Count;i++)
        {
            Vector3 end=_math.tail(bones[i].AsGodotDictionary(),world[i]); if(camera.IsPositionBehind(world[i].Origin)||camera.IsPositionBehind(end)) continue;
            float distance=Geometry2D.GetClosestPointToSegment(point,Project(canvas,world[i].Origin),Project(canvas,end)).DistanceTo(point);
            if(distance<best) { best=distance; result=new Settings { ["bone"]=i,["end"]=false,["line"]=true }; }
        }
        return result;
    }
    public Variant plane_hit(Control canvas,Vector2 point,Vector3 origin,Vector3 normal)
    {
        var ray=canvas.Call("ray",point).AsGodotDictionary(); Vector3 direction=ray["direction"].AsVector3(),start=ray["origin"].AsVector3(); float denominator=normal.Dot(direction);
        if(Mathf.Abs(denominator)<.000001f) return default; float t=normal.Dot(origin-start)/denominator;
        return t>=0?Variant.From(start+direction*t):default;
    }
    public Vector3 placement(Control canvas,RigEditor editor,bool compareRest,Vector2 point,string construction,double depth)
    {
        var snap=pick_bone(canvas,editor,compareRest,point,true);
        if(snap.Count>0)
        {
            var world=world_bones(canvas,editor,compareRest); int bone=snap["bone"].AsInt32();
            return snap["end"].AsBool()?_math.tail(editor.rig()!.Get("bones").AsGodotArray()[bone].AsGodotDictionary(),world[bone]):world[bone].Origin;
        }
        Vector3 anchor=editor.bounds().GetCenter(); var camera=canvas.Get("camera").As<Camera3D>(); Vector3 normal=camera.Basis.Z;
        if(construction is "Inside mesh" or "Surface")
        {
            var hit=canvas.Call("pick",point).AsGodotDictionary();
            if(hit.Count>0)
            {
                Vector3 hitPoint=hit["point"].AsVector3(); if(construction=="Surface") return hitPoint;
                var visual=canvas.Get("visuals").AsGodotDictionary()[hit["id"]].As<MeshInstance3D>();
                var ray=canvas.Call("ray",point).AsGodotDictionary(); Vector3 direction=ray["direction"].AsVector3(); var inverse=visual.Transform.AffineInverse();
                var geometry=visual.Mesh.GenerateTriangleMesh(); Vector3 far=hitPoint+direction*(visual.GetAabb().Size.Length()*visual.GlobalBasis.Scale.Length()+1);
                var exit=geometry.IntersectRay(inverse*far,(-(inverse.Basis*direction)).Normalized());
                if(exit.Count>0) return hitPoint.Lerp(visual.Transform*exit["position"].AsVector3(),.5f);
                return hitPoint;
            }
        }
        else if(construction=="XY") { normal=Vector3.Back;anchor.Z=(float)depth; }
        else if(construction=="YZ") { normal=Vector3.Right;anchor.X=(float)depth; }
        else if(construction=="XZ") { normal=Vector3.Up;anchor.Y=(float)depth; }
        if(construction=="View plane") anchor+=normal*(float)depth;
        Variant value=plane_hit(canvas,point,anchor,normal); return value.VariantType==Variant.Type.Vector3?value.AsVector3():anchor;
    }
    public Settings handles(Control canvas,RigEditor editor,bool compareRest)
    {
        var world=world_bones(canvas,editor,compareRest); if(editor.selected_bone<0 || editor.selected_bone>=world.Count) return new();
        Vector3 origin=world[editor.selected_bone].Origin; var camera=canvas.Get("camera").As<Camera3D>(); if(camera.IsPositionBehind(origin)) return new();
        float distance=Mathf.Max(.001f,-(camera.GlobalTransform.AffineInverse()*origin).Z);
        Vector2 point=camera.UnprojectPosition(origin); float length=camera.ProjectPosition(point+new Vector2(75,0),distance).DistanceTo(origin);
        var axes=new Godot.Collections.Array<Vector3> { Vector3.Right,Vector3.Up,Vector3.Back };
        if(canvas.Get("tool").AsString()=="Scale") { var basis=world[editor.selected_bone].Basis.Orthonormalized(); axes=new(){basis.X,basis.Y,basis.Z}; }
        var rings=new Godot.Collections.Array<Vector2[]>(); var ends=new Vector2[3];
        for(int i=0;i<3;i++)
        {
            ends[i]=Project(canvas,origin+axes[i]*length); var ring=new Vector2[65];
            for(int j=0;j<65;j++) { float angle=j*Mathf.Tau/64; ring[j]=Project(canvas,origin+(axes[(i+1)%3]*Mathf.Cos(angle)+axes[(i+2)%3]*Mathf.Sin(angle))*length*.8f); }
            rings.Add(ring);
        }
        return new(){["origin"]=origin,["center"]=Project(canvas,origin),["length"]=length,["axes"]=axes,["ends"]=ends,["rings"]=rings};
    }
    public int handle_at(string tool,Vector2 point,Settings geometry)
    {
        if(geometry.Count==0) return -2; Vector2 center=geometry["center"].AsVector2(); if(tool!="Rotate" && point.DistanceTo(center)<8) return -1;
        float best=8; int result=-2; var ends=geometry["ends"].AsVector2Array(); var rings=geometry["rings"].AsGodotArray();
        for(int i=0;i<3;i++)
        {
            if(tool=="Rotate")
            {
                var ring=rings[i].AsVector2Array();
                for(int j=0;j<64;j++) { float distance=point.DistanceTo(Geometry2D.GetClosestPointToSegment(point,ring[j],ring[j+1])); if(distance<best) {best=distance;result=i;} }
            }
            else { float distance=point.DistanceTo(Geometry2D.GetClosestPointToSegment(point,center.Lerp(ends[i],.3f),ends[i])); if(distance<best) {best=distance;result=i;} }
        }
        return result;
    }
}
