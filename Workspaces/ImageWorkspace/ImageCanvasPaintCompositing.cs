using Godot;
using System;
public partial class ImageCanvasSelectionOperations
{
    public void upload_native_paint(Control canvas)
    {
        prepare_source_color(canvas);var stroke=canvas.Get("_stroke_ink").As<Image>();var dirty=canvas.Get("_stroke_dirty").AsRect2I();if(stroke!=null&&dirty.HasArea())
        {
            using var ink=stroke.GetRegion(new Rect2I(dirty.Position-canvas.Get("_ink_origin").AsVector2I(),dirty.Size));var item=canvas.Get("_paint_layer").As<Resource>();var image=canvas.Get("_paint_image").As<Image>();var baseline=canvas.Get("_stroke_base").As<Image>();string tool=canvas.Get("tool").AsString();bool erase=tool=="eraser"||canvas.Get("_erase_modifier").AsBool(),selectedOnly=canvas.Get("paint_selection_only").AsBool();double brushOpacity=canvas.Get("brush_opacity").AsDouble();var selection=new SelectionSampler(canvas);var frame=_documents.world_transform(canvas.Get("document").As<Resource>(),item);var scale=item.Get("dimensions").AsVector2()/(Vector2)image.GetSize();var projection=new ImageLayerProjection(item);Vector2 World(Vector2 p)=>frame*projection.Project(p*scale,new Vector2(-1,-1));
            if(tool=="brush"&&canvas.Get("brush_type").AsString()=="soften"&&!erase)
            {
                var filtered=canvas.Get("_soften_source").As<Image>();if(filtered==null){canvas.Set("_soften_opaque",baseline.DetectAlpha()==Image.AlphaMode.None);filtered=_soften.prepare(baseline,canvas.Get("brush_size").AsDouble()*.08*image.GetWidth()/Math.Max(1,item.Get("dimensions").AsVector2().X));canvas.Set("_soften_source",filtered);}
                using var patch=_soften.Composite(baseline,filtered,ink,dirty,canvas.Get("soften_strength").AsDouble(),brushOpacity,selectedOnly?p=>selection.Coverage(World(p)):null,canvas.Get("_soften_opaque").AsBool());image.BlitRect(patch,new Rect2I(Vector2I.Zero,patch.GetSize()),dirty.Position);canvas.Set("_stroke_dirty",new Rect2I());update_paint_texture(canvas);canvas.QueueRedraw();return;
            }
            if(erase)
            {
                using var source=baseline.GetRegion(dirty);var bytes=source.GetData();var coverage=ink.GetData();for(int y=0;y<dirty.Size.Y;y++)for(int x=0;x<dirty.Size.X;x++){int at=(y*dirty.Size.X+x)*4+3;var point=World((Vector2)(dirty.Position+new Vector2I(x,y)));double alpha=coverage[at]/255.0*brushOpacity*(selectedOnly?selection.Coverage(point):1);bytes[at]=Byte(bytes[at]*(1-alpha));coverage[at]=Byte(alpha*255);}
                using var patch=Image.CreateFromData(dirty.Size.X,dirty.Size.Y,false,Image.Format.Rgba8,bytes);image.BlitRect(patch,new Rect2I(Vector2I.Zero,dirty.Size),dirty.Position);
                if(item.Get("live_paint").AsGodotArray().Count>0){var eraser=canvas.Get("_live_eraser").As<RefCounted>();if(eraser==null){eraser=new ImageLiveEraser();canvas.Set("_live_eraser",eraser);_liveErase.begin(eraser,item,image.GetSize());}using var mask=Image.CreateFromData(ink.GetWidth(),ink.GetHeight(),false,Image.Format.Rgba8,coverage);_liveErase.apply(eraser,dirty,mask);}canvas.Set("_stroke_dirty",new Rect2I());update_paint_texture(canvas);canvas.QueueRedraw();return;
            }
            var region=canvas.Get("_material_region").AsGodotObject();bool masked=region==null&&Get(item.Get("properties").AsGodotDictionary(),"values_selection_only",false).AsBool()&&_values.operations(item).Count>0;var color=canvas.Get("color").AsColor();double opacity=Math.Clamp(brushOpacity*(region!=null?canvas.Get("material_strength").AsDouble():masked?color.A:canvas.Get("_value_inverse_color").AsColor().A),0,1);
            if(opacity<1&&!selectedOnly&&!masked){var bytes=ink.GetData();for(int at=3;at<bytes.Length;at+=4)bytes[at]=Byte(bytes[at]*opacity);ink.SetData(ink.GetWidth(),ink.GetHeight(),false,Image.Format.Rgba8,bytes);}
            else if(selectedOnly||masked)
            {
                var bytes=ink.GetData();var source=new ValueColorSampler(this,canvas,item);for(int y=0;y<ink.GetHeight();y++)for(int x=0;x<ink.GetWidth();x++){int at=(y*ink.GetWidth()+x)*4+3;bytes[at]=Byte(bytes[at]*opacity);if(bytes[at]>0&&masked){var sampled=source.Source(frame*((Vector2)(dirty.Position+new Vector2I(x,y))*scale));bytes[at]=Byte(bytes[at]*sampled.A/Math.Max(.00001,color.A));for(int channel=0;channel<3;channel++)bytes[at-3+channel]=Byte(Math.Clamp(sampled[channel],0,1)*255);}}ink.SetData(ink.GetWidth(),ink.GetHeight(),false,Image.Format.Rgba8,bytes);
            }
            image.BlitRect(baseline,dirty,dirty.Position);image.BlendRect(ink,new Rect2I(Vector2I.Zero,ink.GetSize()),dirty.Position);
            if(selectedOnly)
            {
                using var changedImage=image.GetRegion(dirty);using var originalImage=baseline.GetRegion(dirty);var changed=changedImage.GetData();var original=originalImage.GetData();for(int y=0;y<dirty.Size.Y;y++)for(int x=0;x<dirty.Size.X;x++){double coverage=selection.Coverage(World((Vector2)(dirty.Position+new Vector2I(x,y))));int at=(y*dirty.Size.X+x)*4;for(int channel=0;channel<4;channel++)changed[at+channel]=Byte(original[at+channel]+(changed[at+channel]-original[at+channel])*coverage);}using var patch=Image.CreateFromData(dirty.Size.X,dirty.Size.Y,false,Image.Format.Rgba8,changed);image.BlitRect(patch,new Rect2I(Vector2I.Zero,dirty.Size),dirty.Position);
            }
            canvas.Set("_stroke_dirty",new Rect2I());
        }
        update_paint_texture(canvas);canvas.QueueRedraw();
    }
    public void flood(Control canvas,Vector2 point)
    {
        prepare_source_color(canvas);var item=canvas.Get("_paint_layer").As<Resource>();var image=canvas.Get("_paint_image").As<Image>();var frame=_documents.world_transform(canvas.Get("document").As<Resource>(),item);var ratio=(Vector2)image.GetSize()/item.Get("dimensions").AsVector2();var start=(Vector2I)((frame.AffineInverse()*point)*ratio);if(!new Rect2I(Vector2I.Zero,image.GetSize()).HasPoint(start))return;var detectionImage=canvas.Get("_material_flood_source").As<Image>();bool selectedOnly=canvas.Get("paint_selection_only").AsBool(),erase=canvas.Get("_erase_modifier").AsBool();var source=new ValueColorSampler(this,canvas,item);var selection=new SelectionSampler(canvas);
        if(detectionImage==null&&!selectedOnly&&!Get(item.Get("properties").AsGodotDictionary(),"values_selection_only",false).AsBool()&&image.GetUsedRect().Size==Vector2I.Zero){image.Fill(erase?Colors.Transparent:source.Source(point));canvas.Set("_paint_data",image.GetData());upload_paint(canvas);return;}
        int width=image.GetWidth(),height=image.GetHeight(),startOffset=(start.Y*width+start.X)*4;var data=canvas.Get("_paint_data").AsByteArray();var detection=detectionImage!=null?detectionImage.GetData():(byte[])data.Clone();var target=new byte[4];Array.Copy(detection,startOffset,target,0,4);var color=erase?Colors.Transparent:canvas.Get("color").AsColor();bool same=true;for(int i=0;i<4;i++)if(target[i]!=Byte(color[i]*255)){same=false;break;}if(same)return;
        var visited=new byte[width*height];using var lowerErase=erase&&item.Get("live_paint").AsGodotArray().Count>0?Image.CreateEmpty(width,height,false,Image.Format.Rgba8):null;double threshold=threshold_bytes(canvas.Get("fill_threshold").AsDouble()),limit=threshold*threshold;
        bool Matches(int x,int y){if(x<0||y<0||x>=width||y>=height||visited[y*width+x]!=0)return false;int at=(y*width+x)*4;double difference=0;for(int channel=0;channel<4;channel++){int delta=detection[at+channel]-target[channel];difference+=delta*delta;}return difference<=limit&&(!selectedOnly||selection.Exists&&selection.Coverage(frame*(new Vector2(x,y)/ratio))>0);}
        var stack=new System.Collections.Generic.Stack<Vector2I>();stack.Push(start);while(stack.TryPop(out var at)){if(!Matches(at.X,at.Y))continue;int x=at.X;while(Matches(x-1,at.Y))x--;bool above=false,below=false;while(x<width&&Matches(x,at.Y)){int index=at.Y*width+x;visited[index]=1;int offset=index*4;var world=frame*(new Vector2(x,at.Y)/ratio);var sampled=erase?Colors.Transparent:source.Source(world);double coverage=selectedOnly?selection.Coverage(world):1;for(int channel=0;channel<4;channel++)data[offset+channel]=Byte(data[offset+channel]+(Math.Clamp(sampled[channel],0,1)*255-data[offset+channel])*coverage);lowerErase?.SetPixel(x,at.Y,new Color(1,1,1,(float)coverage));bool up=at.Y>0&&Matches(x,at.Y-1);if(up&&!above)stack.Push(new Vector2I(x,at.Y-1));above=up;bool down=at.Y<height-1&&Matches(x,at.Y+1);if(down&&!below)stack.Push(new Vector2I(x,at.Y+1));below=down;x++;}}
        if(lowerErase!=null)_layers.erase_live_paint(item,lowerErase);canvas.Set("_paint_data",data);upload_paint(canvas);
    }
}
