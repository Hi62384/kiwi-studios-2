using Godot;
using System;

public partial class ShaderPreviewAssets : RefCounted
{
    private static readonly object Gate=new();
    private static ImageTexture? _testTexture,_normalTexture,_particleTexture;
    internal static Texture2D TestTexture()
    {
        lock(Gate)
        {
            if(_testTexture!=null)return _testTexture;using var image=Image.CreateEmpty(192,192,false,Image.Format.Rgba8);
            for(int y=0;y<192;y++)for(int x=0;x<192;x++){var uv=new Vector2(x,y)/192;var color=new Color((x/24+y/24)%2==0?"e5c37e":"4687b9");if((uv-new Vector2(.5f,.5f)).Length()<.3)color=new Color("e96e60").Lerp(new Color("fff0b7"),uv.Y);color.A=(float)(1-Mathf.SmoothStep(.45,.49,Math.Max(Math.Abs(uv.X-.5),Math.Abs(uv.Y-.5))));image.SetPixel(x,y,color);}_testTexture=ImageTexture.CreateFromImage(image);return _testTexture;
        }
    }
    internal static Texture2D NormalTexture()
    {lock(Gate){if(_normalTexture!=null)return _normalTexture;using var image=Image.CreateEmpty(4,4,false,Image.Format.Rgba8);image.Fill(new Color(.5f,.5f,1,1));_normalTexture=ImageTexture.CreateFromImage(image);return _normalTexture;}}
    internal static QuadMesh ParticleDrawMesh()
    {
        lock(Gate)
        {
            if(_particleTexture==null){using var image=Image.CreateEmpty(64,64,false,Image.Format.Rgba8);for(int y=0;y<64;y++)for(int x=0;x<64;x++){double distance=(new Vector2(x,y)+new Vector2(.5f,.5f)-new Vector2(32,32)).Length()/32;image.SetPixel(x,y,new Color(1,1,1,(float)(1-Mathf.SmoothStep(.25,1,distance))));}_particleTexture=ImageTexture.CreateFromImage(image);}
            return new QuadMesh {Size=Vector2.One,Material=new StandardMaterial3D {ShadingMode=BaseMaterial3D.ShadingModeEnum.Unshaded,VertexColorUseAsAlbedo=true,BillboardMode=BaseMaterial3D.BillboardModeEnum.Particles,BillboardKeepScale=true,Transparency=BaseMaterial3D.TransparencyEnum.Alpha,AlbedoTexture=_particleTexture}};
        }
    }
    public Texture2D test_texture()=>TestTexture();
    public Texture2D normal_texture()=>NormalTexture();
    public QuadMesh particle_draw_mesh()=>ParticleDrawMesh();
    internal static void ClearCache(){lock(Gate){_testTexture?.Dispose();_normalTexture?.Dispose();_particleTexture?.Dispose();_testTexture=null;_normalTexture=null;_particleTexture=null;}}
}
