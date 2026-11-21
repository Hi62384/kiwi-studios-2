using Godot;
using System;
public partial class ImageWorkspaceOperations
{
    public Image current_selection_bitmap(Control owner)
    {
        var canvas=Canvas(owner);var selection=canvas.Get("selection").As<Image>();var sampler=new ImageCanvasSelectionOperations.SelectionSampler(canvas);if(selection!=null&&sampler.Identity)return (Image)selection.Duplicate();var size=Document(owner).Get("canvas_size").AsVector2I();var result=Image.CreateEmpty(size.X,size.Y,false,Image.Format.Rgba8);result.Fill(Colors.Transparent);if(selection==null)return result;for(int y=0;y<size.Y;y++)for(int x=0;x<size.X;x++)result.SetPixel(x,y,new Color(1,1,1,(float)sampler.Coverage(new Vector2(x,y))));return result;
    }
    public void modify_selection(Control owner,string kind,int radius)
    {
        if(Canvas(owner).Get("selection").AsGodotObject()==null)return;using var source=current_selection_bitmap(owner);using var result=(Image)source.Duplicate();int width=source.GetWidth(),height=source.GetHeight();var horizontal=new float[width*height];bool grow=kind=="grow",shrink=kind=="shrink";var alpha=new float[width*height];for(int y=0;y<height;y++)for(int x=0;x<width;x++)alpha[y*width+x]=source.GetPixel(x,y).A;for(int y=0;y<height;y++)for(int x=0;x<width;x++){float value=grow||kind is "feather" or "smooth"?0:1;int count=0;for(int offset=-radius;offset<=radius;offset++){int sx=x+offset;float next=sx>=0&&sx<width?alpha[y*width+sx]:0;if(grow)value=Math.Max(value,next);else if(shrink)value=Math.Min(value,next);else{value+=next;count++;}}horizontal[y*width+x]=grow||shrink?value:value/Math.Max(1,count);}for(int y=0;y<height;y++)for(int x=0;x<width;x++){float value=grow||kind is "feather" or "smooth"?0:1;int count=0;for(int offset=-radius;offset<=radius;offset++){int sy=y+offset;float next=sy>=0&&sy<height?horizontal[sy*width+x]:0;if(grow)value=Math.Max(value,next);else if(shrink)value=Math.Min(value,next);else{value+=next;count++;}}if(!grow&&!shrink)value/=Math.Max(1,count);if(kind=="smooth")value=value>=.5?1:0;result.SetPixel(x,y,new Color(1,1,1,value));}commit_selection_bitmap(owner,result);
    }
    public void source_to_mask(Control owner,bool luminance)
    {
        var layer=main_layer(owner);if(layer==null)return;var texture=layer.Get("texture").As<Texture2D>();if(texture==null){owner.Get("status").As<Label>().Text="This layer needs raster content or a pixel selection for a mask.";return;}using var source=texture.GetImage();using var bitmap=(Image)source.Duplicate();var dimensions=layer.Get("dimensions").AsVector2();bitmap.Resize(Math.Max(1,Mathf.RoundToInt(dimensions.X)),Math.Max(1,Mathf.RoundToInt(dimensions.Y)),Image.Interpolation.Bilinear);for(int y=0;y<bitmap.GetHeight();y++)for(int x=0;x<bitmap.GetWidth();x++){var color=bitmap.GetPixel(x,y);float value=luminance?(.2126f*color.R+.7152f*color.G+.0722f*color.B)*color.A:color.A;bitmap.SetPixel(x,y,new Color(value,value,value,value));}Action(owner,()=>layer.Set("mask",ImageTexture.CreateFromImage(bitmap)));
    }
    public void mask_to_selection(Control owner)
    {
        var layer=main_layer(owner);if(layer==null||layer.Get("mask").As<Texture2D>() is not Texture2D texture){owner.Get("status").As<Label>().Text="The selected layer has no mask.";return;}using var local=texture.GetImage();var size=Document(owner).Get("canvas_size").AsVector2I();using var result=Image.CreateEmpty(size.X,size.Y,false,Image.Format.Rgba8);result.Fill(Colors.Transparent);var dimensions=layer.Get("dimensions").AsVector2();var transform=_documents.world_transform(Document(owner),layer);var inverse=transform.AffineInverse();var area=transform*new Rect2(Vector2.Zero,dimensions);var bounds=new Rect2I((Vector2I)area.Position.Floor(),(Vector2I)area.Size.Ceil()).Intersection(new Rect2I(Vector2I.Zero,size));var projection=new ImageLayerProjection(layer);for(int y=bounds.Position.Y;y<bounds.End.Y;y++)for(int x=bounds.Position.X;x<bounds.End.X;x++){var sample=(Vector2I)(projection.Unproject(inverse*new Vector2(x,y))*(Vector2)local.GetSize()/dimensions.Max(Vector2.One));if(new Rect2I(Vector2I.Zero,local.GetSize()).HasPoint(sample))result.SetPixel(x,y,new Color(1,1,1,local.GetPixelv(sample).R));}commit_selection_bitmap(owner,result);owner.Call("_set_tool","pixel_select");
    }
    public void select_similar_dialog(Control owner)
    {
        var dialog=new ConfirmationDialog{Title="Select similar color"};owner.AddChild(dialog);var column=new VBoxContainer{CustomMinimumSize=new Vector2(380,130)};dialog.AddChild(column);var picker=new ColorPickerButton{Color=owner.Get("color_picker").As<ColorPickerButton>().Color,Text="Reference color"};column.AddChild(picker);var tolerance=new HSlider{MinValue=.001,MaxValue=1,Step=.001,Value=.12};column.AddChild(tolerance);dialog.Confirmed+=()=>{owner.Call("_smart_select","similar",picker.Color,tolerance.Value);dialog.QueueFree();};dialog.Canceled+=dialog.QueueFree;dialog.PopupCentered();
    }
}
