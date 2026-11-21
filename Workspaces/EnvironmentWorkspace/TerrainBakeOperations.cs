using Godot;

public partial class TerrainBakeOperations : RefCounted
{
    public Material? freeze(Material? source)
    {
        if(source==null)return null;var result=(Material)source.Duplicate(true);
        if(source is ShaderMaterial shader && result is ShaderMaterial target && shader.Shader!=null)
        {
            foreach(var entry in shader.Shader.GetShaderUniformList())
            {
                string name=entry.AsGodotDictionary()["name"].AsString();Variant value=shader.GetShaderParameter(name);
                if(value.VariantType!=Variant.Type.Object)continue;
                if(value.AsGodotObject() is Texture2D texture)
                {using var image=texture.GetImage();if(image!=null&&!image.IsEmpty())target.SetShaderParameter(name,ImageTexture.CreateFromImage(image));}
                else if(value.AsGodotObject() is Texture3D volume)
                {
                    var images=volume.GetData();var copy=new ImageTexture3D();
                    if(images.Count>0 && copy.Create(volume.GetFormat(),volume.GetWidth(),volume.GetHeight(),volume.GetDepth(),volume.HasMipmaps(),images)==Error.Ok)target.SetShaderParameter(name,copy);
                }
            }
        }
        return result;
    }
}
