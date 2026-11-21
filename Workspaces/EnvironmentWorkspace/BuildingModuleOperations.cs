using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class BuildingModuleOperations : RefCounted
{
    private readonly ModelImport _imports=new();
    private readonly ModelDocumentOperations _documents=new();
    private readonly ModelComponentOperations _components=new();
    private readonly ModelReferenceRemap _references=new();
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private static Resource Document(RefCounted session)=>session.Get("document").As<Resource>();
    private static bool ScriptType(Resource item,string path)
    {var script=item.GetScript().As<Script>();while(script!=null){if(script.ResourcePath==path||script.ResourcePath==LegacyResourceLoader.NativeScriptPath(path))return true;script=script.GetBaseScript();}return false;}
    private readonly ModuleLinkOperations _links=new();
    private static ModelSourceLink Files()=>Engine.GetSingleton("KiwiNativeServices").Call("service","model_source_link").As<ModelSourceLink>();
    public Settings insert(RefCounted session,string parentId,string path,Transform3D pose,string ownPath)
    {
        var document=Document(session);var parent=_documents.component(document,parentId);if(parent==null||!_documents.editable_component(document,parent))return new Settings {["id"]="",["error"]="Choose an editable parent component."};var source=_imports.load_document(path);if(ScriptType(source,"res://Workspaces/EnvironmentWorkspace/environment_document.gd"))return new Settings {["id"]="",["error"]="Use reusable environment insertion for terrain and scattering."};if(source.Get("components").AsGodotArray().Count==0||_documents.validate(source).Length>0)return new Settings {["id"]="",["error"]="Choose a valid model, mesh or imported 3D scene."};if(ownPath.Length>0&&_links.depends_on(path,ownPath))return new Settings {["id"]="",["error"]="This source would create a linked model dependency cycle."};
        var group=new KiwiModelComponent();string groupId=Guid.NewGuid().ToString("N");group.Set("id",groupId);group.Set("title",path.GetFile().GetBaseName());group.Set("parent_id",parentId);group.Set("transform",pose);var values=group.Get("parameters").AsGodotDictionary();values["architecture_module_source"]=path;var loaded=Files().load_resource(path);values["module_linked"]=loaded!=null&&ScriptType(loaded,"res://Workspaces/ModelWorkspace/model_document.gd");var remap=new Settings();var parts=new List<Resource>();var originals=source.Get("components").AsGodotArray();foreach(var value in originals)remap[value.As<Resource>().Get("id")]=Guid.NewGuid().ToString("N");
        foreach(var value in originals){var original=value.As<Resource>();var copy=_components.copy_component(original,false);copy.Set("id",remap[original.Get("id")]);copy.Set("parent_id",Get(remap,original.Get("parent_id").AsString(),groupId));_references.component(copy,remap);_links.bind(copy,groupId,original.Get("id").AsString());parts.Add(copy);}
        session.Call("begin");document=Document(session);var components=document.Get("components").AsGodotArray();components.Add(group);bool environment=ScriptType(document,"res://Workspaces/EnvironmentWorkspace/environment_document.gd");if(environment)document.Get("component_settings").AsGodotDictionary()[groupId]=new Settings {["kind"]="group"};foreach(var part in parts){components.Add(part);if(environment)document.Get("component_settings").AsGodotDictionary()[part.Get("id")]=new Settings {["kind"]="asset",["collision"]=part.Get("mesh").As<Resource>()!=null};}var selected=session.Get("selected").AsGodotArray();selected.Clear();selected.Add(groupId);session.Call("commit","Insert model module");return new Settings {["id"]=groupId,["error"]=""};
    }
    public GArray anchors(Resource item)
    {
        var result=new GArray {new Settings {["name"]="Origin",["pose"]=Transform3D.Identity}};foreach(var value in Get(item.Get("parameters").AsGodotDictionary(),"module_anchors",new GArray()).AsGodotArray()){var anchor=value.AsGodotDictionary();if(Get(anchor,"pose").VariantType==Variant.Type.Transform3D)result.Add(anchor.Duplicate());}var mesh=item.Get("mesh").As<Resource>();if(mesh==null||mesh.Get("vertices").AsVector3Array().Length==0)return result;using var meshes=new ModelMeshOperations();var bounds=meshes.bounds(mesh);var center=bounds.GetCenter();for(int axis=0;axis<3;axis++)foreach(float sign in new[]{-1f,1f}){var normal=Vector3.Zero;normal[axis]=sign;var point=center;point[axis]=(sign>0?bounds.End:bounds.Position)[axis];result.Add(new Settings {["name"]=new[]{"X","Y","Z"}[axis]+(sign>0?"+":"−"),["pose"]=new Transform3D(Basis.LookingAt(-normal,axis==1?Vector3.Forward:Vector3.Up),point)});}return result;
    }
    public string snap(RefCounted session,string id,Transform3D anchor,string targetId,Transform3D targetAnchor,bool mate)
    {
        var document=Document(session);var lookup=ModelDocumentOperations.Lookup(document);lookup.TryGetValue(id,out var item);lookup.TryGetValue(targetId,out var target);if(item==null||target==null||id==targetId||ModelDocumentOperations.Descendant(lookup,targetId,id))return "Choose a target outside the moving component's hierarchy.";if(!ModelDocumentOperations.Accessible(lookup,item,true))return "This component is locked.";lookup.TryGetValue(item.Get("parent_id").AsString(),out var parent);var parentPose=parent!=null?ModelDocumentOperations.WorldTransform(lookup,parent):Transform3D.Identity;if(Math.Abs(parentPose.Basis.Determinant())<.000001||Math.Abs(anchor.Basis.Determinant())<.000001)return "A zero-size transform cannot be aligned.";var facing=mate?new Transform3D(new Basis(Vector3.Up,Mathf.Pi),Vector3.Zero):Transform3D.Identity;var pose=parentPose.AffineInverse()*ModelDocumentOperations.WorldTransform(lookup,target)*targetAnchor*facing*anchor.AffineInverse();if(!pose.Origin.IsFinite()||!pose.Basis.IsFinite())return "The alignment produced an invalid transform.";session.Call("begin");item.Set("transform",pose);session.Call("commit","Align module anchors");return "";
    }
}
