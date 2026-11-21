using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;
using Topology=ModelGeometryOperations.Topology;

public partial class BuildingGeometryOperations : RefCounted
{
    private readonly BuildingMeshCache _cache=new();
    private readonly BuildingSourceOperations _source=new();
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private static Topology Top(Resource mesh)=>new(new ModelMeshOperations.Snapshot(mesh));
    private static void Assign(Resource mesh,Topology data)
    {mesh.Set("vertices",data.Points.ToArray());mesh.Set("faces",new Godot.Collections.Array<int[]>(data.Faces));mesh.Set("uv",new Godot.Collections.Array<Vector2[]>(data.Uv));mesh.Set("materials",data.Materials.ToArray());mesh.Set("smooth",data.Smooth);}
    private static void Swizzle(Topology mesh)
    {for(int index=0;index<mesh.Points.Count;index++){var p=mesh.Points[index];mesh.Points[index]=new Vector3(p.X,p.Z,p.Y);}for(int index=0;index<mesh.Faces.Count;index++){Array.Reverse(mesh.Faces[index]);Array.Reverse(mesh.Uv[index]);}}
    public long mesh_key(Resource? mesh,int format)=>mesh==null?0:unchecked((uint)GD.Hash(format>=2?new GArray {mesh.Get("vertices"),mesh.Get("faces"),mesh.Get("uv"),mesh.Get("materials")}:new GArray {mesh.Get("vertices"),mesh.Get("faces")}));
    public double opening_top(Settings opening,double x,double length)
    {
        double height=Get(opening,"height",2.0).AsDouble(),top=Get(opening,"bottom",0.0).AsDouble()+height;if(Get(opening,"type", "").AsString()!="arch")return top;double width=Get(opening,"width",1.0).AsDouble(),rise=Math.Min(width*.5,height*.4),t=(x-Get(opening,"t",.5).AsDouble()*length)/Math.Max(.001,width*.5);return top-rise+rise*Math.Sqrt(Math.Max(0,1-t*t));
    }
    private static void Panel(Topology target,double left,double right,Vector2 bottom,Vector2 top,double thickness)
    {var profile=new[]{new Vector2((float)left,bottom.X),new Vector2((float)right,bottom.Y),new Vector2((float)right,top.Y),new Vector2((float)left,top.X)};var panel=ModelPrimitives.Prism(profile,thickness,0,1);Swizzle(panel);target.Append(panel,Transform3D.Identity);}
    public void panel(Resource target,double left,double right,Vector2 bottom,Vector2 top,double thickness){var data=Top(target);Panel(data,left,right,bottom,top,thickness);Assign(target,data);}
    private Topology Wall(double length,double height,double thickness,GArray openings)
    {
        var mesh=new Topology();var xs=new List<double>{0,length};foreach(var value in openings){var opening=value.AsGodotDictionary();double width=Get(opening,"width",1.0).AsDouble(),center=Get(opening,"t",.5).AsDouble()*length;bool arch=Get(opening,"type", "").AsString()=="arch";for(int step=0;step<(arch?13:2);step++)xs.Add(center-width*.5+width*step/(arch?12.0:1));}
        xs.Sort();var unique=new List<double>();foreach(double x in xs)if(unique.Count==0||Math.Abs(unique[^1]-x)>.00001)unique.Add(x);
        for(int index=0;index<unique.Count-1;index++)
        {
            double left=unique[index],right=unique[index+1],middle=(left+right)*.5;var intervals=new List<(double Bottom,Vector2 Top)>();foreach(var value in openings){var opening=value.AsGodotDictionary();double center=Get(opening,"t",.5).AsDouble()*length,width=Get(opening,"width",1.0).AsDouble();if(Math.Abs(middle-center)>width*.5+.00001)continue;intervals.Add((Get(opening,"bottom",0.0).AsDouble(),new Vector2((float)opening_top(opening,left,length),(float)opening_top(opening,right,length))));}
            var bottom=Vector2.Zero;foreach(var hole in intervals.OrderBy(value=>value.Bottom)){if(hole.Bottom>Math.Max(bottom.X,bottom.Y)+.00001)Panel(mesh,left,right,bottom,Vector2.One*(float)hole.Bottom,thickness);bottom=bottom.Max(hole.Top);}if(Math.Min(bottom.X,bottom.Y)<height-.00001)Panel(mesh,left,right,bottom,Vector2.One*(float)height,thickness);
        }
        return mesh;
    }
    public Resource wall_mesh(double length,double height,double thickness,GArray openings)=>Wall(length,height,thickness,openings).Build();
    private static Topology ConvexSlab(Vector2[] polygon,double thickness)
    {var mesh=new Topology();var triangles=Geometry2D.TriangulatePolygon(polygon);for(int index=0;index<triangles.Length;index+=3)mesh.Append(ModelPrimitives.Prism(new[]{polygon[triangles[index]],polygon[triangles[index+1]],polygon[triangles[index+2]]},thickness,0,1),Transform3D.Identity);return mesh;}
    public Resource convex_slab(Vector2[] polygon,double thickness)=>ConvexSlab(polygon,thickness).Build();
    private static Topology Slab(Vector2[] footprint,GArray cuts,double thickness)
    {
        if(cuts.Count==0)return ConvexSlab(footprint,thickness);var xs=new List<double>();var zs=new List<double>();var mesh=new Topology();foreach(var p in footprint){xs.Add(p.X);zs.Add(p.Y);}foreach(var cut in cuts)if(cut.VariantType==Variant.Type.Rect2){var rect=cut.AsRect2();xs.Add(rect.Position.X);xs.Add(rect.End.X);zs.Add(rect.Position.Y);zs.Add(rect.End.Y);}xs.Sort();zs.Sort();
        for(int x=0;x<xs.Count-1;x++)for(int z=0;z<zs.Count-1;z++)
        {
            if(xs[x+1]-xs[x]<.00001||zs[z+1]-zs[z]<.00001)continue;var center=new Vector2((float)((xs[x]+xs[x+1])*.5),(float)((zs[z]+zs[z+1])*.5));bool remove=false;foreach(var cut in cuts)if(cut.VariantType==Variant.Type.Rect2&&cut.AsRect2().HasPoint(center)){remove=true;break;}if(remove)continue;
            var cell=new[]{new Vector2((float)xs[x],(float)zs[z]),new Vector2((float)xs[x+1],(float)zs[z]),new Vector2((float)xs[x+1],(float)zs[z+1]),new Vector2((float)xs[x],(float)zs[z+1])};foreach(var polygon in Geometry2D.IntersectPolygons(footprint,cell))if(polygon.Length>=3&&Geometry2D.TriangulatePolygon(polygon).Length>0)mesh.Append(ConvexSlab(polygon,thickness),Transform3D.Identity);
        }
        return mesh;
    }
    public Resource slab(Vector2[] footprint,GArray cuts,double thickness)=>Slab(footprint,cuts,thickness).Build();
    public Resource cached_slab(Vector2[] footprint,GArray cuts,double thickness)=>_cache.GetOrBuild("slab",new GArray {footprint,cuts,thickness},()=>Slab(footprint,cuts,thickness).Build())!;
}
