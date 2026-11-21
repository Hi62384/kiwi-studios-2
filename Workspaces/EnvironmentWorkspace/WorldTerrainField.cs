using Godot;
using System;
using Settings=Godot.Collections.Dictionary;

/// <summary>Immutable CPU terrain snapshot shared with procedural world workers.</summary>
public partial class WorldTerrainField : RefCounted
{
    public int resolution {get;set;}
    public Vector2 dimensions {get;set;}
    public float[] heights {get;set;}=Array.Empty<float>();
    public int native_resolution {get;set;}
    public float[] native_base {get;set;}=Array.Empty<float>();
    public float[] native_edits {get;set;}=Array.Empty<float>();
    public float[] native_water {get;set;}=Array.Empty<float>();
    public int water_resolution {get;set;}
    public float[] water_levels {get;set;}=Array.Empty<float>();
    public float[] water_depths {get;set;}=Array.Empty<float>();
    public Transform3D to_ground {get;set;}=Transform3D.Identity;
    private Transform3D _toWorld=Transform3D.Identity;
    private Basis _normalBasis=Basis.Identity;
    public Transform3D to_world {get=>_toWorld;set{_toWorld=value;_normalBasis=value.Basis.Inverse().Transposed();}}
    public long key {get;set;}
    public long source_signature {get;set;}
    public string root_id {get;set;}="";
    public string terrain_id {get;set;}="";
    public WeakRef? terrain_input {get;set;}
    public double _height(int x,int z)=>heights[Math.Clamp(x,0,resolution-1)+Math.Clamp(z,0,resolution-1)*resolution];
    public double _sample_height(int x,int z)
    {if(native_resolution<2)return _height(x,z);int index=Math.Clamp(x,0,native_resolution-1)+Math.Clamp(z,0,native_resolution-1)*native_resolution;return native_base[index]+(index<native_edits.Length?native_edits[index]:0.0)+(index<native_water.Length?native_water[index]:0.0);}
    public Settings sample(Vector2 point)
    {
        var local=to_ground*new Vector3(point.X,0,point.Y);var uv=new Vector2(local.X,local.Z)/dimensions+Vector2.One*.5f;if(uv.X<0||uv.Y<0||uv.X>1||uv.Y>1||resolution<2)return new();int grid=native_resolution>1?native_resolution:resolution;var p=uv*(grid-1);var cell=new Vector2I((int)Math.Floor(p.X),(int)Math.Floor(p.Y));var f=p-(Vector2)cell;
        double height=Mathf.Lerp(Mathf.Lerp(_sample_height(cell.X,cell.Y),_sample_height(cell.X+1,cell.Y),f.X),Mathf.Lerp(_sample_height(cell.X,cell.Y+1),_sample_height(cell.X+1,cell.Y+1),f.X),f.Y);var position=to_world*new Vector3(local.X,(float)height,local.Z);
        double dx=(_sample_height(cell.X+1,cell.Y)-_sample_height(cell.X-1,cell.Y))/(dimensions.X/(grid-1)*Math.Max(1,Math.Min(grid-1,cell.X+1)-Math.Max(0,cell.X-1)));double dz=(_sample_height(cell.X,cell.Y+1)-_sample_height(cell.X,cell.Y-1))/(dimensions.Y/(grid-1)*Math.Max(1,Math.Min(grid-1,cell.Y+1)-Math.Max(0,cell.Y-1)));var normal=(_normalBasis*new Vector3((float)-dx,1,(float)-dz)).Normalized();var water=water_at_uv(uv);double level=water.TryGetValue("level",out var waterLevel)?waterLevel.AsDouble():position.Y,depth=water.Count>0?Math.Max(0,level-position.Y):0;
        return new Settings {["height"]=position.Y,["normal"]=normal,["water"]=depth>.03,["water_depth"]=depth,["water_level"]=level};
    }
    public Settings water_at_uv(Vector2 uv)
    {
        if(water_resolution<2)return new();var p=uv*(water_resolution-1);var cell=new Vector2I((int)Math.Floor(p.X),(int)Math.Floor(p.Y));var f=p-(Vector2)cell;double level=0,depth=0,weight=0;
        for(int z=0;z<2;z++)for(int x=0;x<2;x++){int index=Math.Clamp(cell.X+x,0,water_resolution-1)+Math.Clamp(cell.Y+z,0,water_resolution-1)*water_resolution;double blend=(x==1?f.X:1.0-f.X)*(z==1?f.Y:1.0-f.Y);if(water_depths[index]<=0)continue;level+=water_levels[index]*blend;depth+=water_depths[index]*blend;weight+=blend;}if(weight<=.000001)return new();var local=uv*dimensions-dimensions*.5f;var surface=to_world*new Vector3(local.X,(float)(level/weight),local.Y);return new Settings {["level"]=surface.Y,["depth"]=depth/weight*to_world.Basis.Y.Length()};
    }
    public bool valid(RefCounted session)
    {
        using var documents=new EnvironmentDocumentOperations();using var models=new ModelDocumentOperations();var document=session.Get("document").As<Resource>();var terrain=documents.terrain(document,terrain_id);var owner=models.component(document,root_id);var ground=models.component(document,terrain_id);if(terrain_input==null||terrain==null||owner==null||ground==null)return false;using var reference=terrain_input.GetRef();if(terrain!=reference.As<Resource>()||WorldTerrainFieldOperations.Signature(terrain)!=source_signature)return false;var pose=models.world_transform(document,ground).AffineInverse()*models.world_transform(document,owner);return pose.IsEqualApprox(to_ground);
    }
}
