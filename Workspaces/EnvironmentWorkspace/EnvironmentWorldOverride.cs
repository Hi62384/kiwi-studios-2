using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings=Godot.Collections.Dictionary;

public partial class EnvironmentWorldOverride : Node
{
    public Godot.Collections.Array<WeakRef> entries {get;set;}=new();
    private WeakRef? _worldReference;
    public World3D? world
    {get{if(_worldReference==null)return null;using var reference=_worldReference.GetRef();return reference.As<World3D>();}set{_worldReference?.Dispose();_worldReference=value!=null?GodotObject.WeakRef(value):null;}}
    public Godot.Environment? original {get;set;}
    public Godot.Environment? owned {get;set;}
    public long owner_key {get;set;}
    private readonly EnvironmentWeatherRuntime _weather=new();
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private static Node3D? Content(Node runtime)=>runtime.Get("content").As<Node3D>();
    private static Resource? Document(Node runtime)=>runtime.Get("source_document").As<Resource>();
    private static GDScript Assets()=>GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/environment_assets.gd");
    internal static void Attach(Node3D runtime)
    {var viewport=runtime.GetViewport();var coordinator=viewport.GetNodeOrNull<EnvironmentWorldOverride>("KiwiEnvironmentWorld");if(coordinator==null){coordinator=new EnvironmentWorldOverride {Name="KiwiEnvironmentWorld",world=viewport.FindWorld3D(),ProcessPriority=90};viewport.AddChild(coordinator);}coordinator.entries.Add(GodotObject.WeakRef(runtime)!);}
    public Godot.Environment? underlying()
    {if(world==null)return null;var fog=GetViewport().GetNodeOrNull("KiwiFogEnvironment");if(fog!=null&&world.Environment==fog.Get("overlay").As<Godot.Environment>())return fog.Get("source").As<Godot.Environment>();return world.Environment;}
    public override void _Process(double delta)=>Tick();
    public void _process(double delta)=>Tick();
    private void ClearWeather(Node runtime)
    {var content=Content(runtime);if(content!=null)_weather.update(content,new Settings(),null);}
    private void Restore()
    {if(owner_key!=0&&world!=null&&underlying()==owned)world.Environment=original;owner_key=0;owned=null;original=null;}
    private void Tick()
    {
        if(world==null)return;var active=new List<Node>();for(int index=entries.Count-1;index>=0;index--){var runtime=entries[index].GetRef().As<Node>();if(runtime==null){entries.RemoveAt(index);continue;}var content=Content(runtime);if(runtime.Get("active").AsBool()&&content!=null&&content.Get("include_atmosphere").AsBool()&&Document(runtime)!=null)active.Add(runtime);}active.Sort((a,b)=>string.CompareOrdinal(a.Get("actor").As<Resource>().Get("id").AsString(),b.Get("actor").As<Resource>().Get("id").AsString()));if(active.Count==0){foreach(var entry in entries){var inactive=entry.GetRef().As<Node>();if(inactive!=null)ClearWeather(inactive);}if(owner_key!=0)Restore();return;}var chosen=active[0];foreach(var entry in entries){var candidate=entry.GetRef().As<Node>();if(candidate!=null&&candidate!=chosen)ClearWeather(candidate);}var document=Document(chosen)!;using var keyValues=new Godot.Collections.Array {chosen.Get("actor").As<Resource>().Get("id"),unchecked((long)document.GetInstanceId()),Assets().Call("world_stamp",document)};long key=unchecked((uint)GD.Hash(keyValues));if(key==owner_key){sync_sky_time(chosen);return;}var next=Assets().Call("world_environment",document).As<Godot.Environment>();var climate=document.Get("climate").As<Resource>();if(climate!=null&&climate.HasMethod("make_environment"))next=next!=null?(Godot.Environment)next.Duplicate(true):climate.Call("make_environment",chosen.Get("shader_time")).As<Godot.Environment>();if(next==null){if(owner_key!=0)Restore();return;}if(owner_key==0)original=underlying();owner_key=key;owned=next;world.Environment=owned;sync_sky_time(chosen);
    }
    public void sync_sky_time(Node runtime)
    {
        if(owned==null)return;var timeValue=runtime.Get("shader_time");double time=timeValue.VariantType is Variant.Type.Float or Variant.Type.Int?timeValue.AsDouble():0;if(owned.Sky?.SkyMaterial is ShaderMaterial material){string uniform=material.GetMeta("kiwi_time_uniform", "").AsString();if(uniform.Length>0)material.SetShaderParameter(uniform,time);}var document=Document(runtime);var climate=document?.Get("climate").As<Resource>();var content=Content(runtime);if(content==null)return;if(climate==null){ClearWeather(runtime);return;}var camera=runtime.GetViewport().GetCamera3D();var position=camera!=null?content.GlobalTransform.AffineInverse()*camera.GlobalPosition:Vector3.Zero;var overridesValue=runtime.Get("climate_overrides");var overrides=overridesValue.VariantType==Variant.Type.Dictionary?overridesValue.AsGodotDictionary():new Settings();var state=climate.Call("apply_environment",owned,time,position,overrides).AsGodotDictionary();_weather.update(content,state,camera);var sun=content.Get("sun").As<DirectionalLight3D>();if(sun==null)return;var direction=Get(state,"sun_direction",Vector3.Down).AsVector3();double elevation=Get(state,"sun_elevation",0.0).AsDouble();var sunlight=document!.Get("sunlight").AsGodotDictionary();sun.Visible=Get(sunlight,"enabled",true).AsBool()&&elevation>Mathf.DegToRad(-10);if(direction.LengthSquared()>.0001)sun.Basis=Basis.LookingAt(-direction.Normalized(),Vector3.Up);sun.LightEnergy=(float)(Get(sunlight,"energy",1.5).AsDouble()*Get(state,"sunlight_energy",1.0).AsDouble());float warmth=(float)Math.Clamp(1-Math.Abs(elevation)/.25,0,1);sun.LightColor=Get(sunlight,"color",Colors.White).AsColor().Lerp(new Color(1,.55f,.3f),warmth*.55f);
    }
    public void _sync_sky_time(Node runtime)=>sync_sky_time(runtime);
    public override void _ExitTree()
    {var retiringWorld=world;Restore();entries.Clear();world=null;retiringWorld?.Dispose();}
}
