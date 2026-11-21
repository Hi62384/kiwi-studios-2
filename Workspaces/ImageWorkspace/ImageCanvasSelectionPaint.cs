using Godot;
using System;
using System.Collections.Generic;
public partial class ImageCanvasSelectionOperations
{
    private readonly PixelSelectionAlphaOperations _alpha=new();private readonly PixelEdgeMagnetOperations _magnet=new();
    public void update_pixel_box(Control canvas,Vector2 point)
    {
        var baseline=canvas.Get("_pixel_area_base").As<Image>();if(baseline==null)return;var rect=new Rect2(canvas.Get("_start").AsVector2(),point-canvas.Get("_start").AsVector2()).Abs();var area=new Rect2I((Vector2I)rect.Position.Floor(),(Vector2I)rect.Size.Ceil()).Intersection(canvas.Get("pixel_domain").AsRect2I());var previous=canvas.Get("_pixel_area_previous").AsRect2I();var changed=previous.HasArea()?area.Merge(previous):area;var selection=canvas.Get("selection").As<Image>();if(changed.HasArea())selection.BlitRect(baseline,changed,changed.Position);
        if(area.HasArea()){using var coverage=Image.CreateEmpty(area.Size.X,area.Size.Y,false,Image.Format.Rgba8);coverage.Fill(Colors.White);var feathered=_alpha.feather(coverage,canvas.Get("selection_falloff").AsDouble());using var source=baseline.GetRegion(area);using var blend=_alpha.blend(source,feathered,canvas.Get("selection_alpha").AsDouble(),canvas.Get("_erase_modifier").AsBool()||canvas.Get("pixel_mode").AsString()=="erase",Vector2I.Zero);selection.BlitRect(blend,new Rect2I(Vector2I.Zero,area.Size),area.Position);if(feathered!=coverage)feathered.Dispose();}canvas.Set("_pixel_area_previous",area);update_selection_preview(canvas);
    }
    public void apply_pixel_lasso(Control canvas,bool coverageOnly)
    {
        var points=canvas.Get("_points").AsVector2Array();if(points.Length<3)return;var bounds=new Rect2(points[0],Vector2.Zero);foreach(var point in points)bounds=bounds.Expand(point);var area=new Rect2I((Vector2I)bounds.Position.Floor(),(Vector2I)bounds.Size.Ceil()).Intersection(canvas.Get("pixel_domain").AsRect2I());var tint=coverageOnly||!(canvas.Get("_erase_modifier").AsBool()||canvas.Get("pixel_mode").AsString()=="erase")?Colors.White:Colors.Transparent;var selection=canvas.Get("selection").As<Image>();var intersections=new List<float>(points.Length);
        for(int y=area.Position.Y;y<area.End.Y;y++){intersections.Clear();float line=y+.5f;for(int i=0;i<points.Length;i++){var a=points[i];var b=points[(i+1)%points.Length];if(a.Y<=line&&b.Y>line||b.Y<=line&&a.Y>line)intersections.Add(a.X+(line-a.Y)*(b.X-a.X)/(b.Y-a.Y));}intersections.Sort();for(int i=0;i+1<intersections.Count;i+=2){int left=Math.Max(area.Position.X,Mathf.CeilToInt(intersections[i]-.5f)),right=Math.Min(area.End.X,Mathf.CeilToInt(intersections[i+1]-.5f));if(right>left)selection.FillRect(new Rect2I(left,y,right-left,1),tint);}}
    }
    public void flush_edge_motion(Control canvas){if(!canvas.Get("_edge_motion_pending").AsBool())return;canvas.Set("_edge_motion_pending",false);if(canvas.Get("_drag").AsString()!="pixel_select")return;pixel_brush_line(canvas,canvas.Get("_last").AsVector2(),canvas.Get("_edge_motion_point").AsVector2());canvas.Set("_last",canvas.Get("_edge_motion_point"));update_selection_preview(canvas);}
    public void pixel_brush_line(Control canvas,Vector2 from,Vector2 to)
    {
        if(canvas.Get("edge_magnet").AsBool()&&canvas.Get("pixel_mode").AsString()=="brush"&&!canvas.Get("pixel_box_select").AsBool()){var edges=canvas.Get("smart_selection").AsGodotObject().Get("edges").AsGodotObject();if(edges==null)return;var follower=canvas.Get("_edge_follower").As<RefCounted>();follower.Set("field",edges);var path=_magnet.follow(follower,to,canvas.Get("edge_threshold").AsDouble(),to-from);canvas.Set("_edge_preview",Vector2.Inf);if(path.Length>0){canvas.Set("_edge_preview",path[^1]);pixel_alpha_path(canvas,path);}return;}pixel_alpha_path(canvas,new[]{from,to});
    }
    public void pixel_flood(Control canvas,Vector2I start)
    {
        var selection=canvas.Get("selection").As<Image>();using var coverage=Image.CreateEmpty(selection.GetWidth(),selection.GetHeight(),false,Image.Format.Rgba8);var source=canvas.Get("pixel_source").As<Image>();int width=source.GetWidth();var bytes=source.GetData();int target=(start.Y*width+start.X)*4;var visited=new byte[width*source.GetHeight()];double threshold=threshold_bytes(canvas.Get("fill_threshold").AsDouble()),limit=threshold*threshold;var domain=canvas.Get("pixel_domain").AsRect2I();
        bool Matches(int x,int y){if(!domain.HasPoint(new Vector2I(x,y))||visited[y*width+x]!=0)return false;int offset=(y*width+x)*4;double delta=0;for(int channel=0;channel<4;channel++){int difference=bytes[offset+channel]-bytes[target+channel];delta+=difference*difference;}return delta<=limit;}
        if(canvas.Get("pixel_match_all").AsBool()){for(int y=domain.Position.Y;y<domain.End.Y;y++)for(int x=domain.Position.X;x<domain.End.X;x++)if(Matches(x,y))coverage.SetPixel(x,y,Colors.White);}
        else
        {
            var stack=new Stack<Vector2I>();stack.Push(start);while(stack.TryPop(out var at)){if(!Matches(at.X,at.Y))continue;int left=at.X;while(Matches(left-1,at.Y))left--;int x=left;bool above=false,below=false;while(Matches(x,at.Y)){visited[at.Y*width+x]=1;bool up=Matches(x,at.Y-1),down=Matches(x,at.Y+1);if(up&&!above)stack.Push(new Vector2I(x,at.Y-1));if(down&&!below)stack.Push(new Vector2I(x,at.Y+1));above=up;below=down;x++;}coverage.FillRect(new Rect2I(left,at.Y,x-left,1),Colors.White);}
        }
        var feathered=_alpha.feather(coverage,canvas.Get("selection_falloff").AsDouble());canvas.Set("selection",_alpha.blend(canvas.Get("_pixel_alpha_base").As<Image>(),feathered,canvas.Get("selection_alpha").AsDouble(),canvas.Get("_erase_modifier").AsBool(),Vector2I.Zero));if(feathered!=coverage)feathered.Dispose();
    }
    public void pixel_alpha_path(Control canvas,Vector2[] path)
    {
        var baseline=canvas.Get("_pixel_alpha_base").As<Image>();var ink=canvas.Get("_pixel_alpha_ink").As<Image>();if(baseline==null||ink==null||path.Length==0)return;double brushSize=canvas.Get("brush_size").AsDouble(),falloff=canvas.Get("selection_falloff").AsDouble();string key=brushSize.ToString("R",System.Globalization.CultureInfo.InvariantCulture)+"/"+falloff.ToString("R",System.Globalization.CultureInfo.InvariantCulture);var stamp=canvas.Get("_pixel_alpha_stamp").As<Image>();if(stamp==null||key!=canvas.Get("_pixel_alpha_stamp_key").AsString()){stamp=_alpha.stamp(brushSize,falloff);canvas.Set("_pixel_alpha_stamp",stamp);canvas.Set("_pixel_alpha_stamp_key",key);}var size=stamp.GetSize();var area=new Rect2I();var domain=canvas.Get("pixel_domain").AsRect2I();
        for(int i=0;i<path.Length;i++){var a=path[Math.Max(0,i-1)];var b=path[i];int steps=Math.Max(1,Mathf.CeilToInt(a.DistanceTo(b)/Math.Max(1,brushSize*.2)));for(int step=0;step<=steps;step++){var at=(Vector2I)a.Lerp(b,(float)step/steps)-size/2;ink.BlendRect(stamp,new Rect2I(Vector2I.Zero,size),at);var changed=new Rect2I(at,size).Intersection(domain);if(changed.HasArea())area=area.HasArea()?area.Merge(changed):changed;}}
        _alpha.blend_region(canvas.Get("selection").As<Image>(),baseline,ink,area,canvas.Get("selection_alpha").AsDouble(),canvas.Get("_erase_modifier").AsBool()||canvas.Get("pixel_mode").AsString()=="erase");
    }
}
