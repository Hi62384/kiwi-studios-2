using Godot;
using System;
using System.Linq;
using System.Collections.Generic;
using System.Globalization;
using Settings=Godot.Collections.Dictionary;

public partial class ModelViewportOverlay : RefCounted
{
    private sealed class Data
    {
        public long FaceKey=-1,PointKey=-1;
        public int[][] Faces=Array.Empty<int[]>();
        public Vector3[] Points=Array.Empty<Vector3>(),Normals=Array.Empty<Vector3>(),Centers=Array.Empty<Vector3>();
        public List<ModelGeometryOperations.Edge> Edges=new();
        public bool MathReady;
        public void EnsureMath()
        {
            if(MathReady)return;Normals=new Vector3[Faces.Length];Centers=new Vector3[Faces.Length];
            for(int f=0;f<Faces.Length;f++)
            {if(Faces[f].Any(index=>index<0||index>=Points.Length))continue;Normals[f]=ModelGeometryOperations.Normal(Points,Faces[f]);Vector3 center=Vector3.Zero;foreach(int index in Faces[f])center+=Points[index];Centers[f]=center/Math.Max(1,Faces[f].Length);}MathReady=true;
        }
    }
    private readonly Dictionary<ulong,Data> _cache=new();
    private readonly HashSet<ulong> _live=new();
    private static readonly Color[] AxisColors={new("f3848c"),new("8bddae"),new("85bdff")};
    private Data Acquire(Resource mesh)
    {
        ulong id=mesh.GetInstanceId();_live.Add(id);if(!_cache.TryGetValue(id,out var data)){data=new();_cache[id]=data;}
        Variant faces=mesh.Get("faces"),points=mesh.Get("vertices");long faceKey=GD.Hash(faces),pointKey=GD.Hash(points);
        if(faceKey!=data.FaceKey){data.Faces=faces.AsGodotArray().Select(value=>value.AsInt32Array()).ToArray();data.Edges=ModelGeometryOperations.Edges(data.Faces);data.FaceKey=faceKey;data.MathReady=false;}
        if(pointKey!=data.PointKey){data.Points=points.AsVector3Array();data.PointKey=pointKey;data.MathReady=false;}return data;
    }
    public void draw(Control canvas)
    {
        var session=canvas.Get("session").As<RefCounted>();if(session==null){_cache.Clear();return;}
        var groom=canvas.Get("groom_tool").As<RefCounted>();if(groom!=null&&groom.Call("active").AsBool()){_cache.Clear();groom.Call("draw");return;}
        var rig=canvas.Get("rig_tool").As<RefCounted>();var rigEditor=rig?.Get("editor").As<RefCounted>()?.Get("_native").As<RigEditor>();if(rigEditor?.enabled==true){_cache.Clear();rig!.Call("draw");return;}
        var overlay=canvas.Get("overlay").As<Control>();var camera=canvas.Get("camera").As<Camera3D>();Vector2 scale=canvas.Size/(Vector2)canvas.Get("viewport").As<SubViewport>().Size;
        Vector2 Project(Vector3 point)=>camera.UnprojectPosition(point)*scale;
        var document=session.Get("document").As<Resource>();var lookup=ModelDocumentOperations.Lookup(document);var selectedIds=new HashSet<string>(session.Get("selected").AsGodotArray<string>());var primary=session.Call("primary").As<Resource>();string mode=session.Get("mode").AsString();int[] elements=session.Get("elements").AsInt32Array();var elementSet=new HashSet<int>(elements);var evaluated=canvas.Get("evaluated").AsGodotDictionary();
        bool xray=canvas.Get("xray").AsBool(),wireframe=canvas.Get("wireframe").AsBool(),showEdges=canvas.Get("show_edges").AsBool(),showNormals=canvas.Get("show_normals").AsBool();_live.Clear();
        foreach(var item in lookup.Values)
        {
            var authored=item.Get("mesh").As<Resource>();if(authored==null||!ModelDocumentOperations.Accessible(lookup,item,false))continue;string id=item.Get("id").AsString();bool selected=selectedIds.Contains(id),isPrimary=item==primary;
            if(!selected&&!isPrimary&&!showEdges&&!wireframe)continue;Transform3D transform=ModelDocumentOperations.WorldTransform(lookup,item);var mesh=evaluated.TryGetValue(id,out var found)?found.As<Resource>():authored;var data=Acquire(mesh);Basis normalBasis=transform.Basis.Inverse().Transposed();
            var world=new Vector3[data.Points.Length];var screen=new Vector2[world.Length];var behind=new bool[world.Length];for(int i=0;i<world.Length;i++){world[i]=transform*data.Points[i];screen[i]=Project(world[i]);behind[i]=camera.IsPositionBehind(world[i]);}
            var front=new bool[data.Faces.Length];if(!xray&&!wireframe){data.EnsureMath();for(int f=0;f<front.Length;f++)front[f]=(normalBasis*data.Normals[f]).Dot(camera.Position-transform*data.Centers[f])>0;}
            if(showEdges||wireframe||selected)
            {
                var lines=new List<Vector2>();foreach(var edge in data.Edges)
                {
                    if(edge.A<0||edge.B<0||edge.A>=screen.Length||edge.B>=screen.Length||behind[edge.A]||behind[edge.B])continue;
                    if(!xray&&!wireframe){bool facing=false;foreach(int f in edge.Faces)if(f>=0&&f<front.Length&&front[f]){facing=true;break;}if(!facing)continue;}
                    lines.Add(screen[edge.A]);lines.Add(screen[edge.B]);
                }
                if(lines.Count>0)overlay.DrawMultiline(lines.ToArray(),selected?new Color(isPrimary?"e8b86f":"83bdf0"):new Color(.5f,.65f,.75f,.3f),selected?1.2f:.6f,true);
            }
            if(!isPrimary)continue;
            if(mode!="Object"||showNormals)
            {
                var source=Acquire(authored);source.EnsureMath();var sourceWorld=new Vector3[source.Points.Length];var projected=new Vector2[source.Points.Length];for(int i=0;i<sourceWorld.Length;i++){sourceWorld[i]=transform*source.Points[i];projected[i]=Project(sourceWorld[i]);}
                if(mode=="Face")foreach(int f in elements)
                {
                    if(f<0||f>=source.Faces.Length||(!xray&&(normalBasis*source.Normals[f]).Dot(camera.Position-transform*source.Centers[f])<=0))continue;
                    if(source.Faces[f].Any(index=>index<0||index>=projected.Length))continue;var polygon=source.Faces[f].Select(index=>projected[index]).ToArray();if(polygon.Length>=3&&Geometry2D.TriangulatePolygon(polygon).Length>0)overlay.DrawColoredPolygon(polygon,new Color(1,.65f,.25f,.32f));
                }
                else if(mode=="Vertex"){for(int i=0;i<sourceWorld.Length;i++)if(!camera.IsPositionBehind(sourceWorld[i]))overlay.DrawCircle(projected[i],elementSet.Contains(i)?4:2.5f,new Color(elementSet.Contains(i)?"ffcf83":"91b0c5"));}
                else if(mode=="Edge")
                {
                    var lines=new List<Vector2>();foreach(int index in elements)if(index>=0&&index<source.Edges.Count){var edge=source.Edges[index];if(edge.A>=0&&edge.B>=0&&edge.A<projected.Length&&edge.B<projected.Length){lines.Add(projected[edge.A]);lines.Add(projected[edge.B]);}}if(lines.Count>0)overlay.DrawMultiline(lines.ToArray(),new Color("ffce80"),3,true);
                }
                if(showNormals){var lines=new List<Vector2>();for(int f=0;f<source.Faces.Length;f++){Vector3 point=transform*source.Centers[f];lines.Add(Project(point));lines.Add(Project(point+transform.Basis*source.Normals[f]*.15f));}if(lines.Count>0)overlay.DrawMultiline(lines.ToArray(),new Color("85ccf1"),1,true);}
            }
        }
        foreach(ulong id in _cache.Keys.ToArray())if(!_live.Contains(id))_cache.Remove(id);draw_handles_and_navigation(canvas,"");
    }
    public void draw_handles_and_navigation(Control canvas,string customHint)
    {
        var overlay=canvas.Get("overlay").As<Control>();var camera=canvas.Get("camera").As<Camera3D>();var data=canvas.Call("geometry").AsGodotDictionary();string tool=canvas.Get("tool").AsString();var font=ThemeDB.FallbackFont;
        void Text(Vector2 p,string text,int size,Color color,float width=-1)=>overlay.DrawString(font,p,text,HorizontalAlignment.Left,width,size,color);
        if(data.Count>0)
        {
            Vector2 center=data["center"].AsVector2();var ends=data["ends"].AsVector2Array();var rings=data["rings"].AsGodotArray();
            for(int i=0;i<3;i++)
            {
                if(tool=="Rotate")overlay.DrawPolyline(rings[i].AsVector2Array(),AxisColors[i],2,true);
                else if(center.DistanceTo(ends[i])>15)
                {
                    overlay.DrawLine(center,ends[i],new Color("0b1520"),5,true);overlay.DrawLine(center,ends[i],AxisColors[i],2.4f,true);
                    if(tool=="Scale")overlay.DrawRect(new Rect2(ends[i]-new Vector2(5,5),new Vector2(10,10)),AxisColors[i]);
                    else{Vector2 direction=(ends[i]-center).Normalized(),side=direction.Orthogonal(),tip=ends[i];overlay.DrawColoredPolygon(new[]{tip+direction*4,tip-direction*9+side*5,tip-direction*9-side*5},AxisColors[i]);}
                    Text(ends[i]+new Vector2(7,-4),new[]{"X","Y","Z"}[i],12,AxisColors[i]);
                }
            }
            if(tool!="Rotate")overlay.DrawRect(new Rect2(center-new Vector2(5,5),new Vector2(10,10)),new Color("ffe1a0"));
        }
        Vector2 mouse=canvas.Get("_mouse").AsVector2();if(canvas.Get("_box").AsBool()){Vector2 start=canvas.Get("_start").AsVector2();var rect=new Rect2(start,mouse-start).Abs();overlay.DrawRect(rect,new Color(.3f,.8f,.7f,.12f));overlay.DrawRect(rect,new Color("76e2c2"),false,1);}
        Vector2 compass=new(canvas.Size.X-42,38);var axes=new[]{Vector3.Right,Vector3.Up,Vector3.Back};for(int i=0;i<3;i++){Vector3 direction=camera.Basis.Inverse()*axes[i];Vector2 end=compass+new Vector2(direction.X,-direction.Y)*22;overlay.DrawLine(compass,end,AxisColors[i],2,true);overlay.DrawCircle(end,3,AxisColors[i]);Text(end+new Vector2(4,-4),new[]{"X","Y","Z"}[i],11,AxisColors[i]);}
        if(canvas.Get("sculpt").AsString().Length>0)
        {
            var hit=canvas.Call("pick",mouse).AsGodotDictionary();if(hit.Count>0){Vector2 scale=canvas.Size/(Vector2)canvas.Get("viewport").As<SubViewport>().Size;Vector3 point=hit["point"].AsVector3();float radius=(camera.UnprojectPosition(point+camera.Basis.X*(float)canvas.Get("radius").AsDouble())*scale).DistanceTo(camera.UnprojectPosition(point)*scale);overlay.DrawArc(mouse,radius,0,Mathf.Tau,64,new Color("84e6ca"),1.5f,true);}
        }
        string hint=customHint.Length>0?customHint:"RMB fly · MMB orbit · Shift+MMB pan · Wheel zoom · F frame · 1–4 selection · W/E/R transform";
        if(canvas.Get("_drag").AsBool())hint=tool+"  "+canvas.Get("_numeric").AsString()+"  · X/Y/Z constrain · Shift+axis plane · Ctrl snap · Enter confirm · Esc cancel";
        else if(canvas.Get("_extruding").AsBool())hint="Push/pull "+canvas.Get("_extrude_amount").AsDouble().ToString("F3",CultureInfo.InvariantCulture)+" · Type a distance · Ctrl snap · Enter confirm · Esc cancel";
        else if(canvas.Get("_create_phase").AsInt32()>0)hint="Drag footprint, release, then set height · Click confirms · Esc cancels";
        Text(new Vector2(12,canvas.Size.Y-14),hint,11,new Color("91acbc"),canvas.Size.X-24);
    }
}
