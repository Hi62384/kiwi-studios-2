using Godot;
using System;
public partial class PixelSelectionAlphaOperations:RefCounted
{
    public Image stamp(double diameter,double falloff)
    {
        var image=Image.CreateEmpty(64,64,false,Image.Format.Rgba8);var bytes=new byte[64*64*4];for(int y=0;y<64;y++)for(int x=0;x<64;x++){double radius=new Vector2(x+.5f-32,y+.5f-32).Length()/32.0,alpha=radius<1?1:0;if(falloff>0){double t=Math.Clamp((1-radius)/falloff,0,1);alpha=t*t*(3-2*t);}int index=(y*64+x)*4;bytes[index]=bytes[index+1]=bytes[index+2]=255;bytes[index+3]=(byte)Math.Clamp(Mathf.RoundToInt(alpha*255),0,255);}image.SetData(64,64,false,Image.Format.Rgba8,bytes);int size=Math.Max(1,(int)Math.Ceiling(diameter));image.Resize(size,size,Image.Interpolation.Bilinear);return image;
    }
    public Image blend(Image baseline,Image coverage,double amount,bool subtract,Vector2I origin)
    {
        var result=(Image)baseline.Duplicate();var region=new Rect2I(origin,coverage.GetSize()).Intersection(new Rect2I(Vector2I.Zero,baseline.GetSize()));if(!region.HasArea())return result;using var source=baseline.GetRegion(region);using var maskImage=coverage.GetRegion(new Rect2I(region.Position-origin,region.Size));var prior=source.GetData();var mask=maskImage.GetData();for(int offset=3;offset<prior.Length;offset+=4){double weight=mask[offset]/255.0,old=prior[offset]/255.0,alpha=subtract?old+(0-old)*weight*amount:old+(amount-old)*weight;prior[offset]=(byte)Math.Clamp(Mathf.RoundToInt(Math.Clamp(alpha,0,1)*255),0,255);prior[offset-3]=prior[offset-2]=prior[offset-1]=255;}using var patch=Image.CreateFromData(region.Size.X,region.Size.Y,false,Image.Format.Rgba8,prior);result.BlitRect(patch,new Rect2I(Vector2I.Zero,region.Size),region.Position);return result;
    }
    public void blend_region(Image result,Image baseline,Image coverage,Rect2I area,double amount,bool subtract)
    {
        area=area.Intersection(new Rect2I(Vector2I.Zero,result.GetSize()));if(!area.HasArea())return;using var source=baseline.GetRegion(area);using var mask=coverage.GetRegion(area);using var patch=blend(source,mask,amount,subtract,Vector2I.Zero);result.BlitRect(patch,new Rect2I(Vector2I.Zero,area.Size),area.Position);
    }
    public Image feather(Image mask,double falloff)
    {
        if(falloff<=0)return mask;var small=(Image)mask.Duplicate();double scale=Math.Min(1,256.0/Math.Max(mask.GetWidth(),mask.GetHeight()));if(scale<1)small.Resize(Math.Max(1,Mathf.RoundToInt(mask.GetWidth()*scale)),Math.Max(1,Mathf.RoundToInt(mask.GetHeight()*scale)),Image.Interpolation.Nearest);var size=small.GetSize();var bytes=small.GetData();var distance=new float[size.X*size.Y];float maximum=0;for(int index=0;index<distance.Length;index++)distance[index]=bytes[index*4+3]>0?100000:0;for(int y=0;y<size.Y;y++)for(int x=0;x<size.X;x++){int index=y*size.X+x;if(distance[index]==0)continue;if(x==0||y==0)distance[index]=1;if(x>0)distance[index]=Math.Min(distance[index],distance[index-1]+1);if(y>0)distance[index]=Math.Min(distance[index],distance[index-size.X]+1);}for(int y=size.Y-1;y>=0;y--)for(int x=size.X-1;x>=0;x--){int index=y*size.X+x;if(distance[index]==0)continue;if(x==size.X-1||y==size.Y-1)distance[index]=1;if(x+1<size.X)distance[index]=Math.Min(distance[index],distance[index+1]+1);if(y+1<size.Y)distance[index]=Math.Min(distance[index],distance[index+size.X]+1);maximum=Math.Max(maximum,distance[index]);}double width=Math.Max(1,maximum*falloff);for(int index=0;index<distance.Length;index++){double t=Math.Clamp(distance[index]/width,0,1);bytes[index*4+3]=(byte)Math.Clamp(Mathf.RoundToInt(bytes[index*4+3]*t*t*(3-2*t)),0,255);}small.SetData(size.X,size.Y,false,Image.Format.Rgba8,bytes);if(scale<1)small.Resize(mask.GetWidth(),mask.GetHeight(),Image.Interpolation.Bilinear);return small;
    }
}
