using Godot;
using System;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class ModuleLinkOperations
{
    private static Resource Document(RefCounted session)=>session.Get("document").As<Resource>();
    private static string[] Roots(Resource document)=>Components(document).Where(c=>Get(Values(c),"module_linked",false).AsBool()).Select(c=>Text(c,"id")).ToArray();
    public string refresh(RefCounted session,string id,bool reset)
    {
        if(session.Get("_gesture").AsGodotDictionary().Count>0)return "Finish the current edit before updating linked sources.";var document=Document(session);var group=_documents.component(document,id);if(group==null)return "Select a linked model instance.";var loaded=load(Get(Values(group),"architecture_module_source", "").AsString(),Array.Empty<string>(),new Settings());var source=loaded["document"].As<Resource>();if(source==null)return loaded["error"].AsString();var candidate=document.Call("snapshot").As<Resource>();string error=replace(candidate,id,source,reset);if(error.Length>0)return error;var errors=candidate.Call("validate").AsStringArray();if(errors.Length>0)return "The source update is incompatible with local rig or hierarchy edits: "+errors[0];session.Call("begin");session.Set("document",candidate);session.Call("commit",reset?"Reset linked source overrides":"Update linked model instance");return "";
    }
    public Settings resolve(Resource document)
    {
        var roots=Roots(document);if(roots.Length==0)return new Settings {["document"]=document,["error"]="",["dependencies"]=new GArray()};var candidate=document.Call("snapshot").As<Resource>();var cache=new Settings();foreach(string id in roots){var group=_documents.component(candidate,id);if(group==null)continue;var source=load(Get(Values(group),"architecture_module_source", "").AsString(),Array.Empty<string>(),cache);var loaded=source["document"].As<Resource>();if(loaded==null)return Failure(source["error"].AsString());string error=replace(candidate,id,loaded,false);if(error.Length>0)return Failure(error);}var errors=candidate.Call("validate").AsStringArray();return new Settings {["document"]=errors.Length==0?Variant.From(candidate):default,["error"]=errors.Length>0?errors[0]:"",["dependencies"]=new GArray(cache.Keys)};
    }
    public string refresh_changed(RefCounted session,string path)
    {
        var document=Document(session);bool affected=false;foreach(var item in Components(document))if(Get(Values(item),"module_linked",false).AsBool()&&depends_on(Get(Values(item),"architecture_module_source", "").AsString(),path)){affected=true;break;}if(!affected)return "";var resolved=resolve(document);var candidate=resolved["document"].As<Resource>();if(candidate==null)return resolved["error"].AsString();var errors=candidate.Call("validate").AsStringArray();if(errors.Length>0)return errors[0];if(session.Get("_gesture").AsGodotDictionary().Count>0)return "Finish the current edit before updating linked sources.";session.Call("begin");session.Set("document",candidate);session.Call("commit","Update linked model sources");return "";
    }
    public void make_unique(RefCounted session,string id)
    {
        var document=Document(session);var group=_documents.component(document,id);if(group==null)return;session.Call("begin");var values=Values(group);values.Remove("architecture_module_source");values.Remove("module_linked");foreach(var item in Components(document))if(Get(Values(item),"_module_bindings").VariantType==Variant.Type.Dictionary)Bindings(item).Remove(id);session.Call("commit","Make model instance unique");
    }
}
