using Godot;
using System;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class MorphDistanceFieldOperations : RefCounted
{
    public Image build(Image image,Settings analysis,GArray otherPalette)
    {
        var size=image.GetSize();int count=checked(size.X*size.Y);var inside=new Vector2[count];var outside=new Vector2[count];var mask=analysis.TryGetValue("mask",out var raw)?raw.AsByteArray():Array.Empty<byte>();bool empty=mask.Length==0;var colors=new Vector3[otherPalette.Count];for(int index=0;index<colors.Length;index++)colors[index]=otherPalette[index].AsGodotDictionary()["color"].AsVector3();
        for(int index=0;index<count;index++){var point=new Vector2(index%size.X,index/size.X);bool occupied=!empty&&mask[index]!=0;inside[index]=occupied?point:new Vector2(-100000,-100000);var edge=new Vector2(-1,point.Y);void Near(Vector2 candidate){if(point.DistanceSquaredTo(candidate)<point.DistanceSquaredTo(edge))edge=candidate;}Near(new Vector2(size.X,point.Y));Near(new Vector2(point.X,-1));Near(new Vector2(point.X,size.Y));outside[index]=occupied?edge:point;}
        Propagate(inside,size);Propagate(outside,size);var values=new float[checked(count*4)];float extent=Math.Max(size.X,size.Y);
        for(int index=0;index<count;index++){var point=new Vector2(index%size.X,index/size.X);bool occupied=!empty&&mask[index]!=0;float distance=(occupied?point.DistanceTo(outside[index]):-Math.Min(extent,point.DistanceTo(inside[index])))/extent;var nearest=((inside[index]+Vector2.One*.5f)/(Vector2)size).Clamp(Vector2.Zero,Vector2.One);float novelty=0;if(occupied&&colors.Length>0){var color=image.GetPixel(index%size.X,index/size.X);var rgb=new Vector3(color.R,color.G,color.B);float gap=float.PositiveInfinity;foreach(var feature in colors)gap=Math.Min(gap,rgb.DistanceSquaredTo(feature));novelty=Mathf.SmoothStep(.015f,.08f,gap);}values[index*4]=distance;values[index*4+1]=nearest.X;values[index*4+2]=nearest.Y;values[index*4+3]=novelty;}
        var bytes=new byte[checked(values.Length*sizeof(float))];Buffer.BlockCopy(values,0,bytes,0,bytes.Length);return Image.CreateFromData(size.X,size.Y,false,Image.Format.Rgbaf,bytes);
    }
    public Vector2[] propagate(Vector2[] field,Vector2I size){Propagate(field,size);return field;}
    private static void Propagate(Vector2[] field,Vector2I size)
    {
        for(int pass=0;pass<2;pass++){int direction=pass==0?-1:1;var neighbors=new[]{new Vector2I(direction,0),new Vector2I(-1,direction),new Vector2I(0,direction),new Vector2I(1,direction)};for(int step=0;step<field.Length;step++){int index=pass==0?step:field.Length-1-step;int x=index%size.X,y=index/size.X;var point=new Vector2(x,y);var best=field[index];float distance=point.DistanceSquaredTo(best);foreach(var delta in neighbors){int nx=x+delta.X,ny=y+delta.Y;if(nx<0||nx>=size.X||ny<0||ny>=size.Y)continue;var candidate=field[ny*size.X+nx];float gap=point.DistanceSquaredTo(candidate);if(gap<distance){distance=gap;best=candidate;}}field[index]=best;}}
    }
}
