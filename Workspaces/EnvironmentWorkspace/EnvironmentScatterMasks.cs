using Godot;
using System;
using System.Collections.Generic;
using System.Linq;

public partial class EnvironmentScatterOperations
{
    private sealed class Masks
    {
        private readonly Dictionary<Vector2I,List<Vector2[]>> _cells=new();
        private readonly List<Vector2[]> _large=new();
        private readonly double _margin;
        internal readonly Vector2[][] Included;
        internal Masks(Resource owner)
        {
            _margin=owner.Get("exclusion_margin").AsDouble();Included=owner.Get("include_polygons").AsGodotArray().Select(value=>value.AsVector2Array()).ToArray();
            foreach(var value in owner.Get("exclude_polygons").AsGodotArray())
            {
                var polygon=value.AsVector2Array();if(polygon.Length<3)continue;var bounds=new Rect2(polygon[0],Vector2.Zero);foreach(var point in polygon)bounds=bounds.Expand(point);bounds=bounds.Grow((float)(_margin+.001));var low=(Vector2I)(bounds.Position/16).Floor();var high=(Vector2I)(bounds.End/16).Floor();
                if((high.X-low.X+1)*(high.Y-low.Y+1)>256){_large.Add(polygon);continue;}for(int y=low.Y;y<=high.Y;y++)for(int x=low.X;x<=high.X;x++){var key=new Vector2I(x,y);if(!_cells.TryGetValue(key,out var list))_cells[key]=list=new();list.Add(polygon);}
            }
        }
        internal bool Excluded(Vector2 point)
        {
            var values=_cells.TryGetValue((Vector2I)(point/16).Floor(),out var list)?list.Concat(_large):_large;
            foreach(var polygon in values){if(Geometry2D.IsPointInPolygon(point,polygon))return true;for(int edge=0;edge<polygon.Length;edge++)if(point.DistanceTo(Geometry2D.GetClosestPointToSegment(point,polygon[edge],polygon[(edge+1)%polygon.Length]))<=_margin)return true;}return false;
        }
    }
}
