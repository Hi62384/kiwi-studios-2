using Godot;
using System;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;
using Topology=ModelGeometryOperations.Topology;

public partial class ArchitecturalComponentOperations : RefCounted
{
    private static readonly string[] Types={"Wall segment","Wall corner","Column","Pillar","Beam","Door","Window","Stairs","Railing","Floor","Roof section","Arch","Balcony","Porch","Foundation","Decorative trim"};
    private readonly BuildingGeometryOperations _buildings=new();
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private static string Kind(string kind)=>kind.Split(" / ").ElementAtOrDefault(1)??"";
    public GArray kinds()=>new(Types.Select(type=>Variant.From("Architecture / "+type)));
    public bool accepts(string kind)=>kind.StartsWith("Architecture / ",StringComparison.Ordinal)&&Types.Contains(Kind(kind));
    public Settings defaults(string kind)
    {
        string name=Kind(kind);return new Settings {["length"]=name is "Wall segment" or "Stairs" or "Railing" or "Beam" or "Floor" or "Roof section"?4.0:2.0,["height"]=name is "Wall segment" or "Wall corner" or "Column" or "Pillar" or "Stairs"?3.0:name is "Door" or "Window" or "Arch"?2.2:name=="Railing"?1.0:.2,["width"]=name is "Column" or "Pillar"?.4:1.2,["depth"]=.2,["trim"]=.07,["spacing"]=.6,["rails"]=2,["steps"]=16,["shape"]=0,["base"]=.1,["capital"]=.12,["angle"]=0.0,["architectural_component"]=name,["architecture_type"]="architectural component"};
    }
    public Settings normalize(Settings parameters)
    {
        var result=parameters.Duplicate(true);foreach(string key in new[]{"length","height","width","depth","trim","spacing","base","capital","angle"}){double value=Get(result,key,0.0).AsDouble();if(!double.IsFinite(value))value=0;result[key]=key=="angle"?Math.Clamp(value,-170,170):Math.Clamp(value,key is "base" or "capital"?0:.02,50);}double width=Math.Clamp(result["width"].AsDouble(),.1,10),height=Math.Clamp(result["height"].AsDouble(),.05,20);result["width"]=width;result["height"]=height;result["length"]=Math.Clamp(result["length"].AsDouble(),.1,50);result["depth"]=Math.Clamp(result["depth"].AsDouble(),.02,2);result["base"]=Math.Clamp(result["base"].AsDouble(),0,height*.25);result["capital"]=Math.Clamp(result["capital"].AsDouble(),0,height*.25);result["trim"]=Math.Clamp(result["trim"].AsDouble(),.01,Math.Min(width,height)*.3);result["shape"]=Math.Clamp(Get(result,"shape",0).AsInt32(),0,2);result["steps"]=Math.Clamp(Get(result,"steps",16).AsInt32(),2,80);result["rails"]=Math.Clamp(Get(result,"rails",2).AsInt32(),1,6);return result;
    }
    private static void Box(Topology target,Vector3 size,Vector3 center,int material=0)=>target.Append(ModelPrimitives.Box(size.Max(Vector3.One*.005f)),new Transform3D(Basis.Identity,center),material);
    private static void Railing(Topology target,float length,float height,float depth,float spacing,int rails)
    {int posts=Math.Clamp(Mathf.CeilToInt(length/Math.Max(.1f,spacing)),1,128);for(int index=0;index<=posts;index++)Box(target,new Vector3(depth,height,depth),new Vector3(-length*.5f+length*index/posts,height*.5f,0));int count=Math.Clamp(rails,1,6);for(int rail=0;rail<count;rail++)Box(target,new Vector3(length,depth,depth),new Vector3(0,height*(rail+1)/count,0));}
    private static void Assign(Resource target,Topology mesh)
    {target.Set("vertices",mesh.Points.ToArray());target.Set("faces",new Godot.Collections.Array<int[]>(mesh.Faces));target.Set("uv",new Godot.Collections.Array<Vector2[]>(mesh.Uv));target.Set("materials",mesh.Materials.ToArray());}
    public void box(Resource target,Vector3 size,Vector3 center,int material){var mesh=new Topology(new ModelMeshOperations.Snapshot(target));Box(mesh,size,center,material);Assign(target,mesh);}
    public void railing(Resource target,double length,double height,double depth,double spacing,int rails){var mesh=new Topology(new ModelMeshOperations.Snapshot(target));Railing(mesh,(float)length,(float)height,(float)depth,(float)spacing,rails);Assign(target,mesh);}
    public Resource generate(string kind,Settings p)
    {
        var mesh=new Topology();string name=Kind(kind);float length=(float)Math.Clamp(Get(p,"length",2.0).AsDouble(),.1,50),height=(float)Math.Clamp(Get(p,"height",2.0).AsDouble(),.05,20),width=(float)Math.Clamp(Get(p,"width",1.2).AsDouble(),.1,10),depth=(float)Math.Clamp(Get(p,"depth",.2).AsDouble(),.02,2);
        switch(name)
        {
            case "Column":case "Pillar":
                float radius=width*.5f,baseHeight=(float)Math.Clamp(Get(p,"base",.1).AsDouble(),0,height*.25),capital=(float)Math.Clamp(Get(p,"capital",.12).AsDouble(),0,height*.25),body=height-baseHeight-capital;int shape=Get(p,"shape",0).AsInt32();if(shape==1)Box(mesh,new Vector3(width,body,width),Vector3.Up*(baseHeight+body*.5f));else{using var primitives=new ModelPrimitives();using var cylinder=primitives.create("Cylinder",new Settings {["radius"]=radius,["height"]=body,["segments"]=shape==2?8:24});mesh.Append(new Topology(new ModelMeshOperations.Snapshot(cylinder)),new Transform3D(Basis.Identity,Vector3.Up*(baseHeight+body*.5f)));}if(baseHeight>0)Box(mesh,new Vector3(width*1.3f,baseHeight,width*1.3f),Vector3.Up*baseHeight*.5f);if(capital>0)Box(mesh,new Vector3(width*1.4f,capital,width*1.4f),Vector3.Up*(height-capital*.5f));break;
            case "Wall segment":Box(mesh,new Vector3(length,height,depth),new Vector3(length*.5f,height*.5f,0));break;
            case "Wall corner":Box(mesh,new Vector3(length,height,depth),new Vector3(length*.5f,height*.5f,0));Box(mesh,new Vector3(depth,height,length),new Vector3(0,height*.5f,length*.5f));break;
            case "Door":case "Window":float trim=(float)Math.Clamp(Get(p,"trim",.07).AsDouble(),.01,Math.Min(width,height)*.3);foreach(float x in new[]{-1f,1f})Box(mesh,new Vector3(trim,height,depth),new Vector3(x*(width-trim)*.5f,height*.5f,0));Box(mesh,new Vector3(width,trim,depth),new Vector3(0,height-trim*.5f,0));if(name=="Window")Box(mesh,new Vector3(width,trim,depth),new Vector3(0,trim*.5f,0));break;
            case "Railing":Railing(mesh,length,height,depth,(float)Get(p,"spacing",.6).AsDouble(),Get(p,"rails",2).AsInt32());break;
            case "Stairs":int steps=Math.Clamp(Get(p,"steps",16).AsInt32(),2,80);for(int step=0;step<steps;step++){float y=height*(step+1)/steps;Box(mesh,new Vector3(width,y,length/steps),new Vector3(0,y*.5f,(step+.5f)*length/steps));}break;
            case "Arch":return _buildings.wall_mesh(width,height,depth,new GArray {new Settings {["id"]="arch",["type"]="arch",["t"]=.5,["width"]=Math.Max(.05,width-depth*2),["height"]=Math.Max(.1,height-depth),["bottom"]=0.0}});
            case "Balcony":case "Porch":Box(mesh,new Vector3(width,depth,length),new Vector3(0,-depth*.5f,length*.5f));var railing=new Topology();Railing(railing,width,1,depth*.4f,(float)Get(p,"spacing",.6).AsDouble(),Get(p,"rails",2).AsInt32());mesh.Append(railing,new Transform3D(Basis.Identity,new Vector3(0,0,length)));if(name=="Porch"){foreach(float sign in new[]{-1f,1f})Box(mesh,new Vector3(depth,2.5f,depth),new Vector3(sign*(width-depth)*.5f,1.25f,length-depth*.5f));Box(mesh,new Vector3(width+depth,.12f,length+depth),new Vector3(0,2.56f,length*.5f));}break;
            case "Floor":case "Roof section":case "Foundation":Box(mesh,new Vector3(width,height,length),new Vector3(0,-height*.5f,0));break;
            default:Box(mesh,new Vector3(length,height,depth),new Vector3(length*.5f,height*.5f,0));break;
        }
        return mesh.Build();
    }
}
