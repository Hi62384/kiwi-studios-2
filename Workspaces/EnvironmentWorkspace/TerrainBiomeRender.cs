using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class TerrainBiomeRender : RefCounted
{
    private sealed record Layer(string Id,BaseMaterial3D Material,double Weight);
    private readonly EnvironmentAssetOperations _assets=new();
    private int _capacity=-1;
    private Shader? _shader;
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private static byte[] Bytes(float[] values){var bytes=new byte[checked(values.Length*sizeof(float))];Buffer.BlockCopy(values,0,bytes,0,bytes.Length);return bytes;}
    private static readonly Vector4[] Channels={new(1,0,0,0),new(0,1,0,0),new(0,0,1,0),new(0,0,0,1),new(1f/3,1f/3,1f/3,0)};
    public int capacity()
    {
        if(_capacity>0)return _capacity;_capacity=4;var device=RenderingServer.GetRenderingDevice();
        if(device!=null){long limit=(long)device.LimitGet(RenderingDevice.Limit.MaxTexturesPerShaderStage);if(limit<0||limit>=64)_capacity=8;}return _capacity;
    }
    public Material? material(Node3D owner,Resource terrain,Material ground,Material paint,Settings revisions)
    {
        owner.SetMeta("biome_material_warnings",Array.Empty<string>());var biomes=terrain.Get("biomes").As<Resource>();var data=terrain.Get("biome_data").AsGodotDictionary();
        if(biomes==null||data.Count==0||ground is not BaseMaterial3D baseGround)return null;
        var layers=new List<Layer>();var warnings=new List<string>();
        foreach(var entry in biomes.Get("definitions").AsGodotArray())
        {
            var definition=entry.AsGodotDictionary();if(!Get(definition,"enabled",true).AsBool())continue;
            var accepted=new List<Layer>();double total=0;
            foreach(var source in Get(definition,"materials",new GArray()).AsGodotArray())
            {
                var specification=source.VariantType==Variant.Type.Dictionary?source.AsGodotDictionary():null;Variant value=specification!=null?Get(specification,"source"):source;
                var native=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/environment_assets.gd").Call("material",value).As<Material>();
                if(native is not BaseMaterial3D pbr){warnings.Add($"Biome {Get(definition,"name", "").AsString()} needs a native PBR material for surface blending.");continue;}
                double weight=specification!=null?Math.Max(0,Get(specification,"weight",1.0).AsDouble()):1;total+=weight;accepted.Add(new Layer(definition["id"].AsString(),pbr,weight));
            }
            foreach(var layer in accepted){if(layers.Count==capacity()){warnings.Add($"Biome material budget reached ({capacity()} surfaces on this renderer). Split terrain or reduce its material palette.");break;}layers.Add(layer with {Weight=layer.Weight/Math.Max(.000001,total)});}
        }
        owner.SetMeta("biome_material_warnings",warnings.ToArray());if(layers.Count==0)return null;
        var natives=new List<BaseMaterial3D>{baseGround,paint as BaseMaterial3D??baseGround};natives.AddRange(layers.Select(layer=>layer.Material));
        using var stamps=new GArray();foreach(var native in natives)stamps.Add(_assets.content_stamp(native,new Settings(),0,revisions));
        var dimensions=terrain.Get("dimensions").AsVector2();int resolution=terrain.Get("resolution").AsInt32();var mask=terrain.Get("material_mask").AsFloat32Array();
        long key=unchecked((uint)GD.Hash(new GArray {dimensions,resolution,mask,terrain.Get("biome_key"),terrain.Get("cave_biome_key"),Get(data,"preview_revision",0),biomes.Call("signature"),stamps}));
        if(owner.GetMeta("biome_render_key",-1).AsInt64()==key)return owner.GetMeta("biome_render_material").As<Material>();
        var result=owner.HasMeta("biome_render_material")?owner.GetMeta("biome_render_material").As<ShaderMaterial>():null;result??=new ShaderMaterial {Shader=shader()};
        int count=resolution*resolution,layerCount=capacity()+2,mapCount=(layerCount+3)/4;var channels=new float[mapCount][];for(int map=0;map<mapCount;map++)channels[map]=new float[count*4];
        var weights=Get(data,"weights",new Settings()).AsGodotDictionary();var fields=layers.Select(layer=>Get(weights,layer.Id,Array.Empty<float>()).AsFloat32Array()).ToArray();
        for(int index=0;index<count;index++)
        {
            double painted=paint is BaseMaterial3D?Math.Clamp(mask[index],0,1):0,biomeTotal=0;channels[0][index*4+1]=(float)painted;
            for(int layer=0;layer<layers.Count;layer++){double weight=fields[layer].Length==count?fields[layer][index]*layers[layer].Weight:0;int slot=layer+2;channels[slot/4][index*4+slot%4]=(float)((1-painted)*weight);biomeTotal+=weight;}
            channels[0][index*4]=(float)((1-painted)*Math.Max(0,1-biomeTotal));
        }
        for(int map=0;map<mapCount;map++)
        {
            using var image=Image.CreateFromData(resolution,resolution,false,Image.Format.Rgbaf,Bytes(channels[map]));image.GenerateMipmaps();string name=$"weights{map}";var texture=result.GetShaderParameter(name).As<ImageTexture>();
            if(texture!=null&&texture.GetSize()==new Vector2(resolution,resolution))texture.Update(image);else texture=ImageTexture.CreateFromImage(image);result.SetShaderParameter(name,texture);
        }
        result.SetShaderParameter("terrain_size",dimensions);
        for(int index=0;index<layerCount;index++)BindSurface(result,$"layer{index}_",index<natives.Count?natives[index]:baseGround);
        BindCave(owner,result,terrain,layers);owner.SetMeta("biome_render_key",key);owner.SetMeta("biome_render_material",result);return result;
    }
    private static void BindSurface(ShaderMaterial result,string prefix,BaseMaterial3D native)
    {
        result.SetShaderParameter(prefix+"color",native.AlbedoColor);result.SetShaderParameter(prefix+"texture",native.AlbedoTexture);result.SetShaderParameter(prefix+"normal",native.NormalTexture);
        result.SetShaderParameter(prefix+"scale",native.Uv1Scale);result.SetShaderParameter(prefix+"offset",native.Uv1Offset);result.SetShaderParameter(prefix+"roughness",native.Roughness);result.SetShaderParameter(prefix+"metallic",native.Metallic);
        result.SetShaderParameter(prefix+"normal_strength",native.NormalEnabled?native.NormalScale:0);result.SetShaderParameter(prefix+"roughness_texture",native.RoughnessTexture);result.SetShaderParameter(prefix+"metallic_texture",native.MetallicTexture);
        result.SetShaderParameter(prefix+"roughness_channel",Channels[Math.Clamp((int)native.RoughnessTextureChannel,0,4)]);result.SetShaderParameter(prefix+"metallic_channel",Channels[Math.Clamp((int)native.MetallicTextureChannel,0,4)]);
    }
    public void bind_cave(Node3D owner,ShaderMaterial material,Resource terrain,GArray layers)
    {BindCave(owner,material,terrain,layers.Select(entry=>entry.AsGodotDictionary()).Select(value=>new Layer(value["id"].AsString(),value["source"].As<BaseMaterial3D>(),value["weight"].AsDouble())).ToList());}
    private void BindCave(Node3D owner,ShaderMaterial material,Resource terrain,List<Layer> layers)
    {
        var data=terrain.Get("cave_biome_data").AsGodotDictionary();material.SetShaderParameter("has_cave_fields",false);if(data.Count==0)return;
        var size=data["size"].AsVector3I();int maps=(capacity()+3)/4;var images=new Godot.Collections.Array<Image>[maps];for(int map=0;map<maps;map++)images[map]=new();var masks=new Godot.Collections.Array<Image>();
        var fields=data["weights"].AsGodotDictionary();var samples=layers.Select(layer=>Get(fields,layer.Id,Array.Empty<float>()).AsFloat32Array()).ToArray();var presence=data["presence"].AsByteArray();
        for(int z=0;z<size.Z;z++)
        {
            var channels=new float[maps][];for(int map=0;map<maps;map++)channels[map]=new float[size.X*size.Y*4];var mask=new float[size.X*size.Y];
            for(int index=0;index<mask.Length;index++){int source=index+z*mask.Length;mask[index]=presence[source];for(int layer=0;layer<samples.Length;layer++)if(samples[layer].Length>0)channels[layer/4][index*4+layer%4]=(float)(samples[layer][source]*layers[layer].Weight);}
            for(int map=0;map<maps;map++)images[map].Add(Image.CreateFromData(size.X,size.Y,false,Image.Format.Rgbaf,Bytes(channels[map])));masks.Add(Image.CreateFromData(size.X,size.Y,false,Image.Format.Rf,Bytes(mask)));
        }
        if(!Volume(owner,material,"cave_presence",masks,Image.Format.Rf,size))return;
        for(int map=0;map<maps;map++)if(!Volume(owner,material,map==0?"cave_weights":$"cave_weights{map}",images[map],Image.Format.Rgbaf,size))return;
        var spacing=data["spacing"].AsVector3();material.SetShaderParameter("cave_origin",data["origin"].AsVector3()-spacing*.5f);material.SetShaderParameter("cave_extent",(Vector3)size*spacing);material.SetShaderParameter("has_cave_fields",true);
    }
    private static bool Volume(Node3D owner,ShaderMaterial material,string name,Godot.Collections.Array<Image> images,Image.Format format,Vector3I size)
    {
        var texture=material.GetShaderParameter(name).As<ImageTexture3D>();
        if(texture!=null&&texture.GetWidth()==size.X&&texture.GetHeight()==size.Y&&texture.GetDepth()==size.Z)texture.Update(images);
        else {texture=new ImageTexture3D();if(texture.Create(format,size.X,size.Y,size.Z,false,images)!=Error.Ok){var warnings=owner.GetMeta("biome_material_warnings",Array.Empty<string>()).AsStringArray().ToList();warnings.Add("This renderer could not upload the cave biome volume.");owner.SetMeta("biome_material_warnings",warnings.ToArray());return false;}}
        material.SetShaderParameter(name,texture);return true;
    }
}
