using Godot;
using System;
using GArray=Godot.Collections.Array;
public partial class ImageCanvasSelectionOperations
{
    public Vector2[] shape_path(Control canvas)
    {
        string mode=canvas.Get("_active_mode").AsString();var start=canvas.Get("_start").AsVector2();var end=canvas.Get("_shape_end").AsVector2();if(mode=="line")return new[]{start,end};double spacing=Math.Max(2,canvas.Get("brush_size").AsDouble()*.2);Vector2[] points;
        if(mode=="circle"){var center=(start+end)*.5f;var radius=(end-start).Abs()*.5f;int count=Math.Clamp(Mathf.CeilToInt(Math.Tau*Math.Max(radius.X,radius.Y)/spacing),24,256);points=new Vector2[count+1];var profiles=canvas.Get("_circle_profiles").AsVector4();for(int i=0;i<=count;i++){double angle=Math.Tau*i/count,power=2/profiles[Math.Min(3,(int)Math.Floor(angle/(Math.PI*.5)))];double x=Math.Cos(angle),y=Math.Sin(angle);points[i]=center+new Vector2((float)(Math.Sign(x)*Math.Pow(Math.Abs(x),power)),(float)(Math.Sign(y)*Math.Pow(Math.Abs(y),power)))*radius;}}
        else{var control=canvas.Get("_shape_control").AsVector2();var controlEnd=canvas.Get("_shape_control_end").AsVector2();int count=Math.Clamp(Mathf.CeilToInt((start.DistanceTo(control)+control.DistanceTo(end))/spacing),8,256);points=new Vector2[count+1];for(int i=0;i<=count;i++){float t=(float)i/count,u=1-t;points[i]=start*u*u*u+control*3*u*u*t+controlEnd*3*u*t*t+end*t*t*t;}}return points;
    }
    public GArray shape_handles(Control canvas)
    {
        string mode=canvas.Get("_active_mode").AsString();if(mode=="line")return new GArray();var start=canvas.Get("_start").AsVector2();var end=canvas.Get("_shape_end").AsVector2();if(mode=="curve")return new GArray{start,end,canvas.Get("_shape_control"),canvas.Get("_shape_control_end"),(start+end)*.5f};var rect=new Rect2(start,end-start).Abs();var center=rect.GetCenter();var radius=rect.Size*.5f;var profile=canvas.Get("_circle_profiles").AsVector4();return new GArray{center-radius*(float)Math.Pow(.5,1/profile.Z),new Vector2(center.X,rect.Position.Y),center+new Vector2(1,-1)*radius*(float)Math.Pow(.5,1/profile.W),new Vector2(rect.End.X,center.Y),center+radius*(float)Math.Pow(.5,1/profile.X),new Vector2(center.X,rect.End.Y),center+new Vector2(-1,1)*radius*(float)Math.Pow(.5,1/profile.Y),new Vector2(rect.Position.X,center.Y),center};
    }
    public Vector2 shape_screen_handle(Control canvas,Vector2 point)=>(origin(canvas)+point*canvas.Get("zoom").AsSingle()).Clamp(Vector2.One*12,(canvas.Size-Vector2.One*12).Max(Vector2.One*12));
    public Vector2 constrain_shape_point(Control canvas,Vector2 point,bool constrained){if(canvas.Get("_active_mode").AsString()!="circle"||!constrained)return point;var start=canvas.Get("_start").AsVector2();var delta=point-start;float diameter=Math.Max(Math.Abs(delta.X),Math.Abs(delta.Y));return start+new Vector2(delta.X<0?-diameter:diameter,delta.Y<0?-diameter:diameter);}
    public void move_shape_handle(Control canvas,Vector2 point,bool constrained)
    {
        int handle=canvas.Get("_shape_handle").AsInt32();if(handle<0)return;string mode=canvas.Get("_active_mode").AsString();var start=canvas.Get("_start").AsVector2();var end=canvas.Get("_shape_end").AsVector2();var control=canvas.Get("_shape_control").AsVector2();var controlEnd=canvas.Get("_shape_control_end").AsVector2();
        if(handle==(mode=="curve"?4:8)){var delta=point-(start+end)*.5f;start+=delta;end+=delta;control+=delta;controlEnd+=delta;}
        else if(mode=="curve"){switch(handle){case 0:control+=point-start;start=point;break;case 1:controlEnd+=point-end;end=point;break;case 2:control=point;break;case 3:controlEnd=point;break;}}
        else
        {
            var rect=new Rect2(start,end-start).Abs();start=rect.Position;end=rect.End;canvas.Set("_start",start);canvas.Set("_shape_end",end);
            if(handle is 0 or 2 or 4 or 6){var relative=(point-rect.GetCenter()).Abs()/(rect.Size*.5f).Max(Vector2.One);double fraction=Math.Clamp((relative.X+relative.Y)*.5,.18,.94);var profiles=canvas.Get("_circle_profiles").AsVector4();profiles[new[]{2,3,0,1}[handle/2]]=(float)Math.Clamp(Math.Log(.5)/Math.Log(fraction),.4,12);canvas.Set("_circle_profiles",profiles);return;}
            if(handle is 0 or 6 or 7)start.X=point.X;if(handle is 0 or 1 or 2)start.Y=point.Y;if(handle is 2 or 3 or 4)end.X=point.X;if(handle is 4 or 5 or 6)end.Y=point.Y;canvas.Set("_start",start);end=constrain_shape_point(canvas,end,constrained);
        }
        canvas.Set("_start",start);canvas.Set("_shape_end",end);canvas.Set("_shape_control",control);canvas.Set("_shape_control_end",controlEnd);
    }
}
