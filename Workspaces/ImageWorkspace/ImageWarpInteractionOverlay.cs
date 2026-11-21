using Godot;
using System;
using System.Collections.Generic;
public partial class ImageWarpInteractionOperations
{
    public void draw(RefCounted owner)
    {
        var item=layer(owner);if(item==null)return;
        var canvas=Canvas(owner);var context=Context(owner,item);var data=item.Get("warp").As<Resource>();
        string mode=owner.Get("mode").AsString();double diameter=owner.Get("diameter").AsDouble();
        if(mode=="mesh"&&owner.Get("mesh_radius").AsDouble()>0&&canvas.GetGlobalRect().HasPoint(canvas.GetGlobalMousePosition()))
            Ring(65,owner.Get("mesh_radius").AsDouble()*Math.Max(context.Content.X,context.Content.Y),new Color("95e4d0"),1.2f,.75f);
        if(mode=="brush")Ring(49,diameter*.5,new Color("b0f5df"),1.25f,.85f);
        void Ring(int count,double radius,Color color,float width,float alpha)
        {
            var center=context.ScreenUv(canvas.Get("_mouse").AsVector2());var ring=new Vector2[count];
            for(int i=0;i<count;i++){double angle=Math.Tau*i/(count-1);ring[i]=context.Screen(center+new Vector2((float)Math.Cos(angle),(float)Math.Sin(angle))*(float)radius/context.Content);}
            canvas.DrawPolyline(ring,new Color(0,0,0,alpha),3,true);canvas.DrawPolyline(ring,color,width,true);
        }
        if(owner.Get("show_grid").AsBool())
        {
            int resolution=data!=null?data.Get("mesh_resolution").AsInt32():owner.Get("mesh_resolution").AsInt32();
            var points=MeshPoints(data,resolution);var screen=new Vector2[points.Length];ImageWarpKernel? kernel=null;
            if(mode=="brush"&&data!=null){kernel=data.Call("_native").As<ImageWarpKernel>();kernel.rebuild(data);}
            for(int i=0;i<points.Length;i++)screen[i]=context.Screen(kernel!=null?kernel.ForwardCached(new Vector2(i%resolution,i/resolution)/(resolution-1)):points[i]);
            var selected=new HashSet<int>(owner.Get("selected_points").AsInt32Array());
            for(int i=0;i<points.Length;i++)
            {
                if(i%resolution+1<resolution)canvas.DrawLine(screen[i],screen[i+1],new Color(.4f,.9f,.8f,.65f),1,true);
                if(i/resolution+1<resolution)canvas.DrawLine(screen[i],screen[i+resolution],new Color(.4f,.9f,.8f,.65f),1,true);
                if(mode=="mesh"){canvas.DrawCircle(screen[i],5.5f,new Color("101b24"));canvas.DrawCircle(screen[i],3.5f,new Color(selected.Contains(i)?"ffc575":"93e9db"));}
            }
        }
        if(mode=="pins"&&data!=null)
        {
            var pins=data.Get("pins").AsGodotArray();for(int i=0;i<pins.Count;i++)
            {
                var pin=pins[i].AsGodotDictionary();var point=context.Screen(pin["target"].AsVector2());
                canvas.DrawLine(context.Screen(pin["source"].AsVector2()),point,new Color(.7f,.8f,.9f,.5f),1,true);
                canvas.DrawCircle(point,8,new Color("101b24"));canvas.DrawCircle(point,5,Get(pin,"locked",false).AsBool()?new Color("ffc575"):i==owner.Get("selected_pin").AsInt32()?Colors.White:new Color("75e3cb"));
            }
        }
        if(owner.Get("show_freeze").AsBool()&&data!=null)
        {
            var freeze=data.Get("freeze").AsFloat32Array();var size=data.Get("grid_size").AsVector2I();
            for(int i=0;i<freeze.Length;i++)if(freeze[i]>=.02f)canvas.DrawCircle(context.Screen(new Vector2(i%size.X,i/size.X)/(Vector2)(size-Vector2I.One)),(float)Math.Max(2,diameter*context.Zoom*.025),new Color(.3f,.65f,1,freeze[i]*.32f));
        }
    }
}
