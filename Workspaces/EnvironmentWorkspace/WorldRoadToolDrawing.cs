using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;

public partial class WorldRoadTool
{
    public void draw()
    {
        if(canvas==null)return;district_tool.canvas=canvas;district_tool.draw();if(Mode=="District boundary")return;if(Mode=="World regions"){_draw_regions();return;}if(Mode is not ("Draw road" or "Road points")){if(_drag.Count>0||_first.VariantType!=Variant.Type.Nil)cancel();return;}var info=target();if(info.Count==0)return;if(_world_id!=info["id"].AsString()){cancel();_world_id=info["id"].AsString();}var source=info["source"].As<Resource>();if(_drag.Count>0&&InvalidDrag(source))cancel();var roads=source.Get("roads").AsGodotArray();var pose=info["pose"].AsTransform3D();
        for(int road=0;road<roads.Count;road++)
        {
            var entry=roads[road].AsGodotDictionary();var points=entry["points"].AsVector3Array();var line=new List<Vector2>();if(_drag.Count>0&&road==road_index){points[point_index]=_drag["point"].AsVector3();_draw_strip(info,points,entry["width"].AsDouble());}
            for(int index=0;index<points.Length;index++){var point=_drag.Count>0&&road==road_index&&index==point_index?_drag["point"].AsVector3():points[index];var world=pose*point;if(Camera.IsPositionBehind(world)){line.Clear();continue;}var screen=Project(world);line.Add(screen);Overlay.DrawCircle(screen,6,new Color("10242f"));Overlay.DrawCircle(screen,4,new Color(road==road_index&&index==point_index?"ffc678":"75dfc5"));}if(line.Count>1)Overlay.DrawPolyline(line.ToArray(),new Color("75dfc5"),2,true);
        }
        if(_first.VariantType==Variant.Type.Vector3){var first=_first.AsVector3();var point=pose*first;if(!Camera.IsPositionBehind(point))Overlay.DrawCircle(Project(point),5,new Color("ffc678"));if(_hover.VariantType==Variant.Type.Vector3&&_hover.AsVector3().DistanceTo(first)>.05){_draw_strip(info,new[]{first,_hover.AsVector3()},6);var end=pose*_hover.AsVector3();if(!Camera.IsPositionBehind(end))Overlay.DrawCircle(Project(end),5,new Color("ffc678"));}}
    }
    public void _draw_strip(Settings info,Vector3[] points,double width)
    {
        var strip=_geometry.Strip(_geometry.sample(points,2),width,0,new Settings());var projected=new Vector2[strip.Points.Count];var valid=new bool[strip.Points.Count];var pose=info["pose"].AsTransform3D();for(int index=0;index<strip.Points.Count;index++){var world=pose*strip.Points[index];projected[index]=Project(world);valid[index]=!Camera.IsPositionBehind(world);}foreach(var face in strip.Faces){var polygon=new Vector2[face.Length];bool visible=true;for(int index=0;index<face.Length;index++){polygon[index]=projected[face[index]];visible&=valid[face[index]];}if(!visible)continue;Overlay.DrawColoredPolygon(polygon,new Color(.99f,.75f,.4f,.22f));Overlay.DrawLine(polygon[0],polygon[1],new Color("ffc678"),1.5f,true);Overlay.DrawLine(polygon[2],polygon[3],new Color("ffc678"),1.5f,true);}
    }
    public void _draw_regions()
    {
        var info=target();if(info.Count==0)return;var pose=info["pose"].AsTransform3D();foreach(var value in info["source"].As<Resource>().Get("regions").AsGodotArray())
        {
            var region=value.AsGodotDictionary();var bounds=region["bounds"].AsRect2();var corners=new[]{bounds.Position,new Vector2(bounds.End.X,bounds.Position.Y),bounds.End,new Vector2(bounds.Position.X,bounds.End.Y)};var color=new Color(Get(region,"locked",false).AsBool()?"ffc678":Get(region,"enabled",true).AsBool()?"75dfc5":"6e7e88");for(int edge=0;edge<4;edge++){var first=corners[edge];var last=corners[(edge+1)%4];var a=pose*new Vector3(first.X,.05f,first.Y);var b=pose*new Vector3(last.X,.05f,last.Y);if(!Camera.IsPositionBehind(a)&&!Camera.IsPositionBehind(b))Overlay.DrawLine(Project(a),Project(b),color,1.5f,true);}var center=bounds.GetCenter();var world=pose*new Vector3(center.X,.05f,center.Y);if(!Camera.IsPositionBehind(world))Overlay.DrawString(Owner.GetThemeDefaultFont(),Project(world)+new Vector2(4,-6),Get(region,"name","Region").AsString(),HorizontalAlignment.Left,-1,13,color);
        }
    }
}
