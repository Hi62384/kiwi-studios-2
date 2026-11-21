using Godot;
using System;
public partial class ImageSoftenBrushOperations:RefCounted
{
    public Image prepare(Image source,double radius)
    {
        var result=(Image)source.Duplicate();result.Convert(Image.Format.Rgba8);result.PremultiplyAlpha();var extent=source.GetSize();double factor=Math.Max(2,Math.Clamp(radius,2,32));result.Resize(Math.Max(1,Mathf.RoundToInt(extent.X/factor)),Math.Max(1,Mathf.RoundToInt(extent.Y/factor)),Image.Interpolation.Lanczos);result.Resize(extent.X,extent.Y,Image.Interpolation.Bilinear);return result;
    }
    public Image composite(Image baseline,Image filtered,Image ink,Rect2I area,double strength,double opacity,Variant coverage,bool hasCoverage,bool opaque)
    {
        return Composite(baseline,filtered,ink,area,strength,opacity,hasCoverage?point=>ImageSoftenBrush._coverage_value(coverage,point):null,opaque);
    }
    internal Image Composite(Image baseline,Image filtered,Image ink,Rect2I area,double strength,double opacity,Func<Vector2,double>? coverage,bool opaque)
    {
        double amount=Math.Clamp(strength*opacity,0,1);double Weight(int x,int y)=>coverage!=null?Math.Clamp(coverage(new Vector2(area.Position.X+x+.5f,area.Position.Y+y+.5f)),0,1):1;using var smoothImage=filtered.GetRegion(area);var smooth=smoothImage.GetData();var mask=ink.GetData();if(opaque){var patch=baseline.GetRegion(area);for(int y=0;y<area.Size.Y;y++)for(int x=0;x<area.Size.X;x++){int offset=(y*area.Size.X+x)*4+3;smooth[offset]=(byte)Math.Clamp(Mathf.RoundToInt(mask[offset]*amount*Weight(x,y)),0,255);}using var blend=Image.CreateFromData(area.Size.X,area.Size.Y,false,Image.Format.Rgba8,smooth);patch.BlendRect(blend,new Rect2I(Vector2I.Zero,area.Size),Vector2I.Zero);return patch;}using var originalImage=baseline.GetRegion(area);var original=originalImage.GetData();for(int y=0;y<area.Size.Y;y++)for(int x=0;x<area.Size.X;x++){int offset=(y*area.Size.X+x)*4;double weight=mask[offset+3]/255.0*amount*Weight(x,y),oldAlpha=original[offset+3]/255.0,alpha=oldAlpha+(smooth[offset+3]/255.0-oldAlpha)*weight;for(int channel=0;channel<3;channel++){double premultiplied=original[offset+channel]*oldAlpha+(smooth[offset+channel]-original[offset+channel]*oldAlpha)*weight;original[offset+channel]=(byte)Math.Clamp(Mathf.RoundToInt(premultiplied/Math.Max(.00001,alpha)),0,255);}original[offset+3]=(byte)Math.Clamp(Mathf.RoundToInt(alpha*255),0,255);}return Image.CreateFromData(area.Size.X,area.Size.Y,false,Image.Format.Rgba8,original);
    }
}
