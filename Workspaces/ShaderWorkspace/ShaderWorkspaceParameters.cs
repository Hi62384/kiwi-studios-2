using Godot;
using System;
using Settings=Godot.Collections.Dictionary;

public partial class ShaderWorkspaceOperations
{
    private static bool ScriptType(Resource resource,string path)
    {var script=resource.GetScript().As<Script>();while(script!=null){if(script.ResourcePath==path||script.ResourcePath==LegacyResourceLoader.NativeScriptPath(path))return true;script=script.GetBaseScript();}return false;}
    private static readonly string[] Materials={"spatial_material","sky_material","canvas_material","fog_preview_material","particle_material"};
    private static bool Binding(Control owner,string which)=>owner.Call("_parameter_binding_valid",which).AsBool();
    private static Variant CopyValue(Variant value)=>ActorData.copy_value(value);
    private static Variant Texture(Resource data)=>GD.Load<CSharpScript>("res://scripts/actors/core/ActorImageGenerator.cs").Call("texture_for_object",data);
    public Variant preview_parameter_value(Variant value)
    {
        if(value.VariantType==Variant.Type.Object&&value.AsGodotObject() is Resource resource)
        {
            if(resource is Texture2D)return value;if(ScriptType(resource,"res://scripts/actors/core/actor_object_reference.gd")){var loader=Callable.From<string,Variant>(path=>{var loaded=ResourceLoader.Load(path,"",ResourceLoader.CacheMode.Ignore);return loaded!=null&&ScriptType(loaded,"res://scripts/actors/core/actor_object_data.gd")?Variant.From(loaded):default;});var data=resource.Call("resolve",loader).As<Resource>();return data!=null?Texture(data):default;}if(ScriptType(resource,"res://scripts/actors/core/actor_object_data.gd"))return Texture(resource);
        }
        if(value.VariantType==Variant.Type.String&&value.AsString().Length>0){var loaded=ResourceLoader.Load(value.AsString(),"",ResourceLoader.CacheMode.Ignore);if(loaded is Texture2D)return loaded;if(loaded!=null&&ScriptType(loaded,"res://scripts/actors/core/actor_object_data.gd"))return Texture(loaded);}return value;
    }
    public void rebind_preview_materials(Control owner)
    {
        var shader=Item<Shader>(owner,"preview_shader");foreach(string name in Materials)owner.Set(name,new ShaderMaterial {Shader=shader});foreach(var pair in owner.Get("parameter_values").AsGodotDictionary()){var value=preview_parameter_value(pair.Value);var name=new StringName(pair.Key.ToString());foreach(string field in Materials)Item<ShaderMaterial>(owner,field).SetShaderParameter(name,value);}
    }
    private static bool Equal(Variant first,Variant last)
    {
        if(first.VariantType!=last.VariantType)return false;return first.VariantType switch {Variant.Type.Nil=>true,Variant.Type.Bool=>first.AsBool()==last.AsBool(),Variant.Type.Int=>first.AsInt64()==last.AsInt64(),Variant.Type.Float=>first.AsDouble()==last.AsDouble(),Variant.Type.String=>first.AsString()==last.AsString(),Variant.Type.StringName=>first.AsStringName()==last.AsStringName(),Variant.Type.Vector2=>first.AsVector2()==last.AsVector2(),Variant.Type.Vector3=>first.AsVector3()==last.AsVector3(),Variant.Type.Vector4=>first.AsVector4()==last.AsVector4(),Variant.Type.Color=>first.AsColor()==last.AsColor(),Variant.Type.Object=>first.AsGodotObject()==last.AsGodotObject(),Variant.Type.Dictionary=>first.AsGodotDictionary().RecursiveEqual(last.AsGodotDictionary()),Variant.Type.Array=>first.AsGodotArray().RecursiveEqual(last.AsGodotArray()),_=>first.Equals(last)};
    }
    public void set_preview_parameter(Control owner,StringName name,Variant value,string mode,Variant original)
    {
        owner.Get("parameter_values").AsGodotDictionary()[name]=value;var rendered=preview_parameter_value(value);foreach(string field in Materials)Item<ShaderMaterial>(owner,field).SetShaderParameter(name,rendered);var reset=Item<VBoxContainer>(owner,"parameters_list").FindChild(name+"_reset",true,false) as Button;if(reset!=null)reset.Visible=!Equal(value,shader_uniform_default(owner,name,(int)value.VariantType));if(owner.Get("parameters_linked").AsBool()&&Binding(owner,"writer"))owner.Call("_write_linked_parameter",name,CopyValue(value),mode,original);
    }
    public void vector_parameter_changed(Control owner,double next,StringName name,int component,int valueType,string mode,Variant original)
    {
        var values=owner.Get("parameter_values").AsGodotDictionary();var value=values.TryGetValue(name,out var stored)?stored:Item<ShaderMaterial>(owner,"spatial_material").GetShaderParameter(name);if(value.VariantType==Variant.Type.Nil)value=shader_uniform_default(owner,name,valueType);if((Variant.Type)valueType==Variant.Type.Vector2){var vector=value.AsVector2();vector[component]=(float)next;value=vector;}else if((Variant.Type)valueType==Variant.Type.Vector3){var vector=value.AsVector3();vector[component]=(float)next;value=vector;}else{var vector=value.AsVector4();vector[component]=(float)next;value=vector;}set_preview_parameter(owner,name,value,mode,original);
    }
    public Settings current_parameter_values(Control owner)
    {if(owner.Get("parameters_linked").AsBool()&&Binding(owner,"reader")){var values=owner.Call("_read_linked_parameters");if(values.VariantType==Variant.Type.Dictionary)return values.AsGodotDictionary().Duplicate(true);}return owner.Get("parameter_values").AsGodotDictionary().Duplicate(true);}
    public void commit_linked_parameters(Control owner)
    {if(!owner.Get("parameters_linked").AsBool()||!Binding(owner,"writer"))return;foreach(var pair in owner.Get("parameter_values").AsGodotDictionary())owner.Call("_write_linked_parameter",new StringName(pair.Key.ToString()),CopyValue(pair.Value),"edit",default(Variant));}
    public void reset_preview_parameter(Control owner,StringName name)
    {
        var value=shader_uniform_default(owner,name,uniform_type(owner,name));if(owner.Get("parameters_linked").AsBool())set_preview_parameter(owner,name,value,"edit",default);else{owner.Get("parameter_values").AsGodotDictionary().Remove(name);rebind_preview_materials(owner);owner.Call("_apply_environment");owner.Call("_apply_materials");}owner.Call("_rebuild_parameters");
    }
    public void parameter_link_toggled(Control owner,bool enabled)
    {bool linked=enabled&&Binding(owner,"both");owner.Set("parameters_linked",linked);if(linked)owner.Set("parameter_values",current_parameter_values(owner));rebind_preview_materials(owner);owner.Call("_apply_environment");owner.Call("_apply_materials");owner.Call("_rebuild_parameters");}
    public void reset_all_preview_parameters(Control owner)
    {
        if(owner.Get("parameters_linked").AsBool()){foreach(var value in Item<Shader>(owner,"preview_shader").GetShaderUniformList()){var info=value.AsGodotDictionary();var name=new StringName(info.TryGetValue("name",out var key)?key.AsString():"");if(!name.IsEmpty)set_preview_parameter(owner,name,shader_uniform_default(owner,name,info.TryGetValue("type",out var type)?type.AsInt32():0),"edit",default);}}else{owner.Get("parameter_values").AsGodotDictionary().Clear();rebind_preview_materials(owner);owner.Call("_apply_environment");owner.Call("_apply_materials");}owner.Call("_rebuild_parameters");
    }
}
