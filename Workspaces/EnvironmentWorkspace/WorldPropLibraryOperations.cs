using Godot;
using System;
using Settings=Godot.Collections.Dictionary;

public partial class WorldPropLibraryOperations : RefCounted
{
    private readonly ModelPrimitives _primitives=new();
    private readonly WorldPropOperations _props=new();
    public StandardMaterial3D material(Color color)=>new() {AlbedoColor=color,Roughness=.85f};
    public void part(Resource document,string title,string shape,Settings settings,Vector3 position,Material material)
    {
        var components=document.Get("components").AsGodotArray();var item=new KiwiModelComponent();item.Set("id","part:"+components.Count);item.Set("title",title);item.Set("generator",shape);var parameters=_primitives.defaults(shape);parameters.Merge(settings,true);item.Set("parameters",parameters);item.Set("mesh",_primitives.create(shape,settings));item.Set("transform",new Transform3D(Basis.Identity,position));item.Get("surface_materials").AsGodotArray().Add(material);components.Add(item);
    }
    public Resource model(string kind)
    {
        var document=new KiwiModelDocument();var wood=material(new Color("72523b"));var metal=material(new Color("3b454a"));var stone=material(new Color("858980"));var light=material(new Color("fff0bd"));light.EmissionEnabled=true;light.Emission=new Color("ffda85");light.EmissionEnergyMultiplier=2;
        void Box(string title,Vector3 size,Vector3 position,Material surface)=>part(document,title,"Box",new Settings {["size"]=size},position,surface);
        void Cylinder(string title,double radius,double height,int segments,Vector3 position,Material surface)=>part(document,title,"Cylinder",new Settings {["radius"]=radius,["height"]=height,["segments"]=segments},position,surface);
        switch(kind)
        {
            case "Park bench":foreach(float x in new[]{-.65f,.65f})Box("Leg",new Vector3(.1f,.5f,.6f),new Vector3(x,.25f,0),metal);for(int z=0;z<3;z++)Box("Seat slat",new Vector3(1.65f,.07f,.17f),new Vector3(0,.52f,(z-1)*.2f),wood);for(int y=0;y<2;y++)Box("Back slat",new Vector3(1.65f,.16f,.07f),new Vector3(0,.8f+y*.2f,.3f),wood);break;
            case "Street lamp":Cylinder("Foot",.18,.15,12,new Vector3(0,.075f,0),metal);Cylinder("Post",.055,3.6,10,new Vector3(0,1.9f,0),metal);Box("Arm",new Vector3(.1f,.1f,.8f),new Vector3(0,3.65f,-.35f),metal);Box("Lamp housing",new Vector3(.4f,.15f,.65f),new Vector3(0,3.58f,-.65f),metal);Box("Lamp lens",new Vector3(.32f,.025f,.55f),new Vector3(0,3.49f,-.65f),light);break;
            case "Bollard":Cylinder("Base",.14,.1,12,new Vector3(0,.05f,0),metal);Cylinder("Post",.075,.85,12,new Vector3(0,.525f,0),metal);Cylinder("Reflector",.078,.07,12,new Vector3(0,.8f,0),light);break;
            case "Direction sign":Cylinder("Post",.05,2,10,new Vector3(0,1,0),metal);Box("Sign board",new Vector3(1.2f,.35f,.09f),new Vector3(0,1.75f,0),wood);part(document,"Arrow","Prism",new Settings {["size"]=new Vector3(.3f,.35f,.09f)},new Vector3(.72f,1.75f,0),wood);break;
            case "Wood fence":foreach(float x in new[]{-1f,1f})Box("Post",new Vector3(.12f,1.2f,.12f),new Vector3(x,.6f,0),wood);foreach(float y in new[]{.35f,.9f})Box("Rail",new Vector3(2.1f,.13f,.09f),new Vector3(0,y,0),wood);break;
            case "Stone boundary":for(int row=0;row<3;row++)for(int block=0;block<4;block++)Box("Stone",new Vector3(.5f,.22f,.35f),new Vector3((float)((block-1.5)*.51+(row%2)*.1),(float)(.11+row*.23),0),stone);break;
            case "Supply crates":foreach(var position in new[]{new Vector3(-.3f,.35f,0),new Vector3(.45f,.25f,.2f),new Vector3(-.3f,.95f,0)})Box("Crate",new Vector3(.65f,.6f,.65f),position,wood);break;
            case "Rock cluster":foreach(var position in new[]{new Vector3(-.4f,.25f,0),new Vector3(.35f,.4f,.2f),new Vector3(.15f,.16f,-.45f)})part(document,"Rock","Sphere",new Settings {["radius"]=.45,["segments"]=10},position,stone);break;
        }
        var components=document.Get("components").AsGodotArray();if(components.Count>0)components[0].As<Resource>().Set("title",kind);return document;
    }
    public Resource add(Resource source,string kind)
    {var document=model(kind);var next=_props.create(source,document,kind is "Supply crates" or "Rock cluster"?"Clusters":"Roadside");var rule=next.Get("prop_rules").AsGodotArray()[^1].AsGodotDictionary();rule["name"]=kind;rule["spacing"]=kind=="Street lamp"?20.0:kind is "Wood fence" or "Stone boundary"?2.1:12.0;rule["sidewalk"]=kind is "Park bench" or "Street lamp" or "Bollard";rule["setback"]=1.0;rule["budget"]=500;return next;}
}
