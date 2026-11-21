using Godot;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class RigPaintGeometry : RefCounted
{
    private readonly RigBindingGeometry _geometry=new();
    private readonly RigWeighting _weighting=new();
    public void paint(Control canvas,RigEditor editor,RefCounted state,Vector2 point,bool subtract,bool force)
    {
        if(state.Get("compare_rest").AsBool()) {editor.message="Turn off Compare rest before painting the posed mesh.";return;}
        long now=(long)Time.GetTicksMsec();if(!force&&now-state.Get("last_paint").AsInt64()<33) return;state.Set("last_paint",now);
        var armature=editor.rig();if(armature==null||armature.Get("bones").AsGodotArray().Count==0) return;
        var session=canvas.Get("session").As<RefCounted>();var document=session.Get("document").As<Resource>();var transform=document.Call("world_transform",armature).AsTransform3D();var inverse=transform.AffineInverse();var ray=canvas.Call("ray",point).AsGodotDictionary();
        Vector3 rayOrigin=ray["origin"].AsVector3(),direction=ray["direction"].AsVector3(),hitPoint=Vector3.Zero;double best=double.PositiveInfinity;Resource? chosen=null;
        var cache=state.Get("geometry_cache").AsGodotDictionary();var strokeCache=state.Get("stroke_geometry").AsGodotDictionary();bool stroking=state.Get("drag").AsString()=="weight";string rigId=armature.Get("id").AsString();
        foreach(var item in editor.meshes())
        {
            var binding=item.Get("binding").As<Resource>();if(binding==null||item.Get("skeleton_id").AsString()!=rigId||binding.Get("rigid_bone_id").AsString().Length>0) continue;
            var data=geometry(item,armature,false,stroking,cache,strokeCache);var hit=data["mesh"].As<TriangleMesh>().IntersectRay(inverse*rayOrigin,(inverse.Basis*direction).Normalized());
            if(hit.Count>0) {Vector3 worldHit=transform*hit["position"].AsVector3();double distance=worldHit.DistanceTo(rayOrigin);if(distance<best){chosen=item;hitPoint=worldHit;best=distance;}}
        }
        if(chosen==null) return;state.Set("hover_hit",new Settings{["point"]=hitPoint});var bindingData=chosen.Get("binding").As<Resource>();
        int index=System.Array.IndexOf(bindingData.Get("bone_ids").AsStringArray(),armature.Get("bones").AsGodotArray()[editor.selected_bone].AsGodotDictionary()["id"].AsString());if(index<0) return;
        _weighting.paint_region(chosen,geometry(chosen,armature,false,stroking,cache,strokeCache),index,transform,hitPoint,rayOrigin,best,state.Get("brush_radius").AsDouble(),state.Get("brush_strength").AsDouble(),state.Get("brush_value").AsDouble(),state.Get("brush_mode").AsString(),subtract,state.Get("paint_hidden").AsBool(),state.Get("selected_only").AsBool(),state.Get("region").AsGodotDictionary(),state.Get("weight_before").AsGodotDictionary(),state.Get("weight_after").AsGodotDictionary(),state.Get("touched").AsGodotDictionary());
        session.EmitSignal("changed");
    }
    public void select_region(Control canvas,RigEditor editor,RefCounted state,Rect2 rect,bool additive)
    {
        var region=state.Get("region").AsGodotDictionary();if(!additive) region.Clear();var armature=editor.rig();if(armature==null) return;
        var document=canvas.Get("session").As<RefCounted>().Get("document").As<Resource>();var transform=document.Call("world_transform",armature).AsTransform3D();var inverse=transform.AffineInverse();bool click=rect.Size.Length()<5;string rigId=armature.Get("id").AsString();var camera=canvas.Get("camera").As<Camera3D>();
        foreach(var item in editor.meshes())
        {
            var binding=item.Get("binding").As<Resource>();if(binding==null||binding.Get("rigid_bone_id").AsString().Length>0||item.Get("skeleton_id").AsString()!=rigId) continue;
            var data=geometry(item,armature,state.Get("compare_rest").AsBool(),state.Get("drag").AsString()=="weight",state.Get("geometry_cache").AsGodotDictionary(),state.Get("stroke_geometry").AsGodotDictionary());string id=item.Get("id").AsString();
            if(state.Get("weight_tool").AsString()=="Select faces"&&click)
            {
                var ray=canvas.Call("ray",rect.Position).AsGodotDictionary();var hit=data["mesh"].As<TriangleMesh>().IntersectRay(inverse*ray["origin"].AsVector3(),(inverse.Basis*ray["direction"].AsVector3()).Normalized());
                if(hit.Count==0||!hit.ContainsKey("face_index")) continue;var face=data["faces"].AsGodotArray()[hit["face_index"].AsInt32()].AsGodotDictionary();int surface=face["surface"].AsInt32();
                foreach(int vertex in face["vertices"].AsInt32Array()) region[id+":"+surface+":"+vertex]=new Settings{["id"]=id,["surface"]=surface,["vertex"]=vertex};
                continue;
            }
            var surfaces=data["points"].AsGodotArray();
            for(int surface=0;surface<surfaces.Count;surface++)
            {
                var points=surfaces[surface].AsVector3Array();
                for(int vertex=0;vertex<points.Length;vertex++)
                {
                    Vector3 point=transform*points[vertex];if(camera.IsPositionBehind(point)) continue;Vector2 projected=canvas.Call("project",point).AsVector2();
                    if(click?projected.DistanceTo(rect.Position)<10:rect.HasPoint(projected)) region[id+":"+surface+":"+vertex]=new Settings{["id"]=id,["surface"]=surface,["vertex"]=vertex};
                }
            }
        }
        canvas.Get("overlay").As<Control>().QueueRedraw();
    }
    public Settings geometry(Resource item,Resource armature,bool compareRest,bool stroking,Settings cache,Settings strokeCache)
    {
        string id=item.Get("id").AsString(); if(stroking&&strokeCache.TryGetValue(id,out var frozen)) return frozen.AsGodotDictionary();
        var binding=item.Get("binding").As<Resource>(); var boneValues=new GArray();
        foreach(Variant value in armature.Get("bones").AsGodotArray()) {var bone=value.AsGodotDictionary();boneValues.Add(new GArray{bone["rest"],bone["position"],bone["rotation"],bone["scale"]});}
        long key=GD.Hash(new GArray{binding,binding.Get("revision"),compareRest,boneValues});
        if(cache.TryGetValue(id,out var cached)&&cached.AsGodotDictionary()["key"].AsInt64()==key)
        {if(stroking) strokeCache[id]=cached;return cached.AsGodotDictionary();}
        var surfaces=new Godot.Collections.Array<Vector3[]>();var triangles=new List<Vector3>();var faces=new Godot.Collections.Array<Settings>();
        var mesh=binding.Get("source_mesh").As<Mesh>();var transform=binding.Get("mesh_to_rig").AsTransform3D();
        for(int surface=0;surface<mesh.GetSurfaceCount();surface++)
        {
            var arrays=mesh.SurfaceGetArrays(surface);Vector3[] points;
            if(compareRest) {points=arrays[(int)Mesh.ArrayType.Vertex].AsVector3Array();for(int i=0;i<points.Length;i++) points[i]=transform*points[i];}
            else points=_geometry.deformed_points(binding,armature,surface);
            surfaces.Add(points); int[] ids=arrays[(int)Mesh.ArrayType.Index].VariantType==Variant.Type.Nil?System.Array.Empty<int>():arrays[(int)Mesh.ArrayType.Index].AsInt32Array();
            int count=ids.Length>0?ids.Length:points.Length;
            for(int i=0;i<count;i++) triangles.Add(points[ids.Length>0?ids[i]:i]);
            for(int i=0;i+2<count;i+=3) faces.Add(new Settings{["surface"]=surface,["vertices"]=ids.Length>0?new[]{ids[i],ids[i+1],ids[i+2]}:new[]{i,i+1,i+2}});
        }
        var triangleMesh=new TriangleMesh();triangleMesh.CreateFromFaces(triangles.ToArray());
        var result=new Settings{["key"]=key,["points"]=surfaces,["mesh"]=triangleMesh,["faces"]=faces};cache[id]=result;if(stroking) strokeCache[id]=result;return result;
    }
}
