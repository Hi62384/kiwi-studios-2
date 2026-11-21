using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings=Godot.Collections.Dictionary;

public partial class RigViewportOverlay : RefCounted
{
    private readonly RigViewportGeometry _geometry=new();
    private readonly RigMath _math=new();
    private readonly RigPaintGeometry _paint=new();
    private static readonly Color[] AxisColors={new("f3848c"),new("8bddae"),new("85bdff")};
    private static Vector2 Project(Control canvas,Vector3 point)=>canvas.Call("project",point).AsVector2();
    public void draw(Control canvas,RigEditor editor,RefCounted state)
    {
        if(!editor.enabled) return;var overlay=canvas.Get("overlay").As<Control>();var camera=canvas.Get("camera").As<Camera3D>();var armature=editor.rig();bool compare=state.Get("compare_rest").AsBool();var world=_geometry.world_bones(canvas,editor,compare);var font=ThemeDB.FallbackFont;
        void Text(Vector2 position,string text,Color color)=>overlay.DrawString(font,position,text,HorizontalAlignment.Left,-1,12,color);
        if(armature!=null&&editor.show_bones)
        {
            var bones=armature.Get("bones").AsGodotArray();var chain=new HashSet<int>(bones.Count>0?_math.descendants(armature,editor.selected_bone):Array.Empty<int>());
            for(int i=0;i<world.Count;i++)
            {
                if(editor.only_chain&&!chain.Contains(i)) continue;var bone=bones[i].AsGodotDictionary();Vector3 start=world[i].Origin,end=_math.tail(bone,world[i]);if(camera.IsPositionBehind(start)||camera.IsPositionBehind(end)) continue;
                Vector2 a=Project(canvas,start),b=Project(canvas,end);Color color=new(i==editor.selected_bone?"ffce80":"79dfc5");
                overlay.DrawLine(a,b,new Color("0c1721"),7,true);overlay.DrawLine(a,b,color,3,true);
                foreach(Vector2 point in new[]{a,b}) {overlay.DrawCircle(point,6,new Color("0c1721"));overlay.DrawCircle(point,3.5f,color);}
                if(i==editor.selected_bone)
                {
                    Text(b+new Vector2(8,-8),bone["name"].AsString(),color);
                    if(editor.mode=="Envelope")
                    {
                        Vector3 center=start.Lerp(end,.5f);float pixels=Project(canvas,center+camera.Basis.X*(float)bone["radius"].AsDouble()).DistanceTo(Project(canvas,center));
                        overlay.DrawArc(Project(canvas,center),pixels,0,Mathf.Tau,48,new Color("7bc8ff"),2,true);
                    }
                }
            }
            var geometry=_geometry.handles(canvas,editor,compare);
            if(geometry.Count>0&&editor.mode is "Pose" or "Weight")
            {
                var ends=geometry["ends"].AsVector2Array();var rings=geometry["rings"].AsGodotArray();
                for(int i=0;i<3;i++)
                    if(canvas.Get("tool").AsString()=="Rotate") overlay.DrawPolyline(rings[i].AsVector2Array(),AxisColors[i],2,true);
                    else {overlay.DrawLine(geometry["center"].AsVector2(),ends[i],AxisColors[i],2.5f,true);overlay.DrawCircle(ends[i],5,AxisColors[i]);}
            }
        }
        if(editor.mode=="Draw")
        {
            Vector2 p=Project(canvas,state.Get("cursor").AsVector3());overlay.DrawCircle(p,5,new Color("ffce80"));overlay.DrawArc(p,8,0,Mathf.Tau,24,new Color("0c1721"),2,true);
            if(state.Get("chain").VariantType==Variant.Type.Vector3) overlay.DrawLine(Project(canvas,state.Get("chain").AsVector3()),p,new Color("ffce80"),2,true);
            Text(new Vector2(12,24),"Draw: "+state.Get("construction").AsString()+" · click / release joints · Enter ends chain · RMB cancels point",new Color("ffe0a1"));
        }
        else if(editor.mode=="Weight")
        {
            var handles=_geometry.handles(canvas,editor,compare);float length=handles.TryGetValue("length",out var value)?(float)value.AsDouble():1;
            float radius=(float)state.Get("brush_radius").AsDouble()*75/Mathf.Max(.0001f,length);Vector2 mouse=state.Get("mouse").AsVector2();overlay.DrawArc(mouse,Mathf.Clamp(radius,3,600),0,Mathf.Tau,64,new Color("f3f5ff"),1.5f,true);
            Text(new Vector2(12,24),"Weight: "+state.Get("brush_mode").AsString()+" · Shift+wheel radius · Ctrl subtracts · W/E/R pose handles",new Color("b7e5ff"));
            var document=canvas.Get("session").As<RefCounted>().Get("document").As<Resource>();Transform3D transform=armature==null?Transform3D.Identity:document.Call("world_transform",armature).AsTransform3D();
            var regionGeometry=new Dictionary<string,Vector3[][]>();
            foreach(var pair in state.Get("region").AsGodotDictionary())
            {
                var entry=pair.Value.AsGodotDictionary();string id=entry["id"].AsString();var item=document.Call("component",id).As<Resource>();
                if(item==null||item.Get("binding").As<Resource>()==null||armature==null||item.Get("skeleton_id").AsString()!=armature.Get("id").AsString()) continue;
                if(!regionGeometry.TryGetValue(id,out var surfaces)) {var data=_paint.geometry(item,armature,compare,state.Get("drag").AsString()=="weight",state.Get("geometry_cache").AsGodotDictionary(),state.Get("stroke_geometry").AsGodotDictionary());surfaces=data["points"].AsGodotArray().Select(value=>value.AsVector3Array()).ToArray();regionGeometry[id]=surfaces;}
                int surface=entry["surface"].AsInt32(),vertex=entry["vertex"].AsInt32();if(surface<0||surface>=surfaces.Length) continue;var points=surfaces[surface];if(vertex<0||vertex>=points.Length) continue;
                Vector3 point=transform*points[vertex];if(!camera.IsPositionBehind(point)) overlay.DrawCircle(Project(canvas,point),3,Colors.White);
            }
            if(state.Get("drag").AsString()=="region") {Vector2 start=state.Get("region_start").AsVector2();var rect=new Rect2(start,mouse-start).Abs();overlay.DrawRect(rect,new Color(.3f,.7f,1,.15f));overlay.DrawRect(rect,new Color("9bdcff"),false,1);}
        }
        else Text(new Vector2(12,24),"Rig "+editor.mode+" · drag joints · W/E/R pose tools · Esc cancels · Delete bone",new Color("b7e5ff"));
    }
}
