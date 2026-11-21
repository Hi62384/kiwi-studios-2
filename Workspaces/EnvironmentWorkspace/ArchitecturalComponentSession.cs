using Godot;
using System;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;
using Topology=ModelGeometryOperations.Topology;

public partial class ArchitecturalComponentOperations
{
    private readonly ModelDocumentOperations _documents=new();
    private static Resource Document(RefCounted session)=>session.Get("document").As<Resource>();
    private static Resource NewComponent()=>new KiwiModelComponent();
    public Resource add(RefCounted session,string kind,Settings parameters,Vector3 position)
    {
        var item=NewComponent();item.Set("id",Guid.NewGuid().ToString("N"));string title=Kind(kind);item.Set("title",title);item.Set("generator",kind);var values=defaults(kind);values.Merge(parameters,true);values=normalize(values);item.Set("parameters",values);item.Set("mesh",generate(kind,values));item.Set("transform",new Transform3D(Basis.Identity,position));item.Set("structural",new Settings {[new StringName("structure_enabled")]=false,[new StringName("structure_role")]=0});using var material=new StandardMaterial3D {AlbedoColor=new Color("b8b5a8")};var surfaces=item.Get("surface_materials").AsGodotArray();surfaces.Add(material);if(title=="Window"){using var glass=new StandardMaterial3D {Transparency=BaseMaterial3D.TransparencyEnum.Alpha,AlbedoColor=new Color(.6f,.8f,.9f,.3f),Roughness=.12f};surfaces.Add(glass);}session.Call("begin");Document(session).Get("components").AsGodotArray().Add(item);var selected=session.Get("selected").AsGodotArray();selected.Clear();selected.Add(item.Get("id"));if(title=="Door")door_leaf(session,item);else if(title=="Window")window_glass(session,item);session.Call("commit","Add "+title);return item;
    }
    public void door_leaf(RefCounted session,Resource item)
    {
        var document=Document(session);string id=item.Get("id").AsString()+":leaf";var leaf=_documents.component(document,id);bool fresh=leaf==null;if(fresh){leaf=NewComponent();leaf.Set("id",id);leaf.Set("title","Door leaf");leaf.Set("parent_id",item.Get("id"));document.Get("components").AsGodotArray().Add(leaf);}var values=item.Get("parameters").AsGodotDictionary();float width=(float)values["width"].AsDouble(),height=(float)values["height"].AsDouble(),trim=(float)Math.Clamp(Get(values,"trim",.07).AsDouble(),.01,Math.Min(width,height)*.3);var mesh=ModelPrimitives.Box(new Vector3(width-trim*2,height-trim,.05f));for(int index=0;index<mesh.Points.Count;index++)mesh.Points[index]+=new Vector3((width-trim*2)*.5f,(height-trim)*.5f,0);var pose=new Transform3D(new Basis(Vector3.Up,Mathf.DegToRad((float)Get(values,"angle",0.0).AsDouble())),new Vector3(-width*.5f+trim,0,0));var leafValues=leaf!.Get("parameters").AsGodotDictionary();if(fresh||leaf.Get("transform").AsTransform3D()==Get(leafValues,"_door_pose",leaf.Get("transform")).AsTransform3D())leaf.Set("transform",pose);leafValues["_door_pose"]=pose;leafValues["architecture_type"]="door leaf";leaf.Set("mesh",mesh.Build());leaf.Set("surface_materials",item.Get("surface_materials").AsGodotArray().Duplicate());leaf.Set("structural",new Settings {[new StringName("structure_enabled")]=false,[new StringName("structure_role")]=0,[new StringName("structure_connections")]=new Settings {["hinge"]=StructureConnectionOperations.Create(item.Get("id").AsString(),Vector3.Zero,pose.Origin,1)}});
    }
    public void window_glass(RefCounted session,Resource item)
    {
        var document=Document(session);string id=item.Get("id").AsString()+":glass";var glass=_documents.component(document,id);if(glass==null){glass=NewComponent();glass.Set("id",id);glass.Set("title","Glass pane");glass.Set("parent_id",item.Get("id"));document.Get("components").AsGodotArray().Add(glass);}var values=item.Get("parameters").AsGodotDictionary();float width=(float)values["width"].AsDouble(),height=(float)values["height"].AsDouble(),trim=(float)Math.Clamp(Get(values,"trim",.07).AsDouble(),.01,Math.Min(width,height)*.3);glass.Set("mesh",ModelPrimitives.Box(new Vector3(width-trim*2,height-trim*2,.015f)).Build());var pose=glass.Get("transform").AsTransform3D();pose.Origin=new Vector3(0,height*.5f,0);glass.Set("transform",pose);var surfaces=glass.Get("surface_materials").AsGodotArray();surfaces.Clear();surfaces.Add(item.Get("surface_materials").AsGodotArray()[1]);glass.Get("parameters").AsGodotDictionary()["architecture_type"]="glass pane";
    }
    public void set_parameter(RefCounted session,string id,string key,Variant value)
    {
        var item=_documents.component(Document(session),id);if(item==null||!accepts(item.Get("generator").AsString()))return;session.Call("begin");var values=item.Get("parameters").AsGodotDictionary();values[key]=value;values=normalize(values);item.Set("parameters",values);item.Set("mesh",generate(item.Get("generator").AsString(),values));string title=item.Get("title").AsString();if(title=="Door")door_leaf(session,item);if(title=="Window")window_glass(session,item);session.Call("commit","Change "+title);
    }
}
