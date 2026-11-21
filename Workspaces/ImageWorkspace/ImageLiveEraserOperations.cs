using Godot;
using System;
using Settings=Godot.Collections.Dictionary;
public partial class ImageLiveEraserOperations:RefCounted
{
    public void begin(RefCounted owner,Resource layer,Vector2I size)
    {
        owner.Set("source_size",size);var regions=owner.Get("regions").AsGodotArray();foreach(var raw in layer.Get("live_paint").AsGodotArray()){var region=raw.AsGodotObject();bool live=region.Call("is_live").AsBool();var texture=region.Get(live?"coverage":"raster").As<Texture2D>();if(texture==null)continue;var original=texture.GetImage();if(original==null||original.IsEmpty()){original?.Dispose();continue;}original.Convert(Image.Format.Rgba8);var working=(Image)original.Duplicate();var mutable=ImageTexture.CreateFromImage(working);region.Set(live?"coverage":"raster",mutable);regions.Add(new Settings{["original"]=original,["working"]=working,["texture"]=mutable});}
    }
    public void apply(RefCounted owner,Rect2I area,Image coverage)
    {
        var sourceSize=owner.Get("source_size").AsVector2I();foreach(var raw in owner.Get("regions").AsGodotArray()){var entry=raw.AsGodotDictionary();var original=entry["original"].As<Image>();var working=entry["working"].As<Image>();var ratio=(Vector2)original.GetSize()/(Vector2)sourceSize;var start=(Vector2I)((Vector2)area.Position*ratio).Floor();var end=(Vector2I)((Vector2)area.End*ratio).Ceil();var patch=new Rect2I(start,end-start).Intersection(new Rect2I(Vector2I.Zero,original.GetSize()));for(int y=patch.Position.Y;y<patch.End.Y;y++)for(int x=patch.Position.X;x<patch.End.X;x++){var at=(Vector2I)(new Vector2(x,y)/ratio)-area.Position;at=at.Clamp(Vector2I.Zero,coverage.GetSize()-Vector2I.One);var color=original.GetPixel(x,y);color.A*=1-coverage.GetPixelv(at).A;if(color.A<=0)color=Colors.Transparent;working.SetPixel(x,y,color);}entry["texture"].As<ImageTexture>().Update(working);}
    }
}
