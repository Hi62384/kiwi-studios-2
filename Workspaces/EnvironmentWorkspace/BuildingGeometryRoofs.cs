using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using Topology=ModelGeometryOperations.Topology;

public partial class BuildingGeometryOperations
{
    internal static Topology? Roof(Resource source,List<string> warnings)
    {
        var footprint=source.Get("footprint").AsVector2Array();int kind=source.Get("roof_type").AsInt32();if(kind==0)return ModelPrimitives.Prism(footprint,source.Get("slab_thickness").AsDouble(),0,1);var bounds=new Rect2(footprint[0],Vector2.Zero);foreach(var point in footprint)bounds=bounds.Expand(point);
        if(footprint.Length!=4){warnings.Add("Sloped roofs currently require a rectangular footprint. Use a flat roof for this plan.");return null;}
        foreach(var point in footprint)if(!(Mathf.IsEqualApprox(point.X,bounds.Position.X)||Mathf.IsEqualApprox(point.X,bounds.End.X))||!(Mathf.IsEqualApprox(point.Y,bounds.Position.Y)||Mathf.IsEqualApprox(point.Y,bounds.End.Y))){warnings.Add("Sloped roofs require an axis-aligned rectangular plan.");return null;}
        double width=bounds.Size.X+source.Get("roof_overhang").AsDouble()*2,depth=bounds.Size.Y+source.Get("roof_overhang").AsDouble()*2,rise=Math.Tan(Mathf.DegToRad(Math.Clamp(source.Get("roof_pitch").AsDouble(),1,75)))*(kind==3?Math.Min(width,depth):width)*.5;var mesh=new Topology();
        if(kind is 1 or 2)
        {
            var profile=kind==1?new[]{new Vector2((float)(-width*.5),0),new Vector2((float)(width*.5),0),new Vector2(0,(float)rise)}:new[]{new Vector2((float)(-width*.5),0),new Vector2((float)(width*.5),0),new Vector2((float)(width*.5),(float)rise)};mesh=ModelPrimitives.Prism(profile,depth,0,1);Swizzle(mesh);
        }
        else
        {
            mesh.Points.AddRange(new[]{new Vector3((float)(-width*.5),0,(float)(-depth*.5)),new Vector3((float)(width*.5),0,(float)(-depth*.5)),new Vector3((float)(width*.5),0,(float)(depth*.5)),new Vector3((float)(-width*.5),0,(float)(depth*.5))});int[][] faces;
            if(Mathf.IsEqualApprox(width,depth)){mesh.Points.Add(new Vector3(0,(float)rise,0));faces=new[]{new[]{0,1,4},new[]{1,2,4},new[]{2,3,4},new[]{3,0,4},new[]{3,2,1,0}};}
            else if(depth>width){mesh.Points.Add(new Vector3(0,(float)rise,(float)(-(depth-width)*.5)));mesh.Points.Add(new Vector3(0,(float)rise,(float)((depth-width)*.5)));faces=new[]{new[]{0,1,4},new[]{1,2,5,4},new[]{2,3,5},new[]{3,0,4,5},new[]{3,2,1,0}};}
            else{mesh.Points.Add(new Vector3((float)(-(width-depth)*.5),(float)rise,0));mesh.Points.Add(new Vector3((float)((width-depth)*.5),(float)rise,0));faces=new[]{new[]{0,1,5,4},new[]{1,2,5},new[]{2,3,4,5},new[]{3,0,4},new[]{3,2,1,0}};}
            foreach(var face in faces)mesh.AddFace(face);foreach(int index in Enumerable.Range(0,mesh.Faces.Count)){var face=mesh.Faces[index];var center=Vector3.Zero;foreach(int id in face)center+=mesh.Points[id];center/=face.Length;if(ModelGeometryOperations.Normal(mesh.Points,face).Dot(center-new Vector3(0,(float)(rise*.3),0))<0){Array.Reverse(face);Array.Reverse(mesh.Uv[index]);}}
        }
        var origin=bounds.GetCenter();for(int index=0;index<mesh.Points.Count;index++)mesh.Points[index]+=new Vector3(origin.X,0,origin.Y);return mesh;
    }
    public Settings roof_mesh(Resource source)
    {var warnings=new List<string>();var mesh=Roof(source,warnings);return new Settings {["mesh"]=mesh!=null?Variant.From(mesh.Build()):default,["warnings"]=warnings.ToArray()};}
}
