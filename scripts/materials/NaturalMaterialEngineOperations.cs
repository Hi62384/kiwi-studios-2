using Godot;
using System;
using GArray=Godot.Collections.Array;
using Settings=Godot.Collections.Dictionary;
public partial class NaturalMaterialEngineOperations:RefCounted
{
    private readonly NaturalMaterialDefinitionOperations _definitions=new();private readonly NaturalMaterialShaderSourceOperations _source=new();private readonly ImageTextureMaterialRendererOperations _canvas=new();private readonly ImageMaterialResourceOperations _resources=new();
    private static GDScript Bridge=>GD.Load<GDScript>("res://scripts/materials/natural_material_engine.gd");
    private static Variant Get(Settings d,string key,Variant fallback=default)=>d.TryGetValue(key,out var value)?value:fallback;
    private static GArray Constant(string name)=>Bridge.GetScriptConstantMap()[name].AsGodotArray();
    public GArray definitions(){var result=new GArray();foreach(var id in _definitions.ids())result.Add(_definitions.definition(id.AsString()));return result;}
    public Settings defaults(string id){using var material=_definitions.create(id);return settings_from_material(material);}
    public Settings normalize(Settings settings){using var material=material_from_settings(settings);return settings_from_material(material);}
    public Resource material_from_settings(Settings settings)
    {
        string id=Get(settings,"material_id","wood/oak").AsString();if(!_definitions.ids().Contains(id))id="wood/oak";var value=_definitions.create(id);var parameters=Get(settings,"parameters",new Settings()).AsGodotDictionary();var target=value.Get("parameters").AsGodotDictionary();var keys=new System.Collections.Generic.List<Variant>(target.Keys);
        foreach(var key in keys)if(parameters.TryGetValue(key,out var next))
        {
            if(key.AsString() is "primary" or "secondary")
            {
                if(next.VariantType==Variant.Type.String)next=Color.FromString(next.AsString(),target[key].AsColor());
                else if(next.VariantType==Variant.Type.Array){var array=next.AsGodotArray();if(array.Count>=3)next=new Color(array[0].AsSingle(),array[1].AsSingle(),array[2].AsSingle(),array.Count>3?array[3].AsSingle():1);}
            }
            target[key]=next;
        }
        foreach(var field in Constant("MATERIAL_FIELDS"))if(settings.TryGetValue(field,out var next))value.Set(field.AsString(),next);
        value.Set("texture_size",Math.Max(1,value.Get("texture_size").AsDouble()));value.Set("surface_mapping",Get(settings,"mapping",Get(settings,"surface_mapping","uv")));value.Set("triplanar_sharpness",Math.Clamp(Get(settings,"triplanar_sharpness",4.0).AsDouble(),1,16));value.Set("format_version",2);
        var secondary=Get(settings,"secondary");if(secondary.VariantType==Variant.Type.Dictionary)value.Set("secondary",material_from_settings(secondary.AsGodotDictionary()));return value;
    }
    public Settings settings_from_material(Resource value)
    {
        var result=new Settings{["version"]=2,["material_id"]=value.Get("material_id"),["parameters"]=value.Get("parameters").AsGodotDictionary().Duplicate(true),["mapping"]=value.Get("surface_mapping"),["triplanar_sharpness"]=value.Get("triplanar_sharpness")};foreach(var field in Constant("MATERIAL_FIELDS"))result[field]=value.Get(field.AsString());var secondary=value.Get("secondary").As<Resource>();if(secondary!=null)result["secondary"]=settings_from_material(secondary);return result;
    }
    public ShaderMaterial canvas_material(Resource value,Vector2 extent,Transform2D frame,bool straightOutput)=>_canvas.material(value,extent,frame,straightOutput);
    public ShaderMaterial create_spatial_material(Settings settings){var material=new ShaderMaterial();configure_spatial(material,settings);return material;}
    public ShaderMaterial spatial_material(Resource value)=>create_spatial_material(settings_from_material(value));
    public void configure_spatial(ShaderMaterial material,Settings settings)
    {
        using var value=material_from_settings(settings);string id=value.Get("material_id").AsString();var secondary=value.Get("secondary").As<Resource>();string key=id+(secondary!=null&&value.Get("mix_amount").AsDouble()>0?"/"+secondary.Get("material_id").AsString():"");var shaders=Bridge.Get("_spatial_shaders").AsGodotDictionary();
        if(!shaders.ContainsKey(key)){var shader=new Shader{Code=_source.constants(spatial_source(value),id,"")};if(shaders.Count>=32)shaders.Remove(shaders.Keys.GetEnumerator().First());shaders[key]=shader;}material.Shader=shaders[key].As<Shader>();using var canvas=_canvas.material(value,new Vector2(256,256),Transform2D.Identity,false);
        foreach(var parameter in Constant("PARAMETERS"))material.SetShaderParameter(parameter.AsString(),canvas.GetShaderParameter(parameter.AsString()));if(secondary!=null){foreach(var parameter in Constant("PARAMETERS"))material.SetShaderParameter("secondary_"+parameter.AsString(),canvas.GetShaderParameter("secondary_"+parameter.AsString()));foreach(string parameter in new[]{"mix_amount","mix_distribution","mix_mask"})material.SetShaderParameter(parameter,canvas.GetShaderParameter(parameter));}
        material.SetShaderParameter("triplanar",value.Get("surface_mapping").AsString()=="triplanar");material.SetShaderParameter("triplanar_sharpness",value.Get("triplanar_sharpness"));material.ResourceName=value.Get("label").AsString();
    }
    private const string SpatialHeader="shader_type spatial;\nrender_mode diffuse_burley,specular_schlick_ggx;\nuniform sampler2D noise_map:repeat_enable,filter_linear;\nuniform sampler2D image_map:repeat_enable,filter_linear_mipmap;\nuniform bool imported=false;\nuniform vec2 image_aspect=vec2(1.);\nuniform float tint_strength=0.;\nuniform int family=1; uniform int variant=0;\nuniform vec4 primary:source_color=vec4(.2,.1,.05,1.);\nuniform vec4 secondary:source_color=vec4(.7,.4,.2,1.);\nuniform float density=1.; uniform float thickness=.15; uniform float roughness=.45;\nuniform float distortion=.35; uniform float detail=.6; uniform float knots=.35;\nuniform float contrast=1.; uniform float brightness=0.; uniform float seed=0.;\nuniform bool seamless=true;\nuniform float texture_size=64.; uniform float angle=0.; uniform float relief=.3;\nuniform float metallic_override=-1.;\nuniform bool triplanar=false; uniform float triplanar_sharpness=4.;\nvarying vec3 object_position; varying vec3 object_normal;\nvoid vertex(){object_position=VERTEX;object_normal=NORMAL;}\n";
    private const string SpatialFragment="\nvec2 mapped(vec2 uv){return mat2(vec2(cos(angle),sin(angle)),vec2(-sin(angle),cos(angle)))*uv*256./max(1.,texture_size)*16.;}\nfloat surface_height(vec2 p){return pattern(p);}\nvoid fragment(){\n vec2 p=mapped(UV);float height=surface_height(p);vec4 color=natural_color(p,height);vec2 surface=natural_surface(p,height);\n if(triplanar){\n  vec3 weights=pow(abs(normalize(object_normal)),vec3(triplanar_sharpness));weights/=max(.0001,weights.x+weights.y+weights.z);\n  vec2 px=mapped(object_position.zy*.5),py=mapped(object_position.xz*.5),pz=mapped(object_position.xy*.5);\n  float hx=surface_height(px),hy=surface_height(py),hz=surface_height(pz);\n  height=dot(vec3(hx,hy,hz),weights);\n  color=natural_color(px,hx)*weights.x+natural_color(py,hy)*weights.y+natural_color(pz,hz)*weights.z;\n  surface=natural_surface(px,hx)*weights.x+natural_surface(py,hy)*weights.y+natural_surface(pz,hz)*weights.z;\n }\n if(imported){color=texture(image_map,p/16./image_aspect);color.rgb=mix(color.rgb,color.rgb*primary.rgb,tint_strength);height=dot(color.rgb,vec3(.2126,.7152,.0722));}\n // SECONDARY_SAMPLE\n ALBEDO=color.rgb;ROUGHNESS=surface.x;METALLIC=metallic_override<0.?surface.y:metallic_override;\n // Screen derivatives produce a surface gradient in the actual tangent plane.\n // This works for UV and triplanar projections without an external normal texture.\n vec3 dpdx=dFdx(VERTEX),dpdy=dFdy(VERTEX);vec3 r1=cross(dpdy,NORMAL),r2=cross(NORMAL,dpdx);\n float det=dot(dpdx,r1);float dhdx=dFdx(height),dhdy=dFdy(height);\n vec3 gradient=sign(det)*(dhdx*r1+dhdy*r2);\n NORMAL=normalize(abs(det)*NORMAL-clamp(relief,-2.,2.)*.015*gradient);\n}\n";
    private const string SecondaryHeader="uniform sampler2D secondary_noise_map:repeat_enable,filter_linear;\nuniform sampler2D secondary_image_map:repeat_enable,filter_linear_mipmap;\nuniform sampler2D mix_mask:hint_default_white;\nuniform int secondary_family=0;uniform int secondary_variant=0;\nuniform vec4 secondary_primary:source_color=vec4(0.);uniform vec4 secondary_secondary:source_color=vec4(1.);\nuniform float secondary_density=1.;uniform float secondary_thickness=.15;uniform float secondary_roughness=.45;\nuniform float secondary_distortion=.35;uniform float secondary_detail=.6;uniform float secondary_knots=.35;\nuniform float secondary_contrast=1.;uniform float secondary_brightness=0.;uniform float secondary_seed=0.;\nuniform bool secondary_seamless=true;uniform bool secondary_imported=false;uniform vec2 secondary_image_aspect=vec2(1.);\nuniform float secondary_texture_size=64.;uniform float secondary_angle=0.;uniform float mix_amount=0.;uniform int mix_distribution=0;\n";
    private const string SecondarySample="vec2 p2=mat2(vec2(cos(secondary_angle),sin(secondary_angle)),vec2(-sin(secondary_angle),cos(secondary_angle)))*UV*256./max(1.,secondary_texture_size)*16.;\n float height2=secondary_pattern(p2);vec4 color2=secondary_natural_color(p2,height2);vec2 surface2=secondary_natural_surface(p2,height2);\n if(secondary_imported){color2=texture(secondary_image_map,p2/16./secondary_image_aspect);height2=dot(color2.rgb,vec3(.2126,.7152,.0722));}\n float amount=mix_amount;\n if(mix_distribution==1){amount*=smoothstep(.25,.75,n(p*4.))*2.;}\n if(mix_distribution==2){amount*=smoothstep(.25,.75,cell(p*.3).z)*2.;}\n if(mix_distribution==3){amount*=texture(mix_mask,UV).a;}\n amount=clamp(amount,0.,1.);color=mix(color,color2,amount);height=mix(height,height2,amount);surface=mix(surface,surface2,amount);\n";
    public string spatial_source(Resource value)
    {
        string source=GD.Load<GDScript>("res://scripts/materials/natural_material_shader_source.gd").Get("source").AsString();string code=SpatialHeader+_source.pattern_source(source,value.Get("material_id").AsString())+SpatialFragment;var secondary=value.Get("secondary").As<Resource>();
        if(secondary!=null&&value.Get("mix_amount").AsDouble()>0){code=code.Replace("varying vec3 object_position;",SecondaryHeader+"varying vec3 object_position;");code=code.Replace("vec2 mapped(vec2 uv)",_source.secondary_source(source,secondary.Get("material_id").AsString())+"\nvec2 mapped(vec2 uv)");code=_source.constants(code,secondary.Get("material_id").AsString(),"secondary_");code=code.Replace("// SECONDARY_SAMPLE",SecondarySample);}return code;
    }
    public Settings map_request(Resource value,Vector2I size)
    {
        var data=settings_from_material(value);var image=value.Get("image").As<Texture2D>();if(image!=null)data["image_identity"]=image.GetInstanceId();return new Settings{["signature"]=GD.VarToBytes(data).HexEncode().Sha256Text(),["size"]=new Vector2I(Math.Clamp(size.X,1,4096),Math.Clamp(size.Y,1,4096))};
    }
    public Settings prepare_map(Node host,Resource value,Settings request,string output)
    {
        int mode=Array.IndexOf(new[]{"albedo","height","normal","roughness","metallic"},output);if(mode<0)return new Settings();var size=request["size"].AsVector2I();string key=request["signature"].AsString()+"/"+size+"/"+output;var cache=Bridge.Get("_maps_cache").AsGodotDictionary();if(cache.ContainsKey(key))return new Settings{["image"]=cache[key].As<Image>().Duplicate()};
        var viewport=new SubViewport{Disable3D=true,TransparentBg=true,Size=size,RenderTargetUpdateMode=SubViewport.UpdateMode.Always};host.AddChild(viewport);var rect=new ColorRect{Size=(Vector2)size};using var copy=_resources.copy_material(value);copy.Set("coverage",default(Variant));copy.Set("source",default(Variant));copy.Set("blending","replace");if(output=="albedo")copy.Set("relief",0.0);var shader=_canvas.material(copy,new Vector2(256,256),Transform2D.Identity,true);shader.SetShaderParameter("output_mode",mode);rect.Material=shader;viewport.AddChild(rect);return new Settings{["viewport"]=viewport,["key"]=key,["size"]=size};
    }
    public Image? complete_map(Settings state)
    {
        var viewport=state["viewport"].As<SubViewport>();var image=viewport.GetTexture().GetImage();viewport.QueueFree();if(image==null)return null;var size=state["size"].AsVector2I();if(size.X*size.Y<=512*512){var cache=Bridge.Get("_maps_cache").AsGodotDictionary();var order=Bridge.Get("_map_order").AsGodotArray();while(order.Count>=32){cache.Remove(order[0]);order.RemoveAt(0);}order.Add(state["key"]);cache[state["key"]]=image.Duplicate();}return image;
    }
    public void clear_cache(){Bridge.Get("_maps_cache").AsGodotDictionary().Clear();Bridge.Get("_map_order").AsGodotArray().Clear();}
}
