using Godot;
using System;
using GArray=Godot.Collections.Array;
using Settings=Godot.Collections.Dictionary;
public partial class ImageCanvasSelectionOperations
{
    private readonly ImageLayerOperations _layers=new();private readonly ImageValueOperations _values=new();
    private static Variant Get(Settings data,string key,Variant fallback=default)=>data.TryGetValue(key,out var value)?value:fallback;
    public Vector2 origin(Control canvas){var document=canvas.Get("document").AsGodotObject();return document!=null?canvas.Size*.5f-(Vector2)document.Get("canvas_size").AsVector2I()*canvas.Get("zoom").AsSingle()*.5f+canvas.Get("pan").AsVector2():Vector2.Zero;}
    public Vector2 to_document(Control canvas,Vector2 point)=>(point-origin(canvas))/canvas.Get("zoom").AsSingle();
    public void fit(Control canvas){var document=canvas.Get("document").AsGodotObject();if(document==null)return;var size=document.Get("canvas_size").AsVector2I();canvas.Set("zoom",Math.Clamp(Math.Min((canvas.Size.X-100)/size.X,(canvas.Size.Y-100)/size.Y),.03,8));canvas.Set("pan",Vector2.Zero);canvas.QueueRedraw();}
    public void set_zoom(Control canvas,double value,Vector2 anchor){if(canvas.Get("document").AsGodotObject()==null)return;if(anchor.X<0)anchor=canvas.Size*.5f;var at=to_document(canvas,anchor);canvas.Set("zoom",Math.Clamp(value,.03,32));canvas.Set("pan",canvas.Get("pan").AsVector2()+anchor-(origin(canvas)+at*canvas.Get("zoom").AsSingle()));canvas.QueueRedraw();}
    public Rect2 selection_bounds(Control canvas)
    {
        var document=canvas.Get("document").As<Resource>();var result=new Rect2();bool first=true;if(document==null)return result;foreach(var entry in _documents.selected_roots(document,canvas.Get("selected").AsGodotArray())){var item=entry.As<Resource>();var world=_documents.world_transform(document,item);var projection=new ImageLayerProjection(item);var rect=new Rect2(world*projection.Project(Vector2.Zero,new Vector2(-1,-1)),Vector2.Zero);foreach(var uv in new[]{Vector2.Right,Vector2.One,Vector2.Down})rect=rect.Expand(world*projection.Project(uv*projection.Dimensions,new Vector2(-1,-1)));result=first?rect:result.Merge(rect);first=false;}return result;
    }
    private static readonly Vector2[] HandleUvs={Vector2.Zero,new(.5f,0),Vector2.Right,new(1,.5f),Vector2.One,new(.5f,1),Vector2.Down,new(0,.5f)};
    private Vector2[] ProjectedHandles(Control canvas,Rect2 rect)
    {
        var document=canvas.Get("document").As<Resource>();if(document!=null){var roots=_documents.selected_roots(document,canvas.Get("selected").AsGodotArray());if(roots.Count==1){var item=roots[0].As<Resource>();var world=_documents.world_transform(document,item);var frame=_layers.projected_bounds(item,new Vector2(-1,-1));var points=new Vector2[8];var offset=origin(canvas);float zoom=canvas.Get("zoom").AsSingle();for(int i=0;i<8;i++)points[i]=offset+world*(frame.Position+HandleUvs[i]*frame.Size)*zoom;return points;}}return RawHandles(rect);
    }
    private static Vector2[] RawHandles(Rect2 rect){var points=new Vector2[8];for(int i=0;i<8;i++)points[i]=rect.Position+HandleUvs[i]*rect.Size;return points;}
    private static GArray ArrayOf(Vector2[] points){var result=new GArray();foreach(var point in points)result.Add(point);return result;}
    public GArray projected_handles(Control canvas,Rect2 rect)=>ArrayOf(ProjectedHandles(canvas,rect));
    public GArray raw_handles(Rect2 rect)=>ArrayOf(RawHandles(rect));
    public GArray handles(Control canvas,Rect2 rect)
    {
        var points=ProjectedHandles(canvas,rect);var visible=new Rect2(Vector2.One*8,(canvas.Size-Vector2.One*16).Max(Vector2.One));for(int i=0;i<points.Length;i++)points[i]=points[i].Clamp(visible.Position,visible.End);string drag=canvas.Get("_drag").AsString();if(canvas.Get("_resize_proxy_active").AsBool()&&drag.StartsWith("resize",StringComparison.Ordinal))points[int.Parse(drag[6..],System.Globalization.CultureInfo.InvariantCulture)]=canvas.Get("_resize_proxy_screen").AsVector2().Clamp(visible.Position,visible.End);return ArrayOf(points);
    }
    public Vector2 rotation_handle(Control canvas,Rect2 rect){var points=ProjectedHandles(canvas,rect);var outward=(points[1]-points[5]).Normalized();return(points[1]+outward*25).Clamp(Vector2.One*8,(canvas.Size-Vector2.One*8).Max(Vector2.One*8));}
    public Resource? hit(Control canvas,Vector2 point)
    {
        var document=canvas.Get("document").As<Resource>();var layers=document.Get("layers").AsGodotArray();var selected=canvas.Get("selected").AsGodotArray();for(int i=layers.Count-1;i>=0;i--){var item=layers[i].As<Resource>();string kind=item.Get("kind").AsString();if(kind=="group"||!_documents.can_edit(document,item))continue;var projection=new ImageLayerProjection(item);var local=projection.Unproject(_documents.world_transform(document,item).AffineInverse()*point);if(!new Rect2(Vector2.Zero,_layers.content_dimensions(item)).HasPoint(local))continue;if(selected.Contains(item.Get("id")))return item;var properties=item.Get("properties").AsGodotDictionary();if(kind=="shape"&&Get(properties,"shape","").AsString()=="ellipse"&&((local/projection.Dimensions-Vector2.One*.5f)*2).LengthSquared()>1)continue;var texture=item.Get("texture").As<Texture2D>();if((kind is "image" or "paint" or "basic")&&texture!=null){using var bitmap=texture.GetImage();if(bitmap!=null){var pixel=((Vector2I)(local/projection.Dimensions*(Vector2)bitmap.GetSize())).Clamp(Vector2I.Zero,bitmap.GetSize()-Vector2I.One);if(bitmap.GetPixelv(pixel).A<.02)continue;}}return item;}return null;
    }
    public void sync_selection_overlay(Control canvas)
    {
        string tool=canvas.Get("tool").AsString();var texture=canvas.Get("selection_texture").As<Texture2D>();bool visible=(tool=="pixel_select"||canvas.Get("paint_selection_only").AsBool()&&(tool is "brush" or "eraser" or "fill"))&&texture!=null&&canvas.Get("document").AsGodotObject()!=null;var overlay=canvas.Get("_selection_overlay").As<TextureRect>();if(visible){((ShaderMaterial)overlay.Material).SetShaderParameter("strength",tool=="pixel_select"?.65:.16);overlay.Texture=texture;var size=canvas.Get("_selection_preview_size").AsVector2();overlay.Size=size!=Vector2.Zero?size:texture!.GetSize();overlay.Position=origin(canvas)+canvas.Get("selection_preview_origin").AsVector2()*canvas.Get("zoom").AsSingle();overlay.Scale=Vector2.One*canvas.Get("zoom").AsSingle();}overlay.Visible=visible;
    }
    public void prepare_source_color(Control canvas)
    {
        var item=canvas.Get("_paint_layer").As<Resource>();if(item==null)return;var properties=item.Get("properties").AsGodotDictionary();canvas.Set("_value_mask_mapping",Transform2D.Identity);if(properties.TryGetValue("values_selection_frame",out var stored)){var frame=stored.AsTransform2D();var dimensions=item.Get("dimensions").AsVector2();canvas.Set("_value_mask_mapping",frame.ScaledLocal(Get(properties,"values_selection_dimensions",dimensions).AsVector2()/dimensions.Max(Vector2.One))*_documents.world_transform(canvas.Get("document").As<Resource>(),item).AffineInverse());}long key=GD.Hash(new GArray{canvas.Get("color"),item.Get("id"),_values.operations(item),Get(properties,"values_selection")});if(key!=canvas.Get("_value_inverse_key").AsInt64()){canvas.Set("_value_inverse_key",key);canvas.Set("_value_inverse_color",_values.inverse_color(canvas.Get("color").AsColor(),item));var mask=Get(properties,"values_selection").As<Texture2D>();canvas.Set("_value_mask",mask==null?default(Variant):Variant.From(mask.GetImage()));}
    }
    public Color source_color(Control canvas,Vector2 point)
    {
        if(canvas.Get("_material_region").AsGodotObject()!=null)return Colors.White;var item=canvas.Get("_paint_layer").As<Resource>();var color=canvas.Get("color").AsColor();if(item==null)return color;var properties=item.Get("properties").AsGodotDictionary();if(Get(properties,"values_selection_only",false).AsBool()){var mask=canvas.Get("_value_mask").As<Image>();if(mask==null)return color;var p=(Vector2I)(canvas.Get("_value_mask_mapping").AsTransform2D()*point);if(Get(properties,"values_selection_local",false).AsBool()){var local=new ImageLayerProjection(item).Unproject(_documents.world_transform(canvas.Get("document").As<Resource>(),item).AffineInverse()*point);p=(Vector2I)(local/_layers.content_dimensions(item)*(Vector2)mask.GetSize());}if(!new Rect2I(Vector2I.Zero,mask.GetSize()).HasPoint(p)||mask.GetPixelv(p).A<=0)return color;}return canvas.Get("_value_inverse_color").AsColor();
    }
    public double selection_coverage(Control canvas,Vector2 point,bool warped){var selection=canvas.Get("selection").As<Image>();if(selection==null)return 1;var source=warped?Map(canvas,point,true):canvas.Get("selection_inverse").AsTransform2D()*point;var at=(Vector2I)source.Floor();return new Rect2I(Vector2I.Zero,selection.GetSize()).HasPoint(at)?selection.GetPixelv(at).A:0;}
}
