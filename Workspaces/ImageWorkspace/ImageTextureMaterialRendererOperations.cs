using Godot;
using System;
using Settings=Godot.Collections.Dictionary;
public partial class ImageTextureMaterialRendererOperations:RefCounted
{
    private readonly NaturalMaterialShaderSourceOperations _source=new();
    private readonly NaturalMaterialDefinitionOperations _definitions=new();
    private readonly ImageMaterialResourceOperations _resources=new();
    private static Variant Get(Settings d,string key,Variant fallback=default)=>d.TryGetValue(key,out var value)?value:fallback;
    private static GDScript Bridge=>GD.Load<GDScript>("res://Workspaces/ImageWorkspace/texture_material_renderer.gd");
    public ShaderMaterial material(Resource value,Vector2 extent,Transform2D frame,bool straightOutput)
    {
        var bridge=Bridge;var shaders=bridge.Get("shader_cache").AsGodotDictionary();var noises=bridge.Get("noise_cache").AsGodotDictionary();
        string id=value.Get("material_id").AsString();var second=value.Get("secondary").As<Resource>();bool mixed=second!=null&&value.Get("mix_amount").AsDouble()>0;
        string key=id+"/"+(straightOutput?"true":"false")+(mixed?"/"+second!.Get("material_id").AsString():"");
        if(!shaders.ContainsKey(key))
        {
            string code=bridge.Get("CODE").AsString(),source=GD.Load<GDScript>("res://scripts/materials/natural_material_shader_source.gd").Get("source").AsString();
            code=code[..code.IndexOf("// Single structural evaluator",StringComparison.Ordinal)]+_source.pattern_source(source,id)+"\n"+code[code.IndexOf("void fragment()",StringComparison.Ordinal)..];code=_source.constants(code,id,"");
            if(mixed){string duplicate=_source.secondary_source(source,second!.Get("material_id").AsString());code=code.Replace("void fragment()",duplicate+"\nvoid fragment()");code=_source.constants(code,second.Get("material_id").AsString(),"secondary_");}
            else{int start=code.IndexOf("if(mixer_enabled)",StringComparison.Ordinal),end=_source.block_end(code,code.IndexOf('{',start));code=code[..start]+code[(end+1)..];}
            if(straightOutput)code=code.Replace("render_mode unshaded;","render_mode unshaded, blend_disabled;");
            var compiled=new Shader{Code=code};if(shaders.Count>=32)shaders.Remove(shaders.Keys.GetEnumerator().First());shaders[key]=compiled;
        }
        var result=new ShaderMaterial{Shader=shaders[key].As<Shader>()};
        int family=_source.family_index(id),variant=_definitions.variant(id);result.SetShaderParameter("family",family);result.SetShaderParameter("variant",variant);
        var parameters=value.Get("parameters").AsGodotDictionary();using var preset=_definitions.create(id);var defaults=preset.Get("parameters").AsGodotDictionary();
        foreach(string name in new[]{"primary","secondary","density","thickness","roughness","distortion","detail","knots","contrast","brightness","seed"})result.SetShaderParameter(name,Get(parameters,name,Get(defaults,name)));
        long noiseKey=GD.Hash(new Godot.Collections.Array{family,variant,Get(parameters,"seed",0),Get(parameters,"frequency",.035),Get(parameters,"octaves",4),Get(parameters,"gain",.5),Get(parameters,"lacunarity",2)});
        if(!noises.ContainsKey(noiseKey))
        {
            if(noises.Count>=64)noises.Remove(noises.Keys.GetEnumerator().First());using var noise=new FastNoiseLite{Seed=Get(parameters,"seed",0).AsInt32(),Frequency=(float)Get(parameters,"frequency",.035).AsDouble(),FractalOctaves=Get(parameters,"octaves",4).AsInt32(),FractalGain=(float)Get(parameters,"gain",.5).AsDouble(),FractalLacunarity=(float)Get(parameters,"lacunarity",2).AsDouble()};
            if(family==9)noise.NoiseType=variant==3?FastNoiseLite.NoiseTypeEnum.Perlin:variant is 1 or 2?FastNoiseLite.NoiseTypeEnum.Value:FastNoiseLite.NoiseTypeEnum.SimplexSmooth;
            using var image=noise.GetSeamlessImage(128,128);noises[noiseKey]=ImageTexture.CreateFromImage(image);
        }
        void Set(string name,Variant data)=>result.SetShaderParameter(name,data);
        Set("noise_map",noises[noiseKey]);Set("extent",extent);Set("seamless",Get(parameters,"tileable",true));Set("metallic_override",value.Get("metallic"));Set("texture_size",value.Get("texture_size"));Set("angle",Mathf.DegToRad(value.Get("rotation").AsDouble()));
        string alignment=value.Get("alignment").AsString();Set("origin",alignment=="canvas"?frame.Origin:alignment=="stroke"?-value.Get("mapping_origin").AsVector2():Vector2.Zero);Set("axis_x",alignment=="canvas"?frame.X:Vector2.Right);Set("axis_y",alignment=="canvas"?frame.Y:Vector2.Down);
        Set("coverage_map",value.Get("coverage"));Set("masked",value.Get("coverage").AsGodotObject()!=null);Set("base_map",value.Get("source"));Set("image_map",value.Get("image"));var texture=value.Get("image").As<Texture2D>();Set("imported",texture!=null);
        if(texture!=null)Set("image_aspect",texture.GetSize()/Math.Max(1,Math.Min(texture.GetWidth(),texture.GetHeight())));
        Set("tint_strength",value.Get("tint_strength"));Set("tiling",Array.IndexOf(new[]{"repeat","mirror","clamp"},value.Get("tiling").AsString()));Set("blend_mode",Array.IndexOf(new[]{"replace","overlay","colorize","detail"},value.Get("blending").AsString()));
        Set("relief",value.Get("relief"));Set("light_angle",Mathf.DegToRad(value.Get("light_direction").AsDouble()));Set("highlight",value.Get("highlight"));Set("shadow",value.Get("shadow"));Set("relief_softness",value.Get("relief_softness"));Set("mixer_enabled",mixed);
        if(second!=null)
        {
            using var copied=_resources.copy_material(second);copied.Set("secondary",default(Variant));using var other=material(copied,extent,Transform2D.Identity,false);
            foreach(string name in new[]{"seamless","family","variant","primary","secondary","density","thickness","roughness","distortion","detail","knots","contrast","brightness","seed","noise_map","image_map","image_aspect","imported","texture_size"})Set("secondary_"+name,other.GetShaderParameter(name));
            Set("secondary_angle",Mathf.DegToRad(copied.Get("rotation").AsDouble()));Set("mix_amount",value.Get("mix_amount"));Set("mix_distribution",Array.IndexOf(new[]{"uniform","noise","patches","selection"},value.Get("mix_distribution").AsString()));Set("mix_mask",value.Get("mix_mask"));
        }
        return result;
    }
    public SubViewport prepare_preview(Node host,Resource value,Vector2I size,Vector2 extent,Transform2D frame,Texture2D? coordinates,Rect2 coordinateRect)
    {
        var viewport=new SubViewport{Disable3D=true,TransparentBg=true,Size=size,RenderTargetUpdateMode=SubViewport.UpdateMode.Always};host.AddChild(viewport);
        var rect=new ColorRect{Size=(Vector2)size,Material=material(value,extent==Vector2.Zero?(Vector2)size:extent,frame,true)};viewport.AddChild(rect);var shader=(ShaderMaterial)rect.Material;
        shader.SetShaderParameter("has_coordinate_map",coordinates!=null);shader.SetShaderParameter("coordinate_map",coordinates==null?default(Variant):Variant.From(coordinates));shader.SetShaderParameter("coordinate_rect",new Vector4(coordinateRect.Position.X,coordinateRect.Position.Y,coordinateRect.Size.X,coordinateRect.Size.Y));return viewport;
    }
    public Image complete_preview(SubViewport viewport){var image=viewport.GetTexture().GetImage();viewport.QueueFree();return image;}
}
internal static class ImageMaterialDictionaryEnumerator
{
    public static Variant First(this System.Collections.Generic.IEnumerator<Variant> iterator){using(iterator){iterator.MoveNext();return iterator.Current;}}
}
