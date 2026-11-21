using Godot;
using System;
using System.Text.RegularExpressions;
using Settings=Godot.Collections.Dictionary;

public partial class ShaderSamplePreview : SubViewport
{
    public ShaderMaterial material {get;set;}=new();
    public Shader shader {get;set;}=new();
    public string error_text {get;set;}="";
    public string kind {get;set;}="";
    public Node3D _root {get;set;}=new();
    public MeshInstance3D _mesh {get;set;}=new();
    public Camera3D _camera {get;set;}=new();
    public WorldEnvironment _environment {get;set;}=new();
    public FogVolume _fog {get;set;}=new();
    public GpuParticles3D _particles {get;set;}=new();
    public TextureRect _canvas {get;set;}=new();
    public TextureRect _background {get;set;}=new();
    public ShaderPreviewLogger _logger {get;set;}=new();
    public double _distance {get;set;}=3.5;
    public double _yaw {get;set;}=.35;
    public double _pitch {get;set;}=-.15;
    public string _geometry {get;set;}="sphere";
    public bool _active {get;set;}
    private bool _loggerRegistered;
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    public override void _Ready()
    {
        Size=new Vector2I(384,256);OwnWorld3D=true;TransparentBg=false;RenderTargetUpdateMode=UpdateMode.Disabled;OS.AddLogger(_logger);_loggerRegistered=true;AddChild(_root);_root.AddChild(_mesh);_root.AddChild(_camera);_camera.Current=true;_camera.Fov=46;_root.AddChild(_environment);_environment.Environment=new Godot.Environment {BackgroundMode=Godot.Environment.BGMode.Color,BackgroundColor=new Color("152233"),AmbientLightSource=Godot.Environment.AmbientSource.Color,AmbientLightColor=new Color("c8dcf5"),AmbientLightEnergy=.45f,TonemapMode=Godot.Environment.ToneMapper.Filmic};
        foreach(var spec in new[]{(new Vector3(-40,-35,0),1.8f,Colors.White),(new Vector3(25,140,0),.8f,new Color("7dadf2"))})_root.AddChild(new DirectionalLight3D {RotationDegrees=spec.Item1,LightEnergy=spec.Item2,LightColor=spec.Item3});_root.AddChild(_fog);_fog.Size=Vector3.One*2.8f;_root.AddChild(_particles);_particles.Amount=180;_particles.Lifetime=3;_particles.Preprocess=1.8;_particles.VisibilityAabb=new Aabb(new Vector3(-8,-8,-8),new Vector3(16,16,16));_particles.DrawPass1=ShaderPreviewAssets.ParticleDrawMesh();
        foreach(var rectangle in new[]{_background,_canvas}){rectangle.ExpandMode=TextureRect.ExpandModeEnum.IgnoreSize;rectangle.StretchMode=TextureRect.StretchModeEnum.Scale;rectangle.MouseFilter=Control.MouseFilterEnum.Ignore;rectangle.Size=Size;rectangle.Texture=ShaderPreviewAssets.TestTexture();AddChild(rectangle);}set_geometry("sphere");_update_camera();
    }
    public override void _ExitTree(){_logger.capturing=false;if(_loggerRegistered){OS.RemoveLogger(_logger);_loggerRegistered=false;}}
    public string show_entry(Settings entry)
    {
        _logger.capturing=false;_logger.clear();error_text="";kind=Get(entry,"shader_type","spatial").AsString();if(DisplayServer.GetName()=="headless")error_text="Rendered previews require a graphics display; headless mode cannot render these shaders.";else if(kind=="fog"&&RenderingServer.GetCurrentRenderingMethod()!="forward_plus")error_text="FogVolume previews require the Forward+ renderer.";if(error_text.Length>0){set_active(false);return error_text;}
        string source=Get(entry,"source","").AsString(),path=Get(entry,"path","").AsString();if(source.Length==0&&FileAccess.FileExists(path))source=FileAccess.GetFileAsString(path);if(!Regex.IsMatch(source,@"(?m)^\s*shader_type\s+"+Regex.Escape(kind)+@"\s*;")){error_text="Missing or mismatched shader_type declaration.";set_active(false);return error_text;}_logger.capturing=true;shader=new Shader {Code=source};material=new ShaderMaterial {Shader=shader};
        foreach(var rawUniform in shader.GetShaderUniformList())
        {
            var uniform=rawUniform.AsGodotDictionary();
            if(Get(uniform,"type",0).AsInt32()!=(int)Variant.Type.Object)continue;string name=uniform["name"].AsString();var declaration=Regex.Match(source,@"uniform\s+sampler2D\s+"+Regex.Escape(name)+@"\b[^;]*;");if(!declaration.Success)continue;string text=declaration.Value;if(text.Contains("hint_screen_texture",StringComparison.Ordinal)||text.Contains("hint_depth_texture",StringComparison.Ordinal)||text.Contains("hint_normal_roughness_texture",StringComparison.Ordinal))continue;if(text.Contains("hint_normal",StringComparison.Ordinal)||name.Contains("normal",StringComparison.Ordinal))material.SetShaderParameter(name,ShaderPreviewAssets.NormalTexture());else if(name is "source_texture" or "albedo_texture" or "texture_a" or "texture_b")material.SetShaderParameter(name,ShaderPreviewAssets.TestTexture());
        }
        _mesh.Visible=kind=="spatial";_fog.Visible=kind=="fog";_particles.Visible=kind=="particles";_particles.Emitting=kind=="particles";_canvas.Visible=kind=="canvas_item";_background.Visible=kind=="canvas_item"&&source.Contains("hint_screen_texture",StringComparison.Ordinal);foreach(var rectangle in new[]{_background,_canvas})rectangle.Size=Size;_canvas.Material=kind=="canvas_item"?material:null;_mesh.MaterialOverride=kind=="spatial"?material:null;_fog.Material=kind=="fog"?material:null;_particles.ProcessMaterial=kind=="particles"?material:null;var environment=_environment.Environment;environment.VolumetricFogEnabled=kind=="fog";environment.VolumetricFogDensity=0;environment.BackgroundMode=kind=="sky"?Godot.Environment.BGMode.Sky:Godot.Environment.BGMode.Color;environment.Sky=kind=="sky"?new Sky {SkyMaterial=material}:null;set_geometry(Get(entry,"preview_mesh","sphere").AsString());if(kind=="particles")_particles.Restart();_distance=kind is "fog" or "particles"?4.6:3.5;_yaw=.35;_pitch=kind=="sky"?.35:-.15;_update_camera();set_active(true);return check_errors();
    }
    public string check_errors(){var errors=_logger.messages();if(errors.Length>0){error_text="Shader compilation failed:\n"+string.Join("\n",errors);set_active(false);}return error_text;}
    public void finish_compilation()=>_logger.capturing=false;
    public void set_active(bool value){_active=value;RenderTargetUpdateMode=value?UpdateMode.Always:UpdateMode.Disabled;_particles.SpeedScale=value?1:0;if(!value)_logger.capturing=false;}
    public void set_geometry(string value)
    {
        _geometry=value;switch(value){case "plane":_mesh.Mesh=new PlaneMesh {Size=new Vector2(2.1f,2.1f),SubdivideWidth=64,SubdivideDepth=64};_mesh.RotationDegrees=new Vector3(70,0,0);break;case "cube":case "box":_mesh.Mesh=new BoxMesh {Size=Vector3.One*1.55f,SubdivideWidth=20,SubdivideHeight=20,SubdivideDepth=20};_mesh.RotationDegrees=Vector3.Zero;break;default:_mesh.Mesh=new SphereMesh {Radius=.95f,Height=1.9f,RadialSegments=64,Rings=32};_mesh.RotationDegrees=Vector3.Zero;break;}
    }
    public void orbit(Vector2 delta){_yaw-=delta.X*.008;_pitch=Math.Clamp(_pitch-delta.Y*.008,-1.3,1.3);_update_camera();}
    public void zoom(double factor){_distance=Math.Clamp(_distance*factor,1.5,10);_update_camera();}
    public void _update_camera(){_camera.Position=new Vector3((float)(Math.Sin(_yaw)*Math.Cos(_pitch)),(float)Math.Sin(-_pitch),(float)(Math.Cos(_yaw)*Math.Cos(_pitch)))*(float)_distance;_camera.LookAt(Vector3.Zero,Vector3.Up);}
}
