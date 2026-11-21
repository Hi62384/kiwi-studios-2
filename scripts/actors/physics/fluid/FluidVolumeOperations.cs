using Godot;
using Settings=Godot.Collections.Dictionary;
public partial class FluidVolumeOperations:RefCounted
{
    private readonly VolumeSamplerOperations _sampler=new();
    public Settings generate(Settings values,Transform3D pose,Settings geometry){float spacing=values["spacing"].AsSingle();var size=values.TryGetValue("fluid_dimensions",out var dimensions)?dimensions.AsVector3():Vector3.One;int shape=values.TryGetValue("fluid_shape",out var kind)?kind.AsInt32():0;return _sampler.generate(shape,size.Abs().Max(Vector3.One*spacing),spacing,values["budget"].AsInt32(),pose,geometry,0,1);}
    public bool inside(TriangleMesh mesh,Vector3 point,double distance)=>_sampler.inside(mesh,point,distance);
}
