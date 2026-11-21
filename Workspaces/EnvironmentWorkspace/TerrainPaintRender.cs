using Godot;
using System;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class TerrainPaintRender : RefCounted
{
    private readonly EnvironmentAssetOperations _assets=new();
    private static readonly Vector4[] Channels={new(1,0,0,0),new(0,1,0,0),new(0,0,1,0),new(0,0,0,1),new(1f/3,1f/3,1f/3,0)};
    public Material? material(Node3D owner,Resource terrain,Material ground,Material paint,Settings revisions)
    {
        if(ground is not BaseMaterial3D baseGround || paint is not BaseMaterial3D basePaint) return null;
        var dimensions=terrain.Get("dimensions").AsVector2();int resolution=terrain.Get("resolution").AsInt32();var mask=terrain.Get("material_mask").AsFloat32Array();
        long key=unchecked((uint)GD.Hash(new GArray {dimensions,resolution,mask,_assets.content_stamp(ground,new Settings(),0,revisions),_assets.content_stamp(paint,new Settings(),0,revisions)}));
        if(owner.GetMeta("paint_render_key",-1).AsInt64()==key) return owner.GetMeta("paint_render_material").As<Material>();
        var bytes=new byte[checked(mask.Length*sizeof(float))];Buffer.BlockCopy(mask,0,bytes,0,bytes.Length);
        using var source=Image.CreateFromData(resolution,resolution,false,Image.Format.Rf,bytes); source.GenerateMipmaps();
        var result=owner.HasMeta("paint_render_material")?owner.GetMeta("paint_render_material").As<ShaderMaterial>():null;
        result ??= new ShaderMaterial {Shader=GD.Load<Shader>("res://Workspaces/EnvironmentWorkspace/terrain/terrain_paint.gdshader")};
        var texture=result.GetShaderParameter("paint_mask").As<ImageTexture>();
        if(texture!=null && texture.GetSize()==new Vector2(resolution,resolution)) texture.Update(source);else texture=ImageTexture.CreateFromImage(source);
        result.SetShaderParameter("paint_mask",texture);result.SetShaderParameter("terrain_size",dimensions);
        for(int index=0;index<2;index++)
        {
            var native=index==0?baseGround:basePaint;string prefix=index==0?"ground_":"paint_";
            result.SetShaderParameter(prefix+"color",native.AlbedoColor);result.SetShaderParameter(prefix+"texture",native.AlbedoTexture);
            result.SetShaderParameter(prefix+"normal",native.NormalTexture);result.SetShaderParameter(prefix+"scale",native.Uv1Scale);result.SetShaderParameter(prefix+"offset",native.Uv1Offset);
            result.SetShaderParameter(prefix+"roughness",native.Roughness);result.SetShaderParameter(prefix+"metallic",native.Metallic);result.SetShaderParameter(prefix+"normal_strength",native.NormalEnabled?native.NormalScale:0);
            result.SetShaderParameter(prefix+"roughness_texture",native.RoughnessTexture);result.SetShaderParameter(prefix+"metallic_texture",native.MetallicTexture);
            result.SetShaderParameter(prefix+"roughness_channel",Channels[Math.Clamp((int)native.RoughnessTextureChannel,0,4)]);result.SetShaderParameter(prefix+"metallic_channel",Channels[Math.Clamp((int)native.MetallicTextureChannel,0,4)]);
        }
        owner.SetMeta("paint_render_key",key);owner.SetMeta("paint_render_material",result);return result;
    }
}
