using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
public partial class ImageCanvasSelectionOperations
{
    public void draw(Control canvas)
    {
        canvas.DrawRect(new Rect2(Vector2.Zero,canvas.Size),new Color("101720"));var document=canvas.Get("document").As<Resource>();if(document==null)return;var offset=origin(canvas);float zoom=canvas.Get("zoom").AsSingle();string tool=canvas.Get("tool").AsString(),drag=canvas.Get("_drag").AsString();var rect=new Rect2(offset,(Vector2)document.Get("canvas_size").AsVector2I()*zoom);canvas.DrawRect(rect.Grow(6),new Color(0,0,0,.25f));canvas.DrawRect(rect,new Color("27313e"));var clipped=rect.Intersection(new Rect2(Vector2.Zero,canvas.Size));
        for(int y=Mathf.FloorToInt(clipped.Position.Y/14);y<Mathf.CeilToInt(clipped.End.Y/14);y++)for(int x=Mathf.FloorToInt(clipped.Position.X/14);x<Mathf.CeilToInt(clipped.End.X/14);x++)if((x+y)%2==0)canvas.DrawRect(new Rect2(new Vector2(x,y)*14,Vector2.One*14).Intersection(rect),new Color("303b48"));
        var preview=canvas.Get("preview").As<Texture2D>();if(preview!=null){if(canvas.Get("preview_screen_space").AsBool())canvas.DrawTextureRectRegion(preview,clipped,clipped);else canvas.DrawTextureRect(preview,rect,false);}canvas.DrawRect(rect,new Color("536176"),false,1);
        if(tool=="warp")_warpInteraction.draw(canvas.Get("warp_tool").As<RefCounted>());if(tool=="repair")_repairInteraction.draw(canvas.Get("repair_tool").As<RefCounted>());
        foreach(var guide in canvas.Get("snap_guides_x").AsGodotArray()){float x=offset.X+guide.AsSingle()*zoom;canvas.DrawLine(new Vector2(x,0),new Vector2(x,canvas.Size.Y),new Color("66e0c1"),1);}foreach(var guide in canvas.Get("snap_guides_y").AsGodotArray()){float y=offset.Y+guide.AsSingle()*zoom;canvas.DrawLine(new Vector2(0,y),new Vector2(canvas.Size.X,y),new Color("66e0c1"),1);}
        var selected=canvas.Get("selected").AsGodotArray();if(tool=="move"&&selected.Count>0)
        {
            var bounds=selection_bounds(canvas);var screen=new Rect2(offset+bounds.Position*zoom,bounds.Size*zoom);var outline=ProjectedHandles(canvas,screen);canvas.DrawPolyline(new[]{outline[0],outline[2],outline[4],outline[6],outline[0]},new Color("68e3c7"),1.5f,true);var visibleHandles=handles(canvas,screen);foreach(var value in visibleHandles){var handle=value.AsVector2();canvas.DrawRect(new Rect2(handle-Vector2.One*4,Vector2.One*8),new Color("132a2c"));canvas.DrawRect(new Rect2(handle-Vector2.One*4,Vector2.One*8),new Color("8ff4df"),false,1.5f);}var rotate=rotation_handle(canvas,screen);canvas.DrawLine(visibleHandles[1].AsVector2(),rotate,new Color("68e3c7"),1.5f);canvas.DrawCircle(rotate,4.5f,new Color("8ff4df"));
        }
        if(drag is "rect_select" or "crop" or "shape" or "box" or "pixel_box"){var start=canvas.Get("_start").AsVector2();var dragRect=new Rect2(offset+start*zoom,(canvas.Get("_last").AsVector2()-start)*zoom).Abs();canvas.DrawRect(dragRect,new Color(.03f,.085f,.07f,.1f));canvas.DrawRect(dragRect,new Color("8ff4df"),false,1.5f);}
        var sourcePoints=canvas.Get("_points").AsVector2Array();
        if(tool=="path")
        {
            var points=new Vector2[sourcePoints.Length];for(int i=0;i<points.Length;i++)points[i]=offset+sourcePoints[i]*zoom;var raw=(Vector2[])points.Clone();var shape=_documents.layer_for_id(document,canvas.Get("path_layer_id").AsString());var properties=shape?.Get("properties").AsGodotDictionary()??new Settings();if(shape!=null)points=_layers.rounded_polygon(points,Get(properties,"radius",0).AsDouble()*zoom);var fill=shape!=null?Get(properties,"color",canvas.Get("color")).AsColor():canvas.Get("color").AsColor();fill.R*=fill.A;fill.G*=fill.A;fill.B*=fill.A;
            if(points.Length>2&&(shape==null||Get(properties,"filled",true).AsBool()))DrawPolygon(canvas,points,fill);
            if(points.Length>1){var closed=new Vector2[points.Length+1];Array.Copy(points,closed,points.Length);closed[^1]=points[0];double stroke=shape!=null?Get(properties,"stroke",0).AsDouble():0;canvas.DrawPolyline(closed,stroke>0?Get(properties,"stroke_color",Colors.Black).AsColor():new Color("8ff4df"),(float)Math.Max(1,stroke*zoom),true);}
            foreach(var point in raw){canvas.DrawCircle(point,6,new Color("101720"));canvas.DrawCircle(point,4,new Color("8ff4df"));}var mouse=canvas.Get("_mouse").AsVector2();if(canvas.Get("_polygon_index").AsInt32()<0&&new Rect2(Vector2.Zero,canvas.Size).HasPoint(mouse)){var candidate=offset+snap_polygon_point(canvas,to_document(canvas,mouse),Input.IsKeyPressed(Key.Ctrl))*zoom;canvas.DrawCircle(candidate,6,new Color("101720"));canvas.DrawCircle(candidate,4,new Color("f6ce80"));}
        }
        else if(sourcePoints.Length>1)
        {
            var points=new Vector2[sourcePoints.Length];for(int i=0;i<points.Length;i++)points[i]=offset+sourcePoints[i]*zoom;if((drag is "lasso_crop" or "pixel_lasso")&&points.Length>2)DrawPolygon(canvas,points,new Color(.04f,.14f,.12f,.22f));canvas.DrawPolyline(points,new Color("8ff4df"),1.5f,true);
        }
        if(drag is "shape_stroke" or "stroke_edit")
        {
            var guide=shape_path(canvas);for(int i=0;i<guide.Length;i++)guide[i]=offset+guide[i]*zoom;var tint=canvas.Get("color").AsColor();tint.A*=canvas.Get("brush_opacity").AsSingle();tint.R*=tint.A;tint.G*=tint.A;tint.B*=tint.A;if(guide.Length>1)canvas.DrawPolyline(guide,tint,Math.Max(1,canvas.Get("brush_size").AsSingle()*zoom),true);string mode=canvas.Get("_active_mode").AsString();if(mode!="line"){var shapeHandles=shape_handles(canvas);for(int i=0;i<shapeHandles.Count;i++){var at=shape_screen_handle(canvas,shapeHandles[i].AsVector2());if(mode=="circle"&&(i is 0 or 2 or 4 or 6))canvas.DrawColoredPolygon(new[]{at+new Vector2(0,-7),at+new Vector2(7,0),at+new Vector2(0,7),at+new Vector2(-7,0)},new Color("efb865"));else{canvas.DrawCircle(at,6,new Color("17212d"));canvas.DrawArc(at,6,0,Mathf.Tau,24,new Color("8ff4df"),1.5f,true);}}}if(mode=="curve"){canvas.DrawLine(offset+canvas.Get("_start").AsVector2()*zoom,offset+canvas.Get("_shape_control").AsVector2()*zoom,new Color("749c98"),1,true);canvas.DrawLine(offset+canvas.Get("_shape_control_end").AsVector2()*zoom,offset+canvas.Get("_shape_end").AsVector2()*zoom,new Color("749c98"),1,true);}
        }
        if(tool=="path"&&selected.Count>0){var item=_documents.layer_for_id(document,selected[selected.Count-1].AsString());if(item!=null&&item.Get("kind").AsString()=="path"){var properties=item.Get("properties").AsGodotDictionary();var points=Get(properties,"points",Array.Empty<Vector2>()).AsVector2Array();var dimensions=item.Get("dimensions").AsVector2();var size=Get(properties,"path_size",dimensions).AsVector2().Max(Vector2.One);var world=_documents.world_transform(document,item);foreach(var point in points)canvas.DrawCircle(offset+world*(point*dimensions/size)*zoom,4,new Color("8ff4df"));}}
        var pointer=canvas.Get("_mouse").AsVector2();if((tool is "brush" or "eraser"||tool=="pixel_select"&&(canvas.Get("pixel_mode").AsString() is "brush" or "erase")&&!canvas.Get("pixel_box_select").AsBool())&&new Rect2(Vector2.Zero,canvas.Size).HasPoint(pointer))canvas.DrawArc(pointer,canvas.Get("brush_size").AsSingle()*zoom*.5f,0,Mathf.Tau,48,Colors.White,1,true);
        var edge=canvas.Get("_edge_preview").AsVector2();if(edge!=Vector2.Inf&&tool=="pixel_select"&&canvas.Get("edge_magnet").AsBool()){var at=offset+edge*zoom;canvas.DrawArc(at,Math.Max(3,canvas.Get("brush_size").AsSingle()*zoom*.5f),0,Mathf.Tau,48,new Color("8ff4df"),1.5f,true);canvas.DrawCircle(at,2,new Color("8ff4df"));}
    }
    private static void DrawPolygon(Control canvas,Vector2[] points,Color color){var triangles=Geometry2D.TriangulatePolygon(points);for(int i=0;i<triangles.Length;i+=3)canvas.DrawColoredPolygon(new[]{points[triangles[i]],points[triangles[i+1]],points[triangles[i+2]]},color);}
}
