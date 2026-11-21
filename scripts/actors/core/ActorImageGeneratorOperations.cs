using Godot;
using System;
using Settings=Godot.Collections.Dictionary;
public partial class ActorImageGeneratorOperations:RefCounted
{
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)||values.TryGetValue(new StringName(key),out value)?value:fallback;
    public Image? image_for_object(Resource? resource)
    {
        if(resource==null)return null;var values=resource.Get("values").AsGodotDictionary();return resource.Get("type_id").AsString() switch{"image"=>image_from_value(Get(values,"source","")),"noise_image"=>generate_noise(resource),_=>null};
    }
    public Texture2D? texture_for_object(Resource? resource)
    {
        if(resource!=null&&resource.Get("type_id").AsString()=="noise_image"){string key=GD.VarToStr(resource.Get("values"));var cache=ActorImageGenerator.NoiseTextureCache;if(cache.TryGetValue(key,out var value)&&value.VariantType==Variant.Type.Object&&value.AsGodotObject() is Texture2D texture&&GodotObject.IsInstanceValid(texture))return texture;var image=generate_noise(resource);if(image==null||image.IsEmpty())return null;var result=ImageTexture.CreateFromImage(image);if(cache.Count>=16)cache.Clear();cache[key]=result;return result;}var bitmap=image_for_object(resource);return bitmap!=null&&!bitmap.IsEmpty()?ImageTexture.CreateFromImage(bitmap):null;
    }
    public Image? image_from_value(Variant value)
    {
        if(value.VariantType==Variant.Type.Object){var resource=value.AsGodotObject();if(resource is Texture2D texture)return texture.GetImage();if(resource is Image image)return image;}string path=value.ToString();if(path.Length==0)return null;if(path.StartsWith("res://",StringComparison.Ordinal)||path.StartsWith("user://",StringComparison.Ordinal))path=ProjectSettings.GlobalizePath(path);return FileAccess.FileExists(path)?Image.LoadFromFile(path):null;
    }
    public Image? generate_noise(Resource resource)
    {
        var values=resource.Get("values").AsGodotDictionary();string key=GD.VarToStr(values);var cache=ActorImageGenerator.NoiseImageCache;if(cache.TryGetValue(key,out var existing))return existing.As<Image>();using var noise=new FastNoiseLite{NoiseType=(FastNoiseLite.NoiseTypeEnum)Math.Clamp(Get(values,"noise_type",1).AsInt32(),0,5),Seed=Get(values,"seed",0).AsInt32(),Frequency=Math.Clamp(Get(values,"frequency",.015).AsSingle(),.0001f,1),FractalType=(FastNoiseLite.FractalTypeEnum)Math.Clamp(Get(values,"fractal_type",1).AsInt32(),0,3),FractalOctaves=Math.Clamp(Get(values,"octaves",5).AsInt32(),1,10),FractalLacunarity=Math.Clamp(Get(values,"lacunarity",2).AsSingle(),.01f,8),FractalGain=Math.Clamp(Get(values,"gain",.5).AsSingle(),0,2)};int size=new[]{64,128,256,512}[Math.Clamp(Get(values,"resolution",2).AsInt32(),0,3)];bool invert=Get(values,"invert",false).AsBool();using var source=Get(values,"seamless",true).AsBool()?noise.GetSeamlessImage(size,size,invert,false,.1f):noise.GetImage(size,size,invert,false,true);if(source==null||source.IsEmpty())return null;var low=Get(values,"low_color",Colors.Black).AsColor();var high=Get(values,"high_color",Colors.White).AsColor();float contrast=Math.Clamp(Get(values,"contrast",1).AsSingle(),.01f,4);var result=Image.CreateEmpty(size,size,false,Image.Format.Rgba8);for(int y=0;y<size;y++)for(int x=0;x<size;x++){float amount=Math.Clamp((source.GetPixel(x,y).R-.5f)*contrast+.5f,0,1);result.SetPixel(x,y,low.Lerp(high,amount));}if(Get(values,"as_normal_map",false).AsBool())result.BumpMapToNormalMap();if(cache.Count>=16)cache.Clear();cache[key]=result;return result;
    }
}
