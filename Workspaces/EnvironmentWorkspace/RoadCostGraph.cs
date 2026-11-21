using Godot;
using System;

public partial class RoadCostGraph : AStar3D
{
    public double slope_weight {get;set;}=40;
    public override float _ComputeCost(long fromId,long toId)
    {var a=GetPointPosition(fromId);var b=GetPointPosition(toId);double horizontal=new Vector2(a.X,a.Z).DistanceTo(new Vector2(b.X,b.Z));return (float)(horizontal*(1+Math.Pow(Math.Abs(a.Y-b.Y)/Math.Max(.01,horizontal),2)*slope_weight));}
    public override float _EstimateCost(long fromId,long toId)
    {var a=GetPointPosition(fromId);var b=GetPointPosition(toId);return new Vector2(a.X,a.Z).DistanceTo(new Vector2(b.X,b.Z));}
}
