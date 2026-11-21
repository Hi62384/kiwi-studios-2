using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;

public partial class TerrainHydrologyOperations
{
    private static List<Vector3> Clip(Vector3[] polygon,double level)
    {
        var result=new List<Vector3>();for(int index=0;index<polygon.Length;index++){var a=polygon[index];var b=polygon[(index+1)%polygon.Length];bool insideA=a.Y<level,insideB=b.Y<level;if(insideA)result.Add(a);if(insideA!=insideB)result.Add(a.Lerp(b,(float)Math.Clamp((level-a.Y)/((double)b.Y-a.Y),0,1)));}
        var cleaned=new List<Vector3>();foreach(var point in result)if(cleaned.Count==0||cleaned[^1].DistanceSquaredTo(point)>.000000001)cleaned.Add(point);if(cleaned.Count>1&&cleaned[0].DistanceSquaredTo(cleaned[^1])<.000000001)cleaned.RemoveAt(cleaned.Count-1);return cleaned;
    }
    public Vector3[] clip(Vector3[] polygon,double level)=>Clip(polygon,level).ToArray();
    private sealed partial class Context
    {
        private bool MeshBudget()
        {if(Vertices.Count<=Math.Max(1,I("mesh_vertex_budget")))return false;MeshError="Water mesh vertex budget exceeded. Reduce path density or terrain water resolution.";return true;}
        internal void BuildWater(List<Settings> paths,float[] ground,float[] levels,byte[] kinds)
        {
            Vertices.Clear();Normals.Clear();Uv.Clear();Uv2.Clear();Colors.Clear();Indices.Clear();MeshError="";
            foreach(var path in paths)
            {
                var points=path["points"].AsVector3Array();var widths=path["widths"].AsFloat32Array();double distance=0;
                for(int index=0;index<points.Length-1;index++)
                {
                    if(Cancelled()||MeshBudget())return;var a=points[index];var b=points[index+1];int ca=Cell(new Vector2(a.X,a.Z)),cb=Cell(new Vector2(b.X,b.Z));var tangent=b-a;var side=new Vector3(tangent.Z,0,-tangent.X).Normalized();if(side.LengthSquared()<.5)continue;
                    if(kinds[ca]!=0&&kinds[cb]!=0&&Math.Abs((double)a.Y-levels[ca])<.05&&Math.Abs((double)b.Y-levels[cb])<.05){distance+=tangent.Length();continue;}
                    var normal=tangent.Cross(side).Normalized();var direction=new Vector2(tangent.X,tangent.Z).Normalized();double foam=Math.Clamp(((double)a.Y-b.Y)/Math.Max(.1,new Vector2(tangent.X,tangent.Z).Length())*.3,0,1);int start=Vertices.Count;
                    for(int corner=0;corner<6;corner++)
                    {
                        var center=corner<3?a:b;float width=corner<3?widths[index]:widths[index+1];double across=(corner%3)*.5;var point=center+side*width*(float)(across-.5);double depth=Math.Max(0,point.Y-Sample(ground,new Vector2(point.X,point.Z)));
                        Vertices.Add(point);Normals.Add(normal);Uv.Add(new Vector2((float)across,(float)(distance+(corner<3?0:tangent.Length()))));Uv2.Add(direction);Colors.Add(new Color((float)foam,(float)Math.Clamp(depth/20,0,1),1,1));
                    }
                    Indices.AddRange(new[]{start,start+1,start+3,start+1,start+4,start+3,start+1,start+2,start+4,start+2,start+5,start+4});distance+=tangent.Length();
                }
            }
            var wave=Parameters["wave_direction"].AsVector2().Normalized();
            for(int z=0;z<N-1;z++)
            {
                if(Cancelled()||MeshBudget())return;
                for(int x=0;x<N-1;x++)
                {
                    int a=x+z*N,b=a+1,c=a+N,d=c+1;
                    foreach(var triangle in new[]{new[]{a,b,c},new[]{b,d,c}})
                    {
                        double level=Dry;foreach(int index in triangle)if(kinds[index]!=0)level=Math.Max(level,levels[index]);if(level<=Dry*.5)continue;
                        var polygon=new Vector3[3];for(int i=0;i<3;i++){var point=Point(triangle[i]);point.Y=ground[triangle[i]];polygon[i]=point;}var clipped=Clip(polygon,level);if(clipped.Count<3)continue;int start=Vertices.Count;
                        foreach(var original in clipped){var point=original;double depth=Math.Max(0,level-point.Y);point.Y=(float)level;Vertices.Add(point);Normals.Add(Vector3.Up);Uv.Add(new Vector2(point.X,point.Z));Uv2.Add(wave);Colors.Add(new Color(0,(float)Math.Clamp(depth/20,0,1),0,1));}
                        for(int index=1;index<clipped.Count-1;index++){Indices.Add(start);Indices.Add(start+index);Indices.Add(start+index+1);}
                    }
                }
            }
        }
    }
}
