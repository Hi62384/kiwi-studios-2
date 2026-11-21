using Godot;
using System;
using System.Text.RegularExpressions;
using Settings=Godot.Collections.Dictionary;
public partial class ImageWorkspaceOperations
{
    public void choose_shader_effect_result(Control owner,string chosen)
    {
        if(chosen.Length==0||chosen=="::empty-resource::")return;var shader=ResourceLoader.Load(chosen,"",ResourceLoader.CacheMode.Ignore) as Shader;if(shader==null||!Regex.IsMatch(shader.Code,@"shader_type\s+canvas_item\s*;")){owner.Get("status").As<Label>().Text="Choose a shader with shader_type canvas_item.";return;}var layer=main_layer(owner);if(layer==null)return;Action(owner,()=>layer.Get("effects").AsGodotArray().Add(new Settings{["id"]=NewId(),["type"]="shader",["enabled"]=true,["shader"]=shader,["uniforms"]=new Settings()}));
    }
    private static double Component(Variant value,Variant.Type type,int index)=>type switch{Variant.Type.Vector2=>value.VariantType==Variant.Type.Vector2?value.AsVector2()[index]:0,Variant.Type.Vector3=>value.VariantType==Variant.Type.Vector3?value.AsVector3()[index]:0,Variant.Type.Vector4=>value.VariantType==Variant.Type.Vector4?value.AsVector4()[index]:0,_=>0};
    private static Variant WithComponent(Variant value,Variant.Type type,int index,double next)
    {
        if(type==Variant.Type.Vector2){var vector=value.VariantType==type?value.AsVector2():Vector2.Zero;vector[index]=(float)next;return vector;}if(type==Variant.Type.Vector3){var vector=value.VariantType==type?value.AsVector3():Vector3.Zero;vector[index]=(float)next;return vector;}var result=value.VariantType==type?value.AsVector4():Vector4.Zero;result[index]=(float)next;return result;
    }
    public void shader_fields(Control owner,Node parent,Settings effect)
    {
        var shader=effect["shader"].As<Shader>();var uniforms=effect["uniforms"].AsGodotDictionary();foreach(var row in shader.GetShaderUniformList()){var uniform=row.AsGodotDictionary();StringName key=uniform["name"].AsStringName();var fallback=RenderingServer.ShaderGetParameterDefault(shader.GetRid(),key);var value=uniforms.TryGetValue(key,out var configured)?configured:fallback;var type=(Variant.Type)uniform["type"].AsInt32();switch(type){case Variant.Type.Float:case Variant.Type.Int:number(owner,parent,key.ToString(),value.VariantType==Variant.Type.Nil?0:value.AsDouble(),Callable.From<double>(next=>uniforms[key]=type==Variant.Type.Int?Variant.From((int)next):Variant.From(next)),-100000,100000,.1);break;case Variant.Type.Bool:check(owner,parent,key.ToString(),value.AsBool(),Callable.From<bool>(next=>uniforms[key]=next));break;case Variant.Type.Color:color(owner,parent,key.ToString(),value.VariantType==Variant.Type.Color?value.AsColor():Colors.White,Callable.From<Color>(next=>uniforms[key]=next));break;case Variant.Type.Vector2:case Variant.Type.Vector3:case Variant.Type.Vector4:int count=type==Variant.Type.Vector2?2:type==Variant.Type.Vector3?3:4;for(int i=0;i<count;i++){int axis=i;number(owner,parent,key+" "+new[]{"X","Y","Z","W"}[axis],Component(value,type,axis),Callable.From<double>(next=>{var vector=uniforms.TryGetValue(key,out var current)?current:fallback;uniforms[key]=WithComponent(vector,type,axis,next);}),-100000,100000,.1);}break;case Variant.Type.Object:button(owner,parent,key+" · Load image…",Callable.From(()=>owner.Call("_choose_effect_texture",effect,key)),"","");break;}}
    }
    public void effect_texture_result(Control owner,Settings effect,StringName key,string chosen)
    {
        var uniforms=effect["uniforms"].AsGodotDictionary();if(chosen=="::empty-resource::"){Action(owner,()=>uniforms[key]=default(Variant));return;}if(chosen.Length==0)return;using var bitmap=Image.LoadFromFile(chosen);if(bitmap!=null)Action(owner,()=>uniforms[key]=ImageTexture.CreateFromImage(bitmap));
    }
}
