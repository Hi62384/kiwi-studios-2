using Godot;
using System;
internal readonly struct ImageLayerProjection
{
    public Vector2 Dimensions{get;}
    private readonly double _cosX,_cosY,_sinX,_sinY;
    private readonly Vector2 _depth;private readonly float _fit;
    public ImageLayerProjection(Resource layer)
    {
        Dimensions=layer.Get("dimensions").AsVector2();var properties=layer.Get("properties").AsGodotDictionary();double x=Mathf.DegToRad(properties.TryGetValue("yaw_up_down",out var a)?a.AsDouble():0),y=Mathf.DegToRad(properties.TryGetValue("yaw_left_right",out var b)?b.AsDouble():0);_cosX=Math.Cos(x);_cosY=Math.Cos(y);_sinX=Math.Sin(x);_sinY=Math.Sin(y);_depth=new Vector2((float)-_sinY,(float)(_cosY*_sinX))*.5f;_fit=1+_depth.Abs().Dot(Vector2.One*.5f);
    }
    public Vector2 Project(Vector2 point,Vector2 extent)
    {
        if(extent.X<0)extent=Dimensions;var p=point/extent-Vector2.One*.5f;var q=new Vector2((float)(_cosY*p.X+_sinY*_sinX*p.Y),(float)(_cosX*p.Y));return(q/(1+_depth.Dot(p))/_fit+Vector2.One*.5f)*extent;
    }
    public Vector2 Unproject(Vector2 point)
    {
        var q=(point/Dimensions-Vector2.One*.5f)*_fit;var solve=new Transform2D(new Vector2((float)_cosY,0)-q*_depth.X,new Vector2((float)(_sinY*_sinX),(float)_cosX)-q*_depth.Y,Vector2.Zero);return(solve.AffineInverse()*q+Vector2.One*.5f)*Dimensions;
    }
}
public partial class ImageSelectionMapping:RefCounted
{
    private readonly ImageLayerProjection _old,_current;private readonly Transform2D _from,_to,_fromInverse,_toInverse;
    public ImageSelectionMapping(Resource oldLayer,Resource current,Transform2D from,Transform2D to){_old=new(oldLayer);_current=new(current);_from=from;_to=to;_fromInverse=from.AffineInverse();_toInverse=to.AffineInverse();}
    public Vector2 forward(Vector2 point){var local=_old.Unproject(_fromInverse*point);return _to*_current.Project(local/_old.Dimensions.Max(Vector2.One)*_current.Dimensions,new Vector2(-1,-1));}
    public Vector2 inverse(Vector2 point){var local=_current.Unproject(_toInverse*point);return _from*_old.Project(local/_current.Dimensions.Max(Vector2.One)*_old.Dimensions,new Vector2(-1,-1));}
}
