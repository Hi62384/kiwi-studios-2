using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;
public partial class FogLightingOperations:RefCounted
{
    private readonly ActorPropertyOperations _properties=new();private readonly ActorDefinitionOperations _definitions=new();
    private GArray Rows(string key)=>GD.Load<GDScript>("res://scripts/actors/fog/fog_lighting.gd").GetScriptConstantMap()[key].AsGodotArray();
    public void extend_actor(Resource d)
    {
        string type=d.Get("type_id").AsString();if(type is "light_3d" or "directional_light")foreach(var item in Rows("LIGHT_ROWS")){var row=item.AsGodotArray();string key=row[0].AsString();if(_definitions.find_property(d,new StringName(key))!=null)continue;var p=_properties.create(new StringName(key),row[1].AsString(),row[2],true);var options=p.Get("options").AsGodotDictionary();options.Merge(new Settings{["min"]=row[3],["max"]=row[4],["group"]=key=="volumetric_fog_energy"?"Volumetric lighting":"Shadows"});if(key=="volumetric_fog_energy")options["tooltip"]="Zero removes only this light's volumetric contribution. Surface lighting still uses Energy.";if(key is "attenuation" or "spot_attenuation" or "light_size"){if(type=="directional_light")continue;options["group"]="Light";options["visible_when"]=new Settings{["property"]="light_type",["values"]=key=="spot_attenuation"?new GArray{2}:new GArray{1,2}};}d.Get("properties").AsGodotArray().Add(p);}if(type is "basic_mesh" or "basic_shape" or "text_3d" or "image_3d"&&_definitions.find_property(d,new StringName("shadow_casting"))==null){var p=_properties.create(new StringName("shadow_casting"),"Shadow casting",0,true);p.Get("options").AsGodotDictionary().Merge(new Settings{["group"]="Lighting",["choices"]=new GArray{"Keep original","Off","On","Double-sided","Shadows only"},["tooltip"]="Uses native shadow maps. Transparent and custom materials retain the renderer's shadow limitations."});d.Get("properties").AsGodotArray().Add(p);}
    }
    public void extend_environment(Resource d){foreach(var item in Rows("ENVIRONMENT_ROWS")){var row=item.AsGodotArray();string key=row[0].AsString();if(_definitions.find_property(d,new StringName(key))!=null)continue;var p=_properties.create(new StringName(key),row[1].AsString(),row[2],true);p.Get("options").AsGodotDictionary().Merge(row[3].AsGodotDictionary());p.Get("options").AsGodotDictionary()["group"]="Volumetric Fog";p.Get("options").AsGodotDictionary()["tooltip"]="Environment-wide. Offline frame capture disables temporal history to prevent trails after time jumps.";d.Get("properties").AsGodotArray().Add(p);}}
    public void apply_light(Light3D light,Settings v)
    {
        light.LightVolumetricFogEnergy=(float)Math.Max(0,v.GetValueOrDefault("volumetric_fog_energy",1.0).AsDouble());light.ShadowBias=v.GetValueOrDefault("shadow_bias",.1).AsSingle();light.ShadowNormalBias=v.GetValueOrDefault("shadow_normal_bias",2.0).AsSingle();light.ShadowOpacity=v.GetValueOrDefault("shadow_opacity",1.0).AsSingle();light.ShadowBlur=v.GetValueOrDefault("shadow_blur",1.0).AsSingle();light.LightSize=(float)Math.Max(0,v.GetValueOrDefault("light_size",0.0).AsDouble());if(light is OmniLight3D omni)omni.OmniAttenuation=v.GetValueOrDefault("attenuation",1.0).AsSingle();if(light is SpotLight3D spot){spot.SpotAttenuation=v.GetValueOrDefault("attenuation",1.0).AsSingle();spot.SpotAngleAttenuation=v.GetValueOrDefault("spot_attenuation",1.0).AsSingle();}
    }
    public void apply_geometry(Node runtime,Settings v){if(v.ContainsKey("shadow_casting"))visit_geometry(runtime,runtime,Math.Clamp(v["shadow_casting"].AsInt32(),0,4));}
    public void visit_geometry(Node node,Node owner,int mode)
    {
        if(node!=owner){var script=node.GetScript().As<Script>();while(script!=null){if(script.ResourcePath=="res://scripts/actors/core/ActorRuntime.cs")return;script=script.GetBaseScript();}}if(node is GeometryInstance3D geometry){if(!geometry.HasMeta("kiwi_original_shadow_mode"))geometry.SetMeta("kiwi_original_shadow_mode",(int)geometry.CastShadow);geometry.CastShadow=(GeometryInstance3D.ShadowCastingSetting)(mode==0?geometry.GetMeta("kiwi_original_shadow_mode").AsInt32():mode-1);}foreach(var child in node.GetChildren())visit_geometry(child,owner,mode);
    }
}
