using Godot;
using System;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class TransformationRendererOperations : RefCounted
{
    private static GodotObject Artwork(Resource state)=>state.Get("artwork").AsGodotObject();
    public void ready(Node owner,string code){var shader=owner.Get("shader").As<Shader>();shader.Code=code;var viewport=owner.Get("viewport").As<SubViewport>();viewport.Disable3D=true;viewport.World2D=new World2D();viewport.TransparentBg=true;viewport.RenderTargetUpdateMode=SubViewport.UpdateMode.Always;owner.AddChild(viewport);owner.AddChild(owner.Get("cache").As<Node>());}
    public void clear_views(Node owner){var views=owner.Get("views").AsGodotDictionary();foreach(var value in views.Values)value.AsGodotDictionary()["node"].As<Node>().Free();views.Clear();owner.Get("cache").AsGodotObject().Get("requests").AsGodotArray().Clear();owner.Set("status","");}
    public Settings transform_at(Resource first,Resource last,double time,int turns)
    {
        float t=(float)time;var a=Artwork(first);var b=Artwork(last);var dimensions=a.Get("dimensions").AsVector2().Lerp(b.Get("dimensions").AsVector2(),t);var pivot=first.Get("pivot").AsVector2().Lerp(last.Get("pivot").AsVector2(),t);float rotationA=a.Get("rotation").AsSingle(),rotationB=b.Get("rotation").AsSingle(),rotation=rotationA+(Mathf.Wrap(rotationB-rotationA,-Mathf.Pi,Mathf.Pi)+turns*Mathf.Tau)*t;var anchor=first.Call("anchor").AsVector2().Lerp(last.Call("anchor").AsVector2(),t);var frameA=a.Call("local_transform").AsTransform2D();var frameB=b.Call("local_transform").AsTransform2D();var residualA=new Transform2D(rotationA,Vector2.Zero).AffineInverse()*new Transform2D(frameA.X,frameA.Y,Vector2.Zero);var residualB=new Transform2D(rotationB,Vector2.Zero).AffineInverse()*new Transform2D(frameB.X,frameB.Y,Vector2.Zero);var basis=new Transform2D(rotation,Vector2.Zero)*new Transform2D(residualA.X.Lerp(residualB.X,t),residualA.Y.Lerp(residualB.Y,t),Vector2.Zero);basis.Origin=anchor-(basis.X*(dimensions*pivot).X+basis.Y*(dimensions*pivot).Y);double opacityA=a.Get("visible").AsBool()?a.Get("opacity").AsDouble():0,opacityB=b.Get("visible").AsBool()?b.Get("opacity").AsDouble():0;return new Settings {["transform"]=basis,["dimensions"]=dimensions,["opacity"]=Mathf.Lerp(opacityA,opacityB,time)};
    }
    public ArrayMesh mesh_for(Settings mapping,Vector2 extent)
    {
        var first=mapping["uv_a"].AsVector2Array();var last=mapping["uv_b"].AsVector2Array();var positions=new Vector3[first.Length];var colors=new Color[first.Length];for(int index=0;index<first.Length;index++){var uv=first[index];var target=last[index];positions[index]=new Vector3(uv.X*extent.X,uv.Y*extent.Y,0);var hi=(target*255).Floor()/255;var lo=(target-hi)*255;colors[index]=new Color(hi.X,hi.Y,lo.X,lo.Y);}var arrays=new GArray();arrays.Resize((int)Mesh.ArrayType.Max);arrays[(int)Mesh.ArrayType.Vertex]=positions;arrays[(int)Mesh.ArrayType.Color]=colors;arrays[(int)Mesh.ArrayType.TexUV]=first;arrays[(int)Mesh.ArrayType.Index]=mapping["indices"];var mesh=new ArrayMesh();mesh.AddSurfaceFromArrays(Mesh.PrimitiveType.Triangles,arrays);return mesh;
    }
    public Settings evaluate_events(Resource document,string id,double time)
    {
        bool visible=true;var masks=new Godot.Collections.Array<Texture2D>();foreach(var raw in document.Get("component_events").AsGodotArray()){var item=raw.AsGodotDictionary();double at=item["time"].AsDouble();if(item["target"].AsString()==id&&time<at)visible=false;if(time>=at&&Array.IndexOf(item["sources"].AsStringArray(),id)>=0){if(item["kind"].AsString()=="Merge")visible=false;else if(masks.Count<4)masks.Add(item["mask"].As<Texture2D>());}}return new Settings {["visible"]=visible,["masks"]=masks};
    }
}
