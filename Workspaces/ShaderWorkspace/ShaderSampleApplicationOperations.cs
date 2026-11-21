using Godot;
using System;
using System.Text.RegularExpressions;
using Settings=Godot.Collections.Dictionary;

public partial class ShaderSampleApplicationOperations : RefCounted
{
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private static Settings Reason(string reason)=>new() {["reason"]=reason};
    private static Resource Reference(Resource data)
    {var reference=new ActorObjectReference();reference.Set("object_type",data.Get("type_id"));reference.Set("embedded",data);return reference;}
    private static bool IsReference(Variant value)
    {if(value.VariantType!=Variant.Type.Object||value.AsGodotObject() is not Resource resource)return false;var script=resource.GetScript().As<Script>();while(script!=null){if(script.ResourcePath=="res://scripts/actors/core/ActorObjectReference.cs")return true;script=script.GetBaseScript();}return false;}
    public Settings target_for(SceneTree tree,string kind)
    {var editor=tree.GetFirstNodeInGroup("actor_timeline_editors");return editor==null?Reason("Open a scene and select a compatible actor."):target_for_model(editor.Get("model").As<RefCounted>(),editor.Get("registry").As<RefCounted>(),kind);}
    public Settings target_for_model(RefCounted model,RefCounted registry,string kind)
    {
        var actor=model.Call("selected_actor").As<Resource>();if(actor==null)return Reason("Select a compatible scene actor first.");var definition=registry.Call("get_definition",actor.Get("type_id")).As<Resource>();if(definition==null)return Reason("The selected actor has no material definition.");if(kind=="particles")return Reason("This actor system does not expose a GPU particle process-shader slot. Copy, save, or open this shader for GPUParticles.");
        var key=new StringName(kind=="sky"?"environment":"material");var property=definition.Call("find_property",key).As<Resource>();var objectType=new StringName(kind=="canvas_item"?"canvas_shader_material":kind=="fog"?"fog_shader_material":"shader_material");var objectDefinition=registry.Call("get_object_definition",kind=="sky"?new StringName("environment"):objectType).As<Resource>();string name=actor.Get("display_name").AsString();if(property==null||objectDefinition==null)return Reason(name+" has no compatible "+kind+" material slot.");var candidate=Reference(objectDefinition.Call("create_object").As<Resource>());if(!property.Call("accepts",candidate).AsBool())return Reason(name+" does not accept "+kind+" shaders.");return new Settings {["model"]=model,["registry"]=registry,["actor"]=actor,["definition"]=definition,["key"]=key,["object_type"]=objectType,["kind"]=kind,["label"]=name+" / "+property.Get("label").AsString(),["existing"]=actor.Call("get_value",key).VariantType!=Variant.Type.Nil};
    }
    public string apply_to_target(Settings target,string source,string sampleName)
    {
        if(!target.ContainsKey("actor"))return Get(target,"reason","No compatible target.").AsString();var model=target["model"].As<RefCounted>();var registry=target["registry"].As<RefCounted>();var actor=target["actor"].As<Resource>();string kind=target["kind"].AsString();var current=target_for_model(model,registry,kind);if(!current.ContainsKey("actor")||current["actor"].As<Resource>()!=actor)return "The selected actor changed. Select the target again before applying.";if(!Regex.IsMatch(source,@"(?m)^\s*shader_type\s+"+Regex.Escape(kind)+@"\s*;"))return "The shader source is incompatible with this material slot.";
        var shader=new Shader {ResourceName=sampleName,Code=source};var definition=registry.Call("get_object_definition",target["object_type"]).As<Resource>();var data=definition.Call("create_object").As<Resource>();data.Get("values").AsGodotDictionary()[new StringName("shader_path")]=shader;var reference=Reference(data);
        if(kind=="sky")
        {
            var previousReference=actor.Call("get_value",new StringName("environment"));Resource? previous=IsReference(previousReference)?GD.Load<CSharpScript>("res://scripts/actors/core/ActorAnimation.cs").Call("resolve_reference",previousReference).As<Resource>():null;var environment=previous!=null?previous.Call("copy_object").As<Resource>():registry.Call("get_object_definition",new StringName("environment")).As<Resource>().Call("create_object").As<Resource>();var values=environment.Get("values").AsGodotDictionary();values[new StringName("background_mode")]=3;values[new StringName("sky_material")]=reference;reference=Reference(environment);
        }
        model.Call("edit_property",actor,target["definition"],target["key"],reference);return "";
    }
}
