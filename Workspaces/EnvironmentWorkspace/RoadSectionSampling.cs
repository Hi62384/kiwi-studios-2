using Godot;
using System.Collections.Generic;

public partial class RoadSectionOperations
{
    // Tiny spline overshoot near a snapped junction can invert the
    // solidified side wall. Keep the exact ends and discard tiny interior spans.
    internal static Vector3[] StableSectionSamples(Vector3[] points)
    {
        if(points.Length<3)return points;
        const float minimumSquared=.05f*.05f;
        float HorizontalSquared(Vector3 a,Vector3 b)=>new Vector2(a.X-b.X,a.Z-b.Z).LengthSquared();
        var result=new List<Vector3>{points[0]};
        for(int i=1;i<points.Length-1;i++)
            if(HorizontalSquared(points[i],result[^1])>=minimumSquared)result.Add(points[i]);
        while(result.Count>1&&HorizontalSquared(result[^1],points[^1])<minimumSquared)result.RemoveAt(result.Count-1);
        result.Add(points[^1]);return result.ToArray();
    }
}
