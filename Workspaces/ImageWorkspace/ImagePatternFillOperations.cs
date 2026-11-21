using Godot;
using System;
using GArray=Godot.Collections.Array;
using Settings=Godot.Collections.Dictionary;
public partial class ImagePatternFillOperations:RefCounted
{
    private static Variant Get(Settings d,string key,Variant fallback=default)=>d.TryGetValue(key,out var value)?value:fallback;
    public Color sample(Image source,Rect2I area,Vector2 point,Settings settings)
    {
        if(!area.HasArea())return Colors.Transparent;double scale=Math.Max(.01,Get(settings,"scale",1).AsDouble());var p=(point-Get(settings,"offset",Vector2.Zero).AsVector2()).Rotated(-Mathf.DegToRad((float)Get(settings,"rotation",0).AsDouble()))/(float)scale;double spacing=Math.Max(0,Get(settings,"spacing",0).AsDouble());var cellSize=(Vector2)area.Size*(float)(1+spacing);var cell=(Vector2I)(p/cellSize).Floor();var local=p-(Vector2)cell*cellSize;string layout=Get(settings,"layout","tiled").AsString();if(layout=="offset"&&Mathf.PosMod(cell.Y,2)==1){p.X+=cellSize.X*.5f;cell.X=Mathf.FloorToInt(p.X/cellSize.X);local=p-(Vector2)cell*cellSize;}using var random=new RandomNumberGenerator{Seed=unchecked((uint)GD.Hash(new GArray{cell,Get(settings,"seed",0)}))};if(random.Randf()>Get(settings,"density",1).AsDouble())return Colors.Transparent;if(layout=="scatter")local-=new Vector2(random.RandfRange(-.35f,.35f),random.RandfRange(-.35f,.35f))*cellSize;bool natural=Get(settings,"behavior","exact").AsString()=="natural";double variation=Get(settings,"variation",1).AsDouble();if(natural){float angle=Mathf.DegToRad((float)(random.RandfRange(-1,1)*Get(settings,"random_rotation",15).AsDouble()*variation));float factor=(float)Math.Max(.1,1+random.RandfRange(-1,1)*Get(settings,"random_scale",.15).AsDouble()*variation);local=(local-(Vector2)area.Size*.5f).Rotated(angle)/factor+(Vector2)area.Size*.5f;}if(local.X<0||local.Y<0||local.X>=area.Size.X||local.Y>=area.Size.Y)return Colors.Transparent;if(!ImageTextureSynthesisOperations.Inside((Vector2)area.Position+local,area,Get(settings,"sample_shape","rectangle").AsString(),Get(settings,"sample_points",Array.Empty<Vector2>()).AsVector2Array()))return Colors.Transparent;var color=source.GetPixelv(area.Position+(Vector2I)local);if(natural){float gain=(float)(1+random.RandfRange(-1,1)*Get(settings,"color_variation",.1).AsDouble()*variation);color.R*=gain;color.G*=gain;color.B*=gain;}return color;
    }
}
