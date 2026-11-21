using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;
using Topology=ModelGeometryOperations.Topology;

public partial class BuildingStyleOperations : RefCounted
{
    private readonly BuildingSourceOperations _source=new();
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private static void Box(Topology mesh,Vector3 size,Vector3 position)=>mesh.Append(ModelPrimitives.Box(size),new Transform3D(Basis.Identity,position));
    private static void Beam(Topology mesh,Vector3 a,Vector3 b,float width)
    {var direction=b-a;if(direction.Length()<.001)return;mesh.Append(ModelPrimitives.Box(new Vector3(width,width,direction.Length())),new Transform3D(Basis.LookingAt(-direction.Normalized(),Vector3.Forward),(a+b)*.5f));}
    public Resource facade(Resource source,Settings floor,Settings wall)
    {
        var mesh=new Topology();int kind=source.Get("facade_detail").AsInt32();if(kind==0)return mesh.Build();var a=wall["a"].AsVector2();var b=wall["b"].AsVector2();float height=(float)_source.wall_height(source,floor,wall),length=a.DistanceTo(b),width=Math.Clamp((float)source.Get("detail_width").AsDouble(),.04f,.5f);var direction=(b-a).Normalized();var normal=new Vector2(-direction.Y,direction.X);var polygon=Get(floor,"footprint",source.Get("footprint")).AsVector2Array();bool plus=Geometry2D.IsPointInPolygon((a+b)*.5f+normal*.05f,polygon),minus=Geometry2D.IsPointInPolygon((a+b)*.5f-normal*.05f,polygon);if(plus==minus)return mesh.Build();float sign=plus?-1:1,z=((float)source.Get("wall_thickness").AsDouble()*.5f+width*.5f)*sign;var openings=Get(wall,"openings",new GArray()).AsGodotArray();
        if(kind is 1 or 3 or 4 or 5 or 6 or 7){foreach(float x in new[]{0f,length})Box(mesh,new Vector3(width,height,kind==3?width*4:width),new Vector3(x,height*.5f,z));Box(mesh,new Vector3(length+width,width,width),new Vector3(length*.5f,height-width*.5f,z));}
        if(kind is 1 or 6)
        {
            var spans=new List<Vector2>();float cursor=0;foreach(var opening in openings.Select(v=>v.AsGodotDictionary()).OrderBy(o=>Get(o,"t",.5).AsDouble())){float center=(float)Get(opening,"t",.5).AsDouble()*length,radius=(float)Get(opening,"width",1.0).AsDouble()*.5f+width;if(center-radius>cursor)spans.Add(new Vector2(cursor,center-radius));cursor=Math.Max(cursor,center+radius);}if(cursor<length)spans.Add(new Vector2(cursor,length));
            foreach(var span in spans){if(span.Y-span.X<.35)continue;Beam(mesh,new Vector3(span.X,width,z),new Vector3(span.Y,height-width,z),width);if(kind==6)Beam(mesh,new Vector3(span.Y,width,z),new Vector3(span.X,height-width,z),width);}
        }
        else if(kind==2)
        {
            foreach(var value in openings){var opening=value.AsGodotDictionary();if(Get(opening,"type", "").AsString() is not ("door" or "slider" or "arch"))continue;float x=(float)Get(opening,"t",.5).AsDouble()*length,extent=(float)Get(opening,"width",1.0).AsDouble()*.5f+.4f;foreach(float side in new[]{-1f,1f})Box(mesh,new Vector3(width,height-.2f,width),new Vector3(x+side*extent,(height-.2f)*.5f,z+sign*.9f));Box(mesh,new Vector3(extent*2+width,.12f,1.2f),new Vector3(x,height-.14f,z+sign*.45f));}
        }
        else if(kind==5)
        {
            int count=Math.Max(1,(int)(length/.5));for(int index=0;index<count;index++){float x=(index+.5f)*length/count;bool blocked=false;foreach(var value in openings){var opening=value.AsGodotDictionary();blocked|=Math.Abs(x-Get(opening,"t",.5).AsDouble()*length)<Get(opening,"width",1.0).AsDouble()*.5+width;}if(!blocked)Box(mesh,new Vector3(width*.5f,height,width*3),new Vector3(x,height*.5f,z));}
        }
        else if(kind==7)
        {
            using var primitives=new ModelPrimitives();foreach(float x in new[]{0f,length}){using var cone=primitives.create("Cone",new Settings {["radius"]=width*3,["height"]=.9,["segments"]=8});mesh.Append(new Topology(new ModelMeshOperations.Snapshot(cone)),new Transform3D(Basis.Identity,new Vector3(x,height+.45f,z)));}
        }
        return mesh.Build();
    }
    public void beam(Resource target,Vector3 a,Vector3 b,double width)
    {var mesh=new Topology(new ModelMeshOperations.Snapshot(target));Beam(mesh,a,b,(float)width);target.Set("vertices",mesh.Points.ToArray());target.Set("faces",new Godot.Collections.Array<int[]>(mesh.Faces));target.Set("uv",new Godot.Collections.Array<Vector2[]>(mesh.Uv));target.Set("materials",mesh.Materials.ToArray());}
    public Resource? apply(Resource authored,string name,Settings presets)
    {
        if(!presets.TryGetValue(name,out var preset))return null;var settings=preset.AsGodotArray();var source=_source.copy(authored);source.Set("style",name);source.Set("roof_type",settings[0]);source.Set("roof_pitch",settings[1]);source.Set("wall_thickness",settings[2]);source.Set("facade_detail",settings[3]);source.Set("detail_width",name=="Stylized/Cartoon"?.22:.12);var engine=GD.Load<GDScript>("res://scripts/materials/natural_material_engine.gd");var materials=source.Get("materials").AsGodotArray();while(materials.Count<5)materials.Add(default);materials[0]=engine.Call("create_spatial_material",engine.Call("defaults",settings[4]));materials[3]=engine.Call("create_spatial_material",engine.Call("defaults",settings[5]));bool modern=name is "Modern" or "Minimalist" or "Futuristic";
        foreach(var floorValue in source.Get("floors").AsGodotArray())
        {
            var floor=floorValue.AsGodotDictionary();foreach(var wallValue in floor["walls"].AsGodotArray())
            {
                var wall=wallValue.AsGodotDictionary();double length=wall["b"].AsVector2().DistanceTo(wall["a"].AsVector2()),height=_source.wall_height(source,floor,wall);
                foreach(var openingValue in Get(wall,"openings",new GArray()).AsGodotArray())
                {
                    var opening=openingValue.AsGodotDictionary();if(opening["id"].AsString().StartsWith("layout:door",StringComparison.Ordinal))continue;string type=Get(opening,"type", "").AsString();
                    if(type=="window")
                    {
                        double desired=modern?2.4:name is "Medieval" or "Gothic-Inspired"?1:1.4,t=Get(opening,"t",.5).AsDouble(),available=2*Math.Min(t,1-t)*length-.1;opening["width"]=Math.Min(Get(opening,"width",desired).AsDouble(),Math.Min(desired,Math.Max(.1,available)));double openingHeight=Math.Min(name is "Modern" or "Futuristic"?1.65:1.2,height-.4);opening["height"]=openingHeight;opening["bottom"]=Math.Max(.1,Math.Min(Get(opening,"bottom",1.0).AsDouble(),height-openingHeight-.1));
                    }
                    else if(name=="Gothic-Inspired")opening["type"]="arch";else if(modern&&type!="arch")opening["type"]="slider";
                }
            }
        }
        return source;
    }
}
