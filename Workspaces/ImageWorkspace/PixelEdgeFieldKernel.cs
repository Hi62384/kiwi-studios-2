using Godot;
using System;
using Settings=Godot.Collections.Dictionary;
public partial class PixelEdgeFieldKernel:RefCounted
{
    private Image? _source,_bitmap;
    private Rect2I _domain;
    private Vector2I _size;
    private Vector2 _step;
    private float[] _strength=Array.Empty<float>();
    private Vector2[] _normal=Array.Empty<Vector2>();
    private byte[] _ridges=Array.Empty<byte>();
    private Color[] _colors=Array.Empty<Color>();
    internal Image Source=>_source!;
    internal Rect2I Domain=>_domain;
    internal Vector2I Size=>_size;
    internal Vector2 Step=>_step;
    internal Color[] Colors=>_colors;
    public Settings build(Image image,Rect2I area,int maximum)
    {
        _source=image;_domain=area.Intersection(new Rect2I(Vector2I.Zero,image.GetSize()));_bitmap=image.GetRegion(_domain);_bitmap.Convert(Image.Format.Rgba8);double ratio=Math.Min(1,(double)maximum/Math.Max(_domain.Size.X,_domain.Size.Y));if(ratio<1)_bitmap.Resize(Math.Max(1,Mathf.RoundToInt(_domain.Size.X*ratio)),Math.Max(1,Mathf.RoundToInt(_domain.Size.Y*ratio)),Image.Interpolation.Bilinear);_size=_bitmap.GetSize();_step=(Vector2)_domain.Size/(Vector2)_size;var bytes=_bitmap.GetData();int count=_size.X*_size.Y;_colors=new Color[count];_strength=new float[count];_normal=new Vector2[count];_ridges=new byte[count];for(int index=0;index<count;index++){float alpha=bytes[index*4+3]/255f;_colors[index]=new Color(bytes[index*4]/255f/Math.Max(alpha,.001f),bytes[index*4+1]/255f/Math.Max(alpha,.001f),bytes[index*4+2]/255f/Math.Max(alpha,.001f),alpha);}var filtered=new Color[count];var smooth=new Color[count];for(int y=0;y<_size.Y;y++)for(int x=0;x<_size.X;x++){var sum=new Color(0,0,0,0);for(int k=-1;k<=1;k++){var color=_colors[y*_size.X+Math.Clamp(x+k,0,_size.X-1)];sum+=new Color(color.R*color.A,color.G*color.A,color.B*color.A,color.A)*(k==0?2:1);}filtered[y*_size.X+x]=sum*.25f;}for(int y=0;y<_size.Y;y++)for(int x=0;x<_size.X;x++)smooth[y*_size.X+x]=(filtered[Math.Max(0,y-1)*_size.X+x]+filtered[y*_size.X+x]*2+filtered[Math.Min(_size.Y-1,y+1)*_size.X+x])*.25f;
        for(int y=0;y<_size.Y;y++)for(int x=0;x<_size.X;x++){int index=y*_size.X+x;var dx=new Color(0,0,0,0);var dy=new Color(0,0,0,0);for(int k=-1;k<=1;k++){float weight=k==0?2:1;dx+=(smooth[Math.Clamp(y+k,0,_size.Y-1)*_size.X+Math.Min(_size.X-1,x+1)]-smooth[Math.Clamp(y+k,0,_size.Y-1)*_size.X+Math.Max(0,x-1)])*weight*.25f;dy+=(smooth[Math.Min(_size.Y-1,y+1)*_size.X+Math.Clamp(x+k,0,_size.X-1)]-smooth[Math.Max(0,y-1)*_size.X+Math.Clamp(x+k,0,_size.X-1)])*weight*.25f;}double xx=dx.R*dx.R+dx.G*dx.G+dx.B*dx.B+dx.A*dx.A,yy=dy.R*dy.R+dy.G*dy.G+dy.B*dy.B+dy.A*dy.A,xy=dx.R*dy.R+dx.G*dy.G+dx.B*dy.B+dx.A*dy.A,angle=.5*Math.Atan2(2*xy,xx-yy);_normal[index]=new Vector2((float)Math.Cos(angle),(float)Math.Sin(angle));_strength[index]=(float)Math.Clamp(Math.Sqrt((xx+yy+Math.Sqrt((xx-yy)*(xx-yy)+4*xy*xy))*.5),0,1);}
        for(int y=0;y<_size.Y;y++)for(int x=0;x<_size.X;x++){int index=y*_size.X+x;if(_strength[index]<.008)continue;float before=sample_strength(new Vector2(x,y)+_normal[index]),after=sample_strength(new Vector2(x,y)-_normal[index]);if(_strength[index]>=before-.00001&&_strength[index]>=after-.00001)_ridges[index]=1;}return new Settings{["domain"]=_domain,["bitmap"]=_bitmap,["size"]=_size,["step"]=_step,["strength"]=_strength,["normal"]=_normal,["ridges"]=_ridges,["colors"]=_colors};
    }
    public float sample_strength(Vector2 point)
    {
        float x=Math.Clamp(point.X,0,_size.X-1),y=Math.Clamp(point.Y,0,_size.Y-1);int a=Mathf.FloorToInt(x),b=Mathf.FloorToInt(y);return Mathf.Lerp(Mathf.Lerp(_strength[b*_size.X+a],_strength[b*_size.X+Math.Min(a+1,_size.X-1)],x-a),Mathf.Lerp(_strength[Math.Min(b+1,_size.Y-1)*_size.X+a],_strength[Math.Min(b+1,_size.Y-1)*_size.X+Math.Min(a+1,_size.X-1)],x-a),y-b);
    }
    public bool inside(Vector2I point)=>new Rect2I(Vector2I.Zero,_size).HasPoint(point);
    public Vector2 position(int index)=>(Vector2)_domain.Position+(new Vector2(index%_size.X,index/_size.X)+Vector2.One*.5f)*_step;
    public Vector2I cell(Vector2 point)=>(Vector2I)((point-(Vector2)_domain.Position)/_step).Floor();
    public double cutoff(double value)=>.012+.75*Math.Pow(Math.Clamp(value,0,1),2);
    public int nearest(Vector2 point,double threshold,int previous,Vector2 direction)
    {
        var at=cell(point);var reach=(Vector2I)(Vector2.One*16/_step).Ceil();int best=-1;double score=double.PositiveInfinity,minimum=cutoff(threshold)*(previous>=0?.4:1);var unit=direction.Normalized();for(int y=Math.Max(0,at.Y-reach.Y);y<Math.Min(_size.Y,at.Y+reach.Y+1);y++)for(int x=Math.Max(0,at.X-reach.X);x<Math.Min(_size.X,at.X+reach.X+1);x++){int index=y*_size.X+x;if(_ridges[index]==0||_strength[index]<minimum)continue;var location=position(index);double distance=location.DistanceTo(point);if(distance>16)continue;double value=distance+2*(1-_strength[index]);if(previous>=0)value+=location.DistanceTo(position(previous))*.1+3*(1-Math.Abs(_normal[index].Dot(_normal[previous])));if(!direction.IsZeroApprox())value+=Math.Abs(_normal[index].Dot(unit))*3;if(value<score){score=value;best=index;}}return best;
    }
    private static readonly Vector2I[] Adjacent={new(-1,-1),new(0,-1),new(1,-1),new(-1,0),new(1,0),new(-1,1),new(0,1),new(1,1)};
    private static readonly Vector2I[] Bridge={new(-2,-1),new(-2,0),new(-2,1),new(-1,-2),new(0,-2),new(1,-2),new(2,-1),new(2,0),new(2,1),new(-1,2),new(0,2),new(1,2)};
    public int[] neighbors(int index,double threshold)
    {
        var result=new System.Collections.Generic.List<int>(20);var at=new Vector2I(index%_size.X,index/_size.X);double cutoffValue=cutoff(threshold);foreach(var delta in Adjacent){var point=at+delta;if(!inside(point))continue;int next=point.Y*_size.X+point.X;if(_ridges[next]!=0&&_strength[next]>=cutoffValue*.4)result.Add(next);}foreach(var delta in Bridge){var point=at+delta;if(!inside(point))continue;int next=point.Y*_size.X+point.X;if(_ridges[next]==0||_strength[next]<cutoffValue*.4||Math.Abs(_normal[index].Dot(((Vector2)delta).Normalized()))>.55||Math.Abs(_normal[next].Dot(_normal[index]))<.7||sample_strength((Vector2)at+(Vector2)delta*.5f)<cutoffValue*.3)continue;result.Add(next);}return result.ToArray();
    }
    public Vector2 refine(int index)
    {
        var center=position(index);int reach=Math.Min(8,Mathf.CeilToInt(Math.Max(_step.X,_step.Y)));var best=center;double score=double.NegativeInfinity;for(int y=Math.Max(_domain.Position.Y+1,Mathf.FloorToInt(center.Y)-reach);y<Math.Min(_domain.End.Y-1,Mathf.CeilToInt(center.Y)+reach+1);y++)for(int x=Math.Max(_domain.Position.X+1,Mathf.FloorToInt(center.X)-reach);x<Math.Min(_domain.End.X-1,Mathf.CeilToInt(center.X)+reach+1);x++){var offset=new Vector2(x+.5f,y+.5f)-center;if(Math.Abs(offset.Dot(_normal[index].Orthogonal()))>Math.Max(.75,Math.Min(_step.X,_step.Y)*.5))continue;var dx=_source!.GetPixel(x+1,y)-_source.GetPixel(x-1,y);var dy=_source.GetPixel(x,y+1)-_source.GetPixel(x,y-1);double gradient=Math.Max(Math.Max(new Vector2(dx.R,dy.R).Length(),new Vector2(dx.G,dy.G).Length()),Math.Max(new Vector2(dx.B,dy.B).Length(),new Vector2(dx.A,dy.A).Length())),value=gradient-offset.Length()*.08;if(value>score){score=value;best=new Vector2(x+.5f,y+.5f);}}return best;
    }
}
public partial class PixelEdgeFieldOperations:RefCounted
{
    public PixelEdgeFieldKernel create()=>new();
    public double cutoff(double value)=>.012+.75*Math.Pow(Math.Clamp(value,0,1),2);
}
