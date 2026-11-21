using Godot;
using System;
public partial class ImageCanvasSelectionOperations:RefCounted
{
    private readonly ImageDocumentOperations _documents=new();
    private static double Number(Resource layer,string key){var properties=layer.Get("properties").AsGodotDictionary();return properties.TryGetValue(key,out var value)?value.AsDouble():0;}
    public void sync_pixel_selection(Control canvas)
    {
        canvas.Set("selection_transform",Transform2D.Identity);canvas.Set("selection_inverse",Transform2D.Identity);canvas.Set("selection_forward_warp",default(Callable));canvas.Set("selection_inverse_warp",default(Callable));canvas.Set("_selection_mapping",default(Variant));canvas.Set("selection_preview_origin",Vector2.Zero);canvas.Set("selection_texture",default(Variant));var document=canvas.Get("document").As<Resource>();var selected=canvas.Get("selected").AsGodotArray();if(document!=null&&selected.Count>0&&document.Get("pixel_selection_owner").AsString()==selected[selected.Count-1].AsString()&&document.Get("pixel_selection").AsGodotObject()!=null){using var pixels=document.Get("pixel_selection").As<Texture2D>().GetImage();canvas.Set("selection",pixels.Duplicate());var old=document.Get("pixel_selection_reference").As<Resource>();var current=_documents.layer_for_id(document,document.Get("pixel_selection_owner").AsString());if(old!=null&&current!=null){var from=document.Get("pixel_selection_reference_world").AsTransform2D();var to=_documents.world_transform(document,current);bool sameYaw=Mathf.IsEqualApprox(Number(old,"yaw_up_down"),Number(current,"yaw_up_down"))&&Mathf.IsEqualApprox(Number(old,"yaw_left_right"),Number(current,"yaw_left_right"));if(!(from.IsEqualApprox(to)&&old.Get("dimensions").AsVector2().IsEqualApprox(current.Get("dimensions").AsVector2())&&sameYaw)){var mapping=new ImageSelectionMapping(old,current,from,to);canvas.Set("_selection_mapping",mapping);canvas.Set("selection_forward_warp",new Callable(mapping,nameof(ImageSelectionMapping.forward)));canvas.Set("selection_inverse_warp",new Callable(mapping,nameof(ImageSelectionMapping.inverse)));}}canvas.Call("_update_selection_preview");}else canvas.Call("clear_selection");
    }
}
