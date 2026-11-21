using Godot;
using System;
using System.Linq;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;
using Topology=ModelGeometryOperations.Topology;

public partial class RoadSectionOperations
{
    private sealed record Corner(Vector3 Point,Vector3 Out,int End,Settings Road);
    public Settings junction_details(GArray ends)
    {
        var parts=new Dictionary<string,Topology>(StringComparer.Ordinal);var profile=new List<Vector2>();var vertices=new Dictionary<Vector2,Corner>();for(int index=0;index<ends.Count;index++){var end=ends[index].AsGodotDictionary();var point=end["point"].AsVector3();var direction=end["direction"].AsVector3();var side=new Vector3(-direction.Z,0,direction.X).Normalized();foreach(float sign in new[]{-1f,1f}){var position=point+side*end["width"].AsSingle()*.5f*sign;var key=new Vector2(position.X,position.Z);profile.Add(key);vertices[key]=new Corner(position,side*sign,index,Get(end,"road",new Settings()).AsGodotDictionary());}}
        profile=new List<Vector2>(Geometry2D.ConvexHull(profile.ToArray()));if(profile.Count>1&&profile[0].IsEqualApprox(profile[^1]))profile.RemoveAt(profile.Count-1);for(int index=0;index<profile.Count;index++)
        {
            var a=vertices[profile[index]];var b=vertices[profile[(index+1)%profile.Count]];if(a.End==b.End)continue;double innerA=0,innerB=0;foreach(string part in new[]{"shoulders","curbs","sidewalks"})
            {
                (double Width,double Height) Dimensions(Settings road){bool enabled=Get(road,"section",false).AsBool()&&Get(road,"mode","Ground").AsString()=="Ground";double curb=enabled?F(road,"curb_height"):0;if(!enabled)return(0,0);double width=part=="shoulders"?F(road,"shoulder"):part=="curbs"&&curb>0?F(road,"curb_width",.14):part=="sidewalks"?F(road,"sidewalk"):0;return(width,part!="shoulders"?curb:0);}
                var first=Dimensions(a.Road);var last=Dimensions(b.Road);if(first.Width>0||last.Width>0)
                {
                    var points=new[]{a.Point+a.Out*(float)innerA+Vector3.Up*(float)first.Height,b.Point+b.Out*(float)innerB+Vector3.Up*(float)last.Height,b.Point+b.Out*(float)(innerB+last.Width)+Vector3.Up*(float)last.Height,a.Point+a.Out*(float)(innerA+first.Width)+Vector3.Up*(float)first.Height};var mesh=new Topology();foreach(var point in points)if(mesh.Points.Count==0||!mesh.Points[^1].IsEqualApprox(point))mesh.Points.Add(point);if(mesh.Points.Count>2&&mesh.Points[0].IsEqualApprox(mesh.Points[^1]))mesh.Points.RemoveAt(mesh.Points.Count-1);if(mesh.Points.Count>=3){mesh.AddFace(Enumerable.Range(0,mesh.Points.Count).ToArray());if(ModelGeometryOperations.Normal(mesh.Points,mesh.Faces[0]).Y<0){Array.Reverse(mesh.Faces[0]);Array.Reverse(mesh.Uv[0]);}if(ModelGeometryOperations.Normal(mesh.Points,mesh.Faces[0]).Y>.01)Append(parts,part,Solid(mesh,.12+Math.Max(first.Height,last.Height)));}
                }
                innerA+=first.Width;innerB+=last.Width;
            }
        }
        return BuildParts(parts,false);
    }
}
