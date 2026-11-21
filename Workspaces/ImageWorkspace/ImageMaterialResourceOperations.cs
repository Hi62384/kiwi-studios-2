using Godot;
using System;
public partial class ImageMaterialResourceOperations:RefCounted
{
    public Resource copy_material(Resource source)
    {
        var result=new KiwiTextureMaterial();foreach(string key in new[]{"material_id","format_version","label","image","texture_size","rotation","alignment","application","spacing","jitter","random_rotation","random_scale","follow_direction","direction_smoothing","mapping_origin","tint_strength","tiling","blending","mix_amount","mix_distribution","mix_mask","relief","relief_softness","light_direction","highlight","shadow","coverage","source","surface_mapping","triplanar_sharpness","metallic"})result.Set(key,source.Get(key));result.Set("parameters",source.Get("parameters").AsGodotDictionary().Duplicate(true));var secondary=source.Get("secondary").As<Resource>();if(secondary!=null)result.Set("secondary",copy_material(secondary));return result;
    }
    public Resource copy_region(Resource source)
    {
        var result=new KiwiLivePaintRegion();foreach(string key in new[]{"id","template_id","coverage","coordinates","coordinate_rect","raster","mapping","opacity"})result.Set(key,source.Get(key));return result;
    }
    public bool is_live(Resource region)=>region.Get("template_id").AsString().Length>0;
    public Resource copy_template(Resource source)
    {
        var result=new KiwiLiveMaterialTemplate();foreach(string key in new[]{"version","id","label","visible"})result.Set(key,source.Get(key));var material=source.Get("material").As<Resource>();if(material!=null)result.Set("material",copy_material(material));return result;
    }
}
