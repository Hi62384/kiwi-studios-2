using Godot;
using System;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;
public partial class ActorPropertyOperations:RefCounted
{
    private readonly ActorDataOperations _data=new();private readonly ActorImageGeneratorOperations _images=new();private readonly ActorAnimationOperations _animation=new();
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private static string[] Strings(Variant value){if(value.VariantType==Variant.Type.PackedStringArray)return value.AsStringArray();if(value.VariantType!=Variant.Type.Array)return Array.Empty<string>();var array=value.AsGodotArray();var result=new string[array.Count];for(int i=0;i<result.Length;i++)result[i]=array[i].AsString();return result;}
    public bool can_keyframe(Resource property)
    {
        var options=property.Get("options").AsGodotDictionary();if(Get(options,"no_keyframes",false).AsBool()||Get(options,"file_picker",false).AsBool()||property.Get("object_type").AsString().Length>0)return false;return (Variant.Type)property.Get("value_type").AsInt32() is Variant.Type.Float or Variant.Type.Int or Variant.Type.Bool or Variant.Type.String or Variant.Type.StringName or Variant.Type.Vector2 or Variant.Type.Vector3 or Variant.Type.Vector4 or Variant.Type.Vector2I or Variant.Type.Vector3I or Variant.Type.Vector4I or Variant.Type.Color;
    }
    public int file_resource_mode(Resource property)=>Get(property.Get("options").AsGodotDictionary(),"file_resource_mode","").AsString() switch{"uneditable"=>1,"editable"=>2,_=>0};
    public Resource create(StringName key,string label,Variant value,bool animatable)
    {
        var property=new ActorProperty();property.Set("id",key);property.Set("label",label);property.Set("value_type",(int)value.VariantType);property.Set("animatable",animatable);property.Set("options",new Settings{["default"]=value});return property;
    }
    public bool accepts(Resource property,Variant value)
    {
        string objectType=property.Get("object_type").AsString();var options=property.Get("options").AsGodotDictionary();var resource=value.VariantType==Variant.Type.Object?value.AsGodotObject():null;bool empty=value.VariantType==Variant.Type.Nil||value.VariantType==Variant.Type.Object&&resource==null;if(objectType.Length>0){if(empty)return true;if(resource is not Resource reference||!ActorDataOperations.ScriptIs(reference,"res://scripts/actors/core/actor_object_reference.gd"))return false;return Array.IndexOf(Strings(Get(options,"accepted_object_types",new GArray{objectType})),reference.Get("object_type").AsString())>=0;}if(Get(options,"file_picker",false).AsBool()){if(empty||value.VariantType==Variant.Type.String)return true;var extensions=Strings(Get(options,"extensions",new GArray()));if(Array.IndexOf(extensions,"mp3")>=0)return resource is AudioStream;if(Array.IndexOf(extensions,"gdshader")>=0)return resource is Shader;if(Array.IndexOf(extensions,"glb")>=0||Array.IndexOf(extensions,"mesh")>=0)return resource is Mesh or PackedScene;return resource is Texture2D or Image;}return (int)value.VariantType==property.Get("value_type").AsInt32();
    }
    public Variant create_default(Resource property)=>_data.copy_value(Get(property.Get("options").AsGodotDictionary(),"default"));
    public Variant create_default_for_actor(Resource property,Resource? actor)
    {
        string imageProperty=Get(property.Get("options").AsGodotDictionary(),"aspect_ratio_from_image",new StringName("")).AsString();if(actor!=null&&imageProperty.Length>0&&property.Get("value_type").AsInt32()==(int)Variant.Type.Vector3)return image_ratio_scale(_data.get_value(actor,imageProperty,""));return create_default(property);
    }
    public Vector3 image_ratio_scale(Variant value)
    {
        Image? image=null;bool owned=false;try{if(value.VariantType==Variant.Type.Object){var resource=value.AsGodotObject();if(resource is Resource reference&&ActorDataOperations.ScriptIs(reference,"res://scripts/actors/core/actor_object_reference.gd"))image=_images.image_for_object(_animation.resolve_reference(reference));else if(resource is Resource data&&ActorDataOperations.ScriptIs(data,"res://scripts/actors/core/actor_object_data.gd"))image=_images.image_for_object(data);else if(resource is Texture2D texture){image=texture.GetImage();owned=true;}else if(resource is Image bitmap)image=bitmap;}else{string path=value.ToString();if(path.Length==0||!FileAccess.FileExists(path))return Vector3.One;image=Image.LoadFromFile(path);owned=true;}if(image==null||image.IsEmpty())return Vector3.One;float width=image.GetWidth(),height=image.GetHeight(),longest=Math.Max(width,height);return longest>0?new Vector3(width/longest,height/longest,1):Vector3.One;}finally{if(owned)image?.Dispose();}
    }
}
