using Godot;
using System;
using System.Linq;
using System.Collections.Generic;
using GArray=Godot.Collections.Array;
using Settings=Godot.Collections.Dictionary;
public partial class FogGroundSamplerOperations:RefCounted
{
    private readonly ActorAnimationOperations _animation=new();
    private Settings Cache=>GD.Load<GDScript>("res://scripts/actors/fog/fog_ground_sampler.gd").Get("cache").AsGodotDictionary();
    public Settings prepare(RefCounted? controller,Transform3D pose,Vector3 size,Settings settings)
    {
        var world=controller?.Get("world").AsGodotObject();if(world==null||!world.Get("space").AsRid().IsValid)return new Settings{["error"]="Enable the terrain's normal physics collider to sample its surface."};
        if(Mathf.Abs(pose.Basis.Orthonormalized().Y.Dot(Vector3.Up))<.99f)return new Settings{["error"]="Terrain-following mist needs an upright domain. Use world elevation for a tilted volume."};
        var rows=new GArray();var bodies=world.Get("bodies").AsGodotDictionary();foreach(var id in bodies.Keys){if(id.AsString().StartsWith("@probe:",StringComparison.Ordinal))continue;var entry=bodies[id].AsGodotDictionary();rows.Add(new GArray{id,entry.GetValueOrDefault("pose",Transform3D.Identity),entry.GetValueOrDefault("enabled",false),entry["shape"].As<Shape3D>().GetRid()});}
        double fallback=settings.GetValueOrDefault("cloud_ground_height",0.0).AsDouble(),reach=Math.Max(1,settings.GetValueOrDefault("cloud_ground_search",1000.0).AsDouble());uint mask=unchecked((uint)settings.GetValueOrDefault("cloud_ground_mask",1).AsInt64());long key=GD.Hash(new GArray{pose,size,rows,fallback,reach,(long)mask});var cache=Cache;if(cache.TryGetValue(key,out var cached))return cached.AsGodotDictionary();
        ulong started=Time.GetTicksUsec();const int n=16;var image=Image.CreateEmpty(n,n,false,Image.Format.Rf);int hits=0;var space=PhysicsServer3D.SpaceGetDirectState(world.Get("space").AsRid());
        for(int y=0;y<n;y++)for(int x=0;x<n;x++){var point=pose*(new Vector3((x+.5f)/n-.5f,0,(y+.5f)/n-.5f)*size);var query=PhysicsRayQueryParameters3D.Create(point+Vector3.Up*(float)reach,point-Vector3.Up*(float)reach,mask);query.CollideWithAreas=false;var hit=space.IntersectRay(query);float height=(float)fallback;if(hit.Count>0){height=hit["position"].AsVector3().Y;hits++;}image.SetPixel(x,y,new Color(height,0,0,1));}
        var result=new Settings{["image"]=image,["texture"]=ImageTexture.CreateFromImage(image),["key"]=key,["hits"]=hits,["milliseconds"]=(Time.GetTicksUsec()-started)/1000.0,["error"]=hits>0?"":"No collision surface was found; using the configured ground elevation."};if(cache.Count>=16)cache.Remove(cache.Keys.First());cache[key]=result;return result;
    }
    public double sample_height(Image image,Vector3 unit)
    {
        var p=new Vector2(unit.X,unit.Z)*new Vector2(image.GetWidth(),image.GetHeight())-Vector2.One*.5f;var floor=p.Floor();var f=p-floor;double height=0;for(int y=0;y<2;y++)for(int x=0;x<2;x++){int cx=Math.Clamp((int)floor.X+x,0,image.GetWidth()-1),cy=Math.Clamp((int)floor.Y+y,0,image.GetHeight()-1);height+=image.GetPixel(cx,cy).R*(x==1?f.X:1-f.X)*(y==1?f.Y:1-f.Y);}return height;
    }
    public void sync(Node runtime,ShaderMaterial material)
    {
        var content=runtime.Get("content").As<FogVolume>();material.SetShaderParameter("scene_ground",false);content.SetMeta("fog_ground_error","");var actor=runtime.Get("actor").As<Resource>();double time=actor.Get("animation_time").AsDouble();var values=_animation.sampled_values(actor,double.IsNaN(time)?0:time);var candidate=values.GetValueOrDefault("field",default(Variant));Resource? field=null;if(candidate.VariantType==Variant.Type.Object&&candidate.AsGodotObject() is Resource reference&&ActorDataOperations.ScriptIs(reference,"res://scripts/actors/core/actor_object_reference.gd"))field=_animation.resolve_reference(reference);if(field==null)return;var settings=field.Get("values").AsGodotDictionary();if(settings.GetValueOrDefault("mode",0).AsInt32()!=8||!settings.GetValueOrDefault("cloud_follow_ground",false).AsBool())return;
        RefCounted? controller=null;foreach(var editor in runtime.GetTree().GetNodesInGroup("actor_timeline_editors")){var model=editor.Get("model").AsGodotObject();if(model.Call("actor_for_id",actor.Get("id")).AsGodotObject()==actor){controller=editor.Get("physics").As<RefCounted>();break;}}
        var result=prepare(controller,content.GlobalTransform,content.Size,settings);content.SetMeta("fog_ground_error",result.GetValueOrDefault("error",""));if(result.TryGetValue("texture",out var texture)&&texture.AsGodotObject() is Texture2D){material.SetShaderParameter("scene_ground",true);material.SetShaderParameter("scene_ground_height",texture);}
    }
}
