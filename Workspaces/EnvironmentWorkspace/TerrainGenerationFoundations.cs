using Godot;
using System;
using Settings=Godot.Collections.Dictionary;

public partial class TerrainGenerationOperations
{
    public float[] apply_foundations(Resource owner,float[] heights,int resolution,Vector2 dimensions,Settings cancellation)
    {
        var result=(float[])heights.Clone();var edits=owner.Get("foundation_edits").AsFloat32Array();int editResolution=(int)Math.Floor(Math.Sqrt(edits.Length));
        bool canCancel=Get(cancellation,"enabled",false).AsBool();
        foreach(var entry in owner.Get("layers").AsGodotArray())
        {
            var layer=entry.AsGodotDictionary();if(Get(layer,"type", "").AsString()!="Foundation"||!Get(layer,"enabled",true).AsBool())continue;
            var polygon=Get(layer,"polygon",Array.Empty<Vector2>()).AsVector2Array();var plane=Get(layer,"plane",new Plane(Vector3.Up,0)).AsPlane();double feather=Math.Max(0,Number(layer,"feather",1));
            if(polygon.Length<3||Math.Abs(plane.Normal.Y)<.2)continue;
            var bounds=new Rect2(polygon[0],Vector2.Zero);foreach(var point in polygon)bounds=bounds.Expand(point);bounds=bounds.Grow((float)feather);
            var begin=((bounds.Position/dimensions+Vector2.One*.5f)*(resolution-1)).Floor();var finish=((bounds.End/dimensions+Vector2.One*.5f)*(resolution-1)).Ceil();
            int startX=Math.Max(0,(int)begin.X),startZ=Math.Max(0,(int)begin.Y),endX=Math.Min(resolution-1,(int)finish.X),endZ=Math.Min(resolution-1,(int)finish.Y);
            for(int z=startZ;z<=endZ;z++)
            {
                if(canCancel&&GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/terrain/terrain_erosion.gd").Call("_cancel_requested",cancellation).AsBool())return Array.Empty<float>();
                for(int x=startX;x<=endX;x++)
                {
                    var point=new Vector2((float)((double)x/(resolution-1)-.5),(float)((double)z/(resolution-1)-.5))*dimensions;bool inside=Geometry2D.IsPointInPolygon(point,polygon);double distance=double.PositiveInfinity;
                    if(!inside)for(int edge=0;edge<polygon.Length;edge++)distance=Math.Min(distance,point.DistanceTo(Geometry2D.GetClosestPointToSegment(point,polygon[edge],polygon[(edge+1)%polygon.Length])));
                    double weight=inside?1:feather>.0001?1-Smooth(0,feather,distance):0;if(weight<=0)continue;
                    int index=x+z*resolution;double target=(plane.D-plane.Normal.X*point.X-plane.Normal.Z*point.Y)/plane.Normal.Y;
                    if(Get(layer,"surface_target",false).AsBool()&&editResolution>1&&editResolution*editResolution==edits.Length)
                    {
                        var p=new Vector2(x,z)/(resolution-1)*(editResolution-1);var cell=new Vector2I(Math.Min((int)Math.Floor(p.X),editResolution-2),Math.Min((int)Math.Floor(p.Y),editResolution-2));var f=p-(Vector2)cell;
                        target-=Mathf.Lerp(Mathf.Lerp(edits[cell.X+cell.Y*editResolution],edits[cell.X+1+cell.Y*editResolution],f.X),Mathf.Lerp(edits[cell.X+(cell.Y+1)*editResolution],edits[cell.X+1+(cell.Y+1)*editResolution],f.X),f.Y);
                    }
                    result[index]=(float)Mathf.Lerp(result[index],target,weight);
                }
            }
        }
        return result;
    }
}
