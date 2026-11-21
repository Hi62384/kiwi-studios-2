using Godot;
public partial class ImageCanvasSelectionOperations
{
    public Texture2D? capture_layer_selection(Control canvas,Resource layer)
    {
        var selection=canvas.Get("selection").As<Image>();if(selection==null)return null;var size=((Vector2I)layer.Get("dimensions").AsVector2().Ceil()).Max(Vector2I.One);using var bitmap=Image.CreateEmpty(size.X,size.Y,false,Image.Format.Rgba8);bitmap.Fill(Colors.Transparent);var world=_documents.world_transform(canvas.Get("document").As<Resource>(),layer);var mapping=canvas.Get("selection_inverse").AsTransform2D()*world;var properties=layer.Get("properties").AsGodotDictionary();bool translated=!HasWarp(canvas,true)&&mapping.X.IsEqualApprox(Vector2.Right)&&mapping.Y.IsEqualApprox(Vector2.Down)&&mapping.Origin.IsEqualApprox(mapping.Origin.Round())&&Mathf.IsZeroApprox(Get(properties,"yaw_up_down",0).AsDouble())&&Mathf.IsZeroApprox(Get(properties,"yaw_left_right",0).AsDouble());
        if(translated){var origin=(Vector2I)mapping.Origin.Round();var region=new Rect2I(origin,size).Intersection(new Rect2I(Vector2I.Zero,selection.GetSize()));if(region.HasArea())bitmap.BlitRect(selection,region,region.Position-origin);}
        else{var sampler=new SelectionSampler(canvas);var projection=new ImageLayerProjection(layer);for(int y=0;y<size.Y;y++)for(int x=0;x<size.X;x++){float alpha=(float)sampler.Coverage(world*projection.Project(new Vector2(x+.5f,y+.5f),new Vector2(-1,-1)));if(alpha>0)bitmap.SetPixel(x,y,new Color(1,1,1,alpha));}}return ImageTexture.CreateFromImage(bitmap);
    }
}
