using Godot;
using System;
using GArray=Godot.Collections.Array;
using Settings=Godot.Collections.Dictionary;
public partial class ImageHealingOperations:RefCounted
{
    private static Variant Get(Settings d,string key,Variant fallback=default)=>d.TryGetValue(key,out var value)?value:fallback;
    public Color mean(Image image,Rect2I area,Rect2I excluded)
    {
        area=area.Intersection(new Rect2I(Vector2I.Zero,image.GetSize()));var sum=new Color(0,0,0,0);int count=0,step=Math.Max(1,Math.Max(area.Size.X,area.Size.Y)/12);for(int y=area.Position.Y;y<area.End.Y;y+=step)for(int x=area.Position.X;x<area.End.X;x+=step){if(excluded.HasPoint(new Vector2I(x,y)))continue;var color=image.GetPixel(x,y);if(color.A<.01)continue;sum+=color;count++;}if(count==0&&excluded.HasArea())return mean(image,area,new Rect2I());return sum/Math.Max(1,count);
    }
    public Color adapt(Color sample,Color sourceMean,Color destinationMean,double preserve)
    {
        var result=destinationMean+(sample-sourceMean)*(float)preserve;return new Color(Math.Clamp(result.R,0,1),Math.Clamp(result.G,0,1),Math.Clamp(result.B,0,1),sample.A);
    }
    public Image spot_patch(Image image,Rect2I area,Settings settings,Rect2I excluded,bool canCancel)
    {
        var extent=area.Size;using var random=new RandomNumberGenerator{Seed=unchecked((uint)GD.Hash(new GArray{area,Get(settings,"seed",0)}))};int radius=Math.Max(extent.X,extent.Y)*Get(settings,"search_radius",3).AsInt32();var best=area.Position;double score=double.PositiveInfinity;bool found=false;var imageArea=new Rect2I(Vector2I.Zero,image.GetSize());var bridge=canCancel?GD.Load<GDScript>("res://Workspaces/ImageWorkspace/image_healing.gd"):null;for(int candidateIndex=0;candidateIndex<96;candidateIndex++){if(canCancel&&bridge!.Call("_cancelled",settings["cancelled"]).AsBool())return image.GetRegion(area);double angle=candidateIndex*2.39996323,distance=Math.Max(extent.X,extent.Y)*1.5+radius*Math.Sqrt(candidateIndex/96.0);var source=area.Position+(Vector2I)(new Vector2((float)Math.Cos(angle),(float)Math.Sin(angle))*(float)distance)+new Vector2I(random.RandiRange(-2,2),random.RandiRange(-2,2));var candidate=new Rect2I(source,extent);if(!imageArea.Encloses(candidate)||candidate.Intersects(excluded))continue;double error=0;int count=0,margin=Math.Max(2,Math.Min(8,Math.Min(extent.X,extent.Y)/3));for(int y=-margin;y<extent.Y+margin;y+=Math.Max(1,extent.Y/6))for(int x=-margin;x<extent.X+margin;x+=Math.Max(1,extent.X/6)){var target=area.Position+new Vector2I(x,y);var sampled=source+new Vector2I(x,y);if(excluded.HasPoint(target)||!imageArea.HasPoint(target)||!imageArea.HasPoint(sampled))continue;var a=image.GetPixelv(target);var b=image.GetPixelv(sampled);if(a.A<.05||b.A<.05)continue;error+=ImageTextureSynthesisOperations.Difference(a,b);count++;}if(count>0&&error/count<score){score=error/count;best=source;found=true;}}if(!found)return image.GetRegion(area);var patch=image.GetRegion(new Rect2I(best,extent));var sourceMean=mean(image,new Rect2I(best,extent),new Rect2I());var targetMean=mean(image,new Rect2I(area.Position-extent/2,extent*2),excluded);double preserve=Get(settings,"texture_preservation",1).AsDouble();for(int y=0;y<patch.GetHeight();y++)for(int x=0;x<patch.GetWidth();x++)patch.SetPixel(x,y,adapt(patch.GetPixel(x,y),sourceMean,targetMean,preserve));return patch;
    }
}
