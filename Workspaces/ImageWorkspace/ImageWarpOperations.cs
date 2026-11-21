using Godot;
using System;
using Settings=Godot.Collections.Dictionary;
public partial class ImageWarpOperations:RefCounted
{
    public ImageWarpKernel create()=>new();
    public Vector2 sample_grid(Vector2[] values,Vector2I size,Vector2 uv)=>SampleGrid(values,size,uv);
    public double sample_scalar(float[] values,Vector2I size,Vector2 uv)=>SampleScalar(values,size,uv);
    internal static Vector2 SampleGrid(Vector2[] values,Vector2I size,Vector2 uv){if(values.Length==0)return Vector2.Zero;var point=uv.Clamp(Vector2.Zero,Vector2.One)*(Vector2)(size-Vector2I.One);int x=Mathf.FloorToInt(point.X),y=Mathf.FloorToInt(point.Y),right=Math.Min(size.X-1,x+1),bottom=Math.Min(size.Y-1,y+1);return values[y*size.X+x].Lerp(values[y*size.X+right],point.X-x).Lerp(values[bottom*size.X+x].Lerp(values[bottom*size.X+right],point.X-x),point.Y-y);}
    internal static float SampleScalar(float[] values,Vector2I size,Vector2 uv){if(values.Length==0)return 0;var point=uv.Clamp(Vector2.Zero,Vector2.One)*(Vector2)(size-Vector2I.One);int x=Mathf.FloorToInt(point.X),y=Mathf.FloorToInt(point.Y),right=Math.Min(size.X-1,x+1),bottom=Math.Min(size.Y-1,y+1);return Mathf.Lerp(Mathf.Lerp(values[y*size.X+x],values[y*size.X+right],point.X-x),Mathf.Lerp(values[bottom*size.X+x],values[bottom*size.X+right],point.X-x),point.Y-y);}
}
public partial class ImageWarpKernel:RefCounted
{
    private Vector2[] _field=Array.Empty<Vector2>(),_mesh=Array.Empty<Vector2>(),_pinSources=Array.Empty<Vector2>(),_pinDeltas=Array.Empty<Vector2>();
    private float[] _pinRadii=Array.Empty<float>();private byte[] _pinLocked=Array.Empty<byte>();
    private bool _meshActive;private int _meshResolution;private Vector2I _fieldSize;private long _localRevision=-1;
    private static void Touch(Resource owner)=>owner.Set("revision",owner.Get("revision").AsInt64()+1);
    private static Vector2 NodeUv(int index,Vector2I size)=>new Vector2(index%size.X,index/size.X)/(Vector2)(size-Vector2I.One);
    private static Vector2 MeshOrigin(int index,int resolution)=>new Vector2(index%resolution,index/resolution)/(resolution-1);
    public void initialize(Resource owner,Vector2 extent)
    {
        var ratio=extent/Math.Max(1,Math.Max(extent.X,extent.Y));var size=((Vector2I)(ratio*64).Ceil()).Max(new Vector2I(16,16))+Vector2I.One;owner.Set("grid_size",size);var displacement=owner.Get("displacement").AsVector2Array();var freeze=owner.Get("freeze").AsFloat32Array();Array.Resize(ref displacement,size.X*size.Y);Array.Resize(ref freeze,displacement.Length);owner.Set("displacement",displacement);owner.Set("freeze",freeze);reset_mesh(owner,4);Touch(owner);
    }
    public Resource copy_warp(Resource owner)
    {
        var result=new KiwiImageWarpData();foreach(string key in new[]{"enabled","grid_size","mesh_resolution","revision"})result.Set(key,owner.Get(key));foreach(string key in new[]{"displacement","mesh_points","baseline"})result.Set(key,owner.Get(key).AsVector2Array());foreach(string key in new[]{"freeze","restriction"})result.Set(key,owner.Get(key).AsFloat32Array());var pins=result.Get("pins").AsGodotArray();foreach(var pin in owner.Get("pins").AsGodotArray().Duplicate(true))pins.Add(pin);return result;
    }
    public void touch(Resource owner)=>Touch(owner);
    public Vector2 node_uv(Resource owner,int index)=>NodeUv(index,owner.Get("grid_size").AsVector2I());
    public Vector2 mesh_origin(Resource owner,int index)=>MeshOrigin(index,owner.Get("mesh_resolution").AsInt32());
    public void reset_mesh(Resource owner,int resolution)
    {
        resolution=Math.Clamp(resolution,2,16);owner.Set("mesh_resolution",resolution);var points=new Vector2[resolution*resolution];for(int index=0;index<points.Length;index++)points[index]=MeshOrigin(index,resolution);owner.Set("mesh_points",points);Touch(owner);
    }
    public void change_resolution(Resource owner,int resolution)
    {
        var previous=owner.Get("mesh_points").AsVector2Array();int prior=owner.Get("mesh_resolution").AsInt32();reset_mesh(owner,resolution);int next=owner.Get("mesh_resolution").AsInt32();var points=new Vector2[next*next];for(int index=0;index<points.Length;index++)points[index]=ImageWarpOperations.SampleGrid(previous,new Vector2I(prior,prior),MeshOrigin(index,next));owner.Set("mesh_points",points);Touch(owner);
    }
    public void refine_for_brush(Resource owner,Vector2 extent,double diameter)
    {
        int desired=Math.Clamp(Mathf.CeilToInt(Math.Max(extent.X,extent.Y)/Math.Max(.5,diameter*.12)),64,256);var priorSize=owner.Get("grid_size").AsVector2I();if(desired<=Math.Max(priorSize.X,priorSize.Y)-1)return;int next=Math.Min(256,(int)Math.Pow(2,Math.Ceiling(Math.Log(desired)/Math.Log(2))));var previous=owner.Get("displacement").AsVector2Array();var oldFreeze=owner.Get("freeze").AsFloat32Array();var oldRestriction=owner.Get("restriction").AsFloat32Array();var oldBaseline=owner.Get("baseline").AsVector2Array();var size=((Vector2I)(extent/Math.Max(extent.X,extent.Y)*next).Ceil()).Max(new Vector2I(16,16))+Vector2I.One;var displacement=new Vector2[size.X*size.Y];var freeze=new float[displacement.Length];var restriction=oldRestriction.Length>0?new float[displacement.Length]:Array.Empty<float>();var baseline=oldBaseline.Length>0?new Vector2[displacement.Length]:Array.Empty<Vector2>();for(int index=0;index<displacement.Length;index++){var point=NodeUv(index,size);displacement[index]=ImageWarpOperations.SampleGrid(previous,priorSize,point);freeze[index]=ImageWarpOperations.SampleScalar(oldFreeze,priorSize,point);if(restriction.Length>0)restriction[index]=ImageWarpOperations.SampleScalar(oldRestriction,priorSize,point);if(baseline.Length>0)baseline[index]=ImageWarpOperations.SampleGrid(oldBaseline,priorSize,point);}owner.Set("grid_size",size);owner.Set("displacement",displacement);owner.Set("freeze",freeze);owner.Set("restriction",restriction);owner.Set("baseline",baseline);owner.Set("_texture",default(Variant));Touch(owner);
    }
    private Vector2 ForwardControls(Vector2 uv)
    {
        var result=uv;if(_meshActive)result+=ImageWarpOperations.SampleGrid(_mesh,new Vector2I(_meshResolution,_meshResolution),uv)-uv.Clamp(Vector2.Zero,Vector2.One);var sum=Vector2.Zero;var anchors=Vector2.Zero;double anchorWeight=0;for(int index=0;index<_pinSources.Length;index++){double distance=uv.DistanceTo(_pinSources[index]),radius=_pinRadii[index];if(distance>=radius)continue;double falloff=1-distance/radius,influence=Math.Pow(falloff,4)*(1+4*distance/radius);sum+=_pinDeltas[index]*(float)influence;if(_pinLocked[index]!=0){double weight=influence/Math.Max(.0000001,distance*distance);anchors+=_pinDeltas[index]*(float)weight;anchorWeight+=weight;}}if(anchorWeight>0)sum=sum.Lerp(anchors/(float)anchorWeight,(float)(anchorWeight/(1+anchorWeight)));return result+sum;
    }
    public Vector2 forward_controls(Resource owner,Vector2 uv)
    {
        _meshActive=owner.Get("_mesh_active").AsBool();_mesh=owner.Get("mesh_points").AsVector2Array();_meshResolution=owner.Get("mesh_resolution").AsInt32();_pinSources=owner.Get("_pin_sources").AsVector2Array();_pinDeltas=owner.Get("_pin_deltas").AsVector2Array();_pinRadii=owner.Get("_pin_radii").AsFloat32Array();_pinLocked=owner.Get("_pin_locked").AsByteArray();return ForwardControls(uv);
    }
    public void rebuild(Resource owner)
    {
        long revision=owner.Get("revision").AsInt64();var texture=owner.Get("_texture").As<ImageTexture>();if(owner.Get("_cached_revision").AsInt64()==revision&&texture!=null&&_localRevision==revision)return;var displacement=owner.Get("displacement").AsVector2Array();var freeze=owner.Get("freeze").AsFloat32Array();var restriction=owner.Get("restriction").AsFloat32Array();var baseline=owner.Get("baseline").AsVector2Array();_fieldSize=owner.Get("grid_size").AsVector2I();_field=new Vector2[displacement.Length];var pins=owner.Get("pins").AsGodotArray();bool controlsActive=pins.Count>0;_meshActive=false;_pinSources=new Vector2[pins.Count];_pinDeltas=new Vector2[pins.Count];_pinRadii=new float[pins.Count];_pinLocked=new byte[pins.Count];for(int index=0;index<pins.Count;index++){var pin=pins[index].AsGodotDictionary();_pinSources[index]=pin["source"].AsVector2();_pinDeltas[index]=pin["target"].AsVector2()-_pinSources[index];_pinRadii[index]=(float)Math.Max(.001,pin["radius"].AsDouble());_pinLocked[index]=(byte)(pin.TryGetValue("locked",out var locked)&&locked.AsBool()?1:0);}_mesh=owner.Get("mesh_points").AsVector2Array();_meshResolution=owner.Get("mesh_resolution").AsInt32();for(int index=0;index<_mesh.Length;index++)if(_mesh[index].DistanceSquaredTo(MeshOrigin(index,_meshResolution))>.000000001){controlsActive=true;_meshActive=true;break;}owner.Set("_mesh_active",_meshActive);owner.Set("_pin_sources",_pinSources);owner.Set("_pin_deltas",_pinDeltas);owner.Set("_pin_radii",_pinRadii);owner.Set("_pin_locked",_pinLocked);bool direct=!controlsActive;foreach(float value in freeze)if(value!=0){direct=false;break;}foreach(float value in restriction)if(value!=1){direct=false;break;}if(direct)Array.Copy(displacement,_field,displacement.Length);else for(int index=0;index<displacement.Length;index++){var point=NodeUv(index,_fieldSize);var q=point;if(controlsActive)for(int iteration=0;iteration<5;iteration++){var error=point-ForwardControls(q);if(error.LengthSquared()<.000000001)break;q+=error*.8f;}var offset=q-point+ImageWarpOperations.SampleGrid(displacement,_fieldSize,q);float allowed=1-Math.Clamp(freeze[index],0,1);if(restriction.Length==displacement.Length)allowed*=Math.Clamp(restriction[index],0,1);_field[index]=(baseline.Length==displacement.Length?baseline[index]:Vector2.Zero).Lerp(offset,allowed);}var bytes=System.Runtime.InteropServices.MemoryMarshal.AsBytes(_field.AsSpan()).ToArray();using var image=Image.CreateFromData(_fieldSize.X,_fieldSize.Y,false,Image.Format.Rgf,bytes);if(texture==null)texture=ImageTexture.CreateFromImage(image);else texture.Update(image);owner.Set("_texture",texture);owner.Set("_field",_field);owner.Set("_cached_revision",revision);_localRevision=revision;
    }
    public Texture2D? texture(Resource owner){rebuild(owner);return owner.Get("_texture").As<Texture2D>();}
    public Vector2 forward(Resource owner,Vector2 uv){rebuild(owner);return ForwardCached(uv);}
    internal Vector2 ForwardCached(Vector2 uv){var point=uv;for(int iteration=0;iteration<5;iteration++)point=uv-ImageWarpOperations.SampleGrid(_field,_fieldSize,point);return point;}
    public void capture_baseline(Resource owner){rebuild(owner);owner.Set("baseline",_field);}
    public Vector2 inverse_offset(Resource owner,int index){if(_localRevision<0)_field=owner.Get("_field").AsVector2Array();if(index>=_field.Length)return Vector2.Zero;if(index<0)index+=_field.Length;return _field[index];}
    public void reset_all(Resource owner){var displacement=owner.Get("displacement").AsVector2Array();Array.Fill(displacement,Vector2.Zero);owner.Set("displacement",displacement);reset_mesh(owner,owner.Get("mesh_resolution").AsInt32());owner.Set("baseline",Array.Empty<Vector2>());owner.Set("restriction",Array.Empty<float>());foreach(var raw in owner.Get("pins").AsGodotArray()){var pin=raw.AsGodotDictionary();pin["target"]=pin["source"];}Touch(owner);}
}
