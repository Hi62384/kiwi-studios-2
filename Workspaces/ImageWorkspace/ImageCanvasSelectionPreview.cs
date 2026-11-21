using Godot;
using System;
using GArray=Godot.Collections.Array;
public partial class ImageCanvasSelectionOperations
{
    private static bool HasWarp(Control canvas,bool inverse=false)=>canvas.Call("_has_selection_warp",inverse).AsBool();
    private static Vector2 Map(Control canvas,Vector2 point,bool inverse=false)
    {
        var mapping=canvas.Get("_selection_mapping").AsGodotObject() as ImageSelectionMapping;return mapping!=null?(inverse?mapping.inverse(point):mapping.forward(point)):canvas.Call("_map_selection_point",point,inverse).AsVector2();
    }
    private static Vector2[] Corners(Rect2I used)=>new[]{(Vector2)used.Position,new Vector2(used.End.X,used.Position.Y),(Vector2)used.End,new Vector2(used.Position.X,used.End.Y)};
    private static void ClearMapping(Control canvas)
    {
        canvas.Set("selection_transform",Transform2D.Identity);canvas.Set("selection_inverse",Transform2D.Identity);canvas.Set("selection_forward_warp",default(Callable));canvas.Set("selection_inverse_warp",default(Callable));canvas.Set("_selection_mapping",default(Variant));canvas.Set("selection_preview_origin",Vector2.Zero);
    }
    private static void Overlay(Control canvas){canvas.Call("_sync_selection_overlay");canvas.QueueRedraw();}
    public double threshold_bytes(double value)=>Math.Clamp(value,0,1)*510;
    public void make_selection(Control canvas,string kind,Rect2 rect)
    {
        var selection=canvas.Get("selection").As<Image>();int operation=canvas.Get("_selection_operation").AsInt32();if(selection==null||operation==0){var size=canvas.Get("document").AsGodotObject().Get("canvas_size").AsVector2I();selection=Image.CreateEmpty(size.X,size.Y,false,Image.Format.Rgba8);selection.Fill(Colors.Transparent);canvas.Set("selection",selection);}
        var points=canvas.Get("_points").AsVector2Array();if(kind=="lasso"&&points.Length>2){rect=new Rect2(points[0],Vector2.Zero);foreach(var p in points)rect=rect.Expand(p);}var color=operation==-1?Colors.Transparent:Colors.White;
        for(int y=Math.Max(0,Mathf.FloorToInt(rect.Position.Y));y<Math.Min(selection.GetHeight(),Mathf.CeilToInt(rect.End.Y));y++)for(int x=Math.Max(0,Mathf.FloorToInt(rect.Position.X));x<Math.Min(selection.GetWidth(),Mathf.CeilToInt(rect.End.X));x++)if(kind!="lasso"||points.Length>2&&Geometry2D.IsPointInPolygon(new Vector2(x,y),points))selection.SetPixel(x,y,color);
        canvas.Set("selection_texture",ImageTexture.CreateFromImage(selection));canvas.Set("pixel_selection_bounds",new Rect2(rect.Position.Floor(),rect.Size.Ceil()));canvas.EmitSignal("hint_changed","Selection ready · Paint inside it, or choose Selection → Mask / Copy / Clear");
    }
    public void clear_selection(Control canvas){canvas.Set("_selection_preview_size",Vector2.Zero);ClearMapping(canvas);canvas.Set("selection",default(Variant));canvas.Set("selection_texture",default(Variant));canvas.Set("pixel_selection_bounds",new Rect2());Overlay(canvas);}
    public void update_selection_preview(Control canvas)
    {
        var selection=canvas.Get("selection").As<Image>();if(selection==null)return;if(HasWarp(canvas)&&HasWarp(canvas,true)){update_warped_selection_preview(canvas);return;}canvas.Set("_selection_preview_size",Vector2.Zero);((ShaderMaterial)canvas.Get("_selection_overlay").As<Control>().Material).SetShaderParameter("warped",false);var texture=canvas.Get("selection_texture").As<ImageTexture>();if(texture!=null&&texture.GetSize()==(Vector2)selection.GetSize())texture.Update(selection);else canvas.Set("selection_texture",ImageTexture.CreateFromImage(selection));canvas.Set("selection_preview_origin",Vector2.Zero);var used=selection.GetUsedRect();canvas.Set("pixel_selection_bounds",canvas.Get("selection_transform").AsTransform2D()*(Rect2)used);Overlay(canvas);
    }
    public void update_warped_selection_preview(Control canvas)
    {
        var selection=canvas.Get("selection").As<Image>();var used=selection.GetUsedRect();if(!used.HasArea()){canvas.Set("selection_texture",default(Variant));canvas.Set("pixel_selection_bounds",new Rect2());Overlay(canvas);return;}
        var corners=Corners(used);var bounds=new Rect2(Map(canvas,corners[0]),Vector2.Zero);for(int i=1;i<4;i++)bounds=bounds.Expand(Map(canvas,corners[i]));var visible=new Rect2I((Vector2I)bounds.Position.Floor(),(Vector2I)(bounds.End.Ceil()-bounds.Position.Floor())).Intersection(new Rect2I(Vector2I.Zero,canvas.Get("document").AsGodotObject().Get("canvas_size").AsVector2I()));canvas.Set("pixel_selection_bounds",bounds);
        if(!visible.HasArea()){canvas.Set("selection_texture",default(Variant));Overlay(canvas);return;}
        for(int i=0;i<4;i++)corners[i]=(Map(canvas,corners[i])-(Vector2)visible.Position)/(Vector2)visible.Size;var rows=Projection(corners);if(rows.Length==0)return;using var preview=selection.GetRegion(used);canvas.Set("selection_preview_origin",(Vector2)visible.Position);canvas.Set("_selection_preview_size",(Vector2)visible.Size);var texture=canvas.Get("selection_texture").As<ImageTexture>();if(texture!=null&&texture.GetSize()==(Vector2)preview.GetSize())texture.Update(preview);else canvas.Set("selection_texture",ImageTexture.CreateFromImage(preview));var material=(ShaderMaterial)canvas.Get("_selection_overlay").As<Control>().Material;material.SetShaderParameter("warped",true);for(int i=0;i<3;i++)material.SetShaderParameter("row"+i,rows[i]);Overlay(canvas);
    }
    public GArray selection_projection(Vector2[] corners){var result=new GArray();foreach(var row in Projection(corners))result.Add(row);return result;}
    internal static Vector3[] Projection(Vector2[] corners)
    {
        var equations=new double[8,9];var uv=new[]{Vector2.Zero,Vector2.Right,Vector2.One,Vector2.Down};for(int i=0;i<4;i++){double x=corners[i].X,y=corners[i].Y,u=uv[i].X,v=uv[i].Y;int row=i*2;equations[row,0]=x;equations[row,1]=y;equations[row,2]=1;equations[row,6]=-u*x;equations[row,7]=-u*y;equations[row,8]=u;equations[row+1,3]=x;equations[row+1,4]=y;equations[row+1,5]=1;equations[row+1,6]=-v*x;equations[row+1,7]=-v*y;equations[row+1,8]=v;}
        for(int column=0;column<8;column++){int pivot=column;for(int row=column+1;row<8;row++)if(Math.Abs(equations[row,column])>Math.Abs(equations[pivot,column]))pivot=row;if(Math.Abs(equations[pivot,column])<.000000001)return Array.Empty<Vector3>();for(int j=0;j<9;j++)(equations[column,j],equations[pivot,j])=(equations[pivot,j],equations[column,j]);double factor=equations[column,column];for(int j=column;j<9;j++)equations[column,j]/=factor;for(int row=0;row<8;row++){if(row==column)continue;factor=equations[row,column];for(int j=column;j<9;j++)equations[row,j]-=factor*equations[column,j];}}
        return new[]{new Vector3((float)equations[0,8],(float)equations[1,8],(float)equations[2,8]),new Vector3((float)equations[3,8],(float)equations[4,8],(float)equations[5,8]),new Vector3((float)equations[6,8],(float)equations[7,8],1)};
    }
    public void bake_selection_transform(Control canvas)
    {
        var source=canvas.Get("selection").As<Image>();var transform=canvas.Get("selection_transform").AsTransform2D();bool warp=HasWarp(canvas);if(source==null||transform.IsEqualApprox(Transform2D.Identity)&&!warp)return;var used=source.GetUsedRect();var bounds=transform*(Rect2)used;if(warp){var corners=Corners(used);bounds=new Rect2(Map(canvas,corners[0]),Vector2.Zero);for(int i=1;i<4;i++)bounds=bounds.Expand(Map(canvas,corners[i]));}
        var size=canvas.Get("document").AsGodotObject().Get("canvas_size").AsVector2I();var area=new Rect2I((Vector2I)bounds.Position.Floor(),(Vector2I)(bounds.End.Ceil()-bounds.Position.Floor())).Intersection(new Rect2I(Vector2I.Zero,size));var selection=Image.CreateEmpty(size.X,size.Y,false,Image.Format.Rgba8);canvas.Set("selection",selection);var inverse=canvas.Get("selection_inverse").AsTransform2D();bool inverseWarp=HasWarp(canvas,true);
        if(!warp&&Mathf.IsZeroApprox(transform.X.Y)&&Mathf.IsZeroApprox(transform.Y.X)&&used.HasArea()){using var piece=source.GetRegion(used);piece.Resize(Math.Max(1,Mathf.RoundToInt(bounds.Size.X)),Math.Max(1,Mathf.RoundToInt(bounds.Size.Y)),Image.Interpolation.Nearest);if(transform.X.X<0)piece.FlipX();if(transform.Y.Y<0)piece.FlipY();selection.BlitRect(piece,new Rect2I(Vector2I.Zero,piece.GetSize()),(Vector2I)bounds.Position.Round());}
        else for(int y=area.Position.Y;y<area.End.Y;y++){var at=new Vector2(area.Position.X+.5f,y+.5f);var sample=inverseWarp?Map(canvas,at,true):inverse*at;for(int x=area.Position.X;x<area.End.X;x++){var pixel=(Vector2I)sample.Floor();if(used.HasPoint(pixel))selection.SetPixel(x,y,source.GetPixelv(pixel));sample=inverseWarp?Map(canvas,new Vector2(x+1.5f,y+.5f),true):sample+inverse.X;}}
        ClearMapping(canvas);canvas.Set("selection_texture",default(Variant));update_selection_preview(canvas);
    }
}
