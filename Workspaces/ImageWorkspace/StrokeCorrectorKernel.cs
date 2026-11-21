using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
public partial class StrokeCorrectorKernel:RefCounted
{
    private long _viewVersion;
    public long view_version()=>_viewVersion;
    private const int Support=54,CornerSupport=12,Tail=76;private const double ConnectionRange=16;
    private double _strength=.5,_scale=1,_spacing=1,_lastTime,_tipTime,_carry;private Vector2 _tip,_last;private int _sealed;private bool _dirty=true,_shapeRejected,_gapClosed;private Rect2 _rawBounds;
    private readonly List<Vector2> _points=new(),_knots=new(),_fitEdge=new();private readonly List<double> _times=new(),_turnPrefix=new(),_fitRadius=new();private readonly List<byte> _corners=new();private readonly List<int> _leftCorner=new(),_rightCorner=new(),_fitFirst=new(),_fitLast=new();
    private static void Resize<T>(List<T> list,int count)where T:struct{if(list.Count>count)list.RemoveRange(count,list.Count-count);else{list.EnsureCapacity(count);while(list.Count<count)list.Add(default);}}
    private static void Replace<T>(List<T> list,T[] values){list.Clear();list.AddRange(values);}
    private Vector2 Raw(int index)=>index<_points.Count?_points[index<0?_points.Count+index:index]:_tip;
    private double PointTime(int index)=>index<_times.Count?_times[index<0?_times.Count+index:index]:_tipTime;
    public Vector2 raw(int index)=>Raw(index);
    public double time(int index)=>PointTime(index);
    public void begin(Vector2 point,double amount,double brushSize,double time,double scale)
    {
        _viewVersion++;_strength=Math.Clamp(amount,0,1);_scale=Math.Clamp(scale,.1,16);_spacing=1.25*_scale;_points.Clear();_points.Add(point);_times.Clear();_times.Add(time);_knots.Clear();_knots.Add(point);_corners.Clear();_corners.Add(1);_tip=_last=point;_lastTime=_tipTime=time;_carry=0;_sealed=0;_dirty=true;_leftCorner.Clear();_rightCorner.Clear();_turnPrefix.Clear();_turnPrefix.Add(0);_turnPrefix.Add(0);_fitFirst.Clear();_fitLast.Clear();_fitRadius.Clear();_fitEdge.Clear();_rawBounds=new Rect2(point,Vector2.Zero);_shapeRejected=_gapClosed=false;
    }
    public void add(Vector2 point,double time)
    {
        double distance=_last.DistanceTo(point);if(distance<.00001)return;_viewVersion++;var direction=(point-_last)/(float)distance;double travel=_spacing-_carry;while(travel<=distance){_points.Add(_last+direction*(float)travel);_times.Add(_lastTime+(time-_lastTime)*(travel/distance));travel+=_spacing;}_carry=(_carry+distance)%_spacing;_last=_tip=point;_lastTime=_tipTime=time;_dirty=true;_rawBounds=_rawBounds.Expand(point);
    }
    public bool corner(int index,int count)
    {
        if(index<CornerSupport||index>count-CornerSupport-1)return false;var incoming=Raw(index)-Raw(index-CornerSupport);var outgoing=Raw(index+CornerSupport)-Raw(index);if(incoming.Length()<_spacing*CornerSupport*.75||outgoing.Length()<_spacing*CornerSupport*.75)return false;double turn=Math.Abs(incoming.AngleTo(outgoing));if(turn<1.05)return false;double immediate=Math.Abs((Raw(index)-Raw(index-1)).AngleTo(Raw(index+1)-Raw(index))),left=Math.Abs((Raw(index-2)-Raw(index-CornerSupport)).AngleTo(incoming)),right=Math.Abs(outgoing.AngleTo(Raw(index+CornerSupport)-Raw(index+2)));return immediate>turn*.4&&left<.2&&right<.2;
    }
    public Vector2 fit(int index,int count)
    {
        _viewVersion++;if(index==0||index==count-1||_corners[index]!=0||_strength<=0){_fitRadius[index]=-1;return Raw(index);}int first=Math.Max(0,index-Support),last=Math.Min(count-1,index+Support);double radius=2+34*Math.Pow(_strength,1.2);first=Math.Max(first,_leftCorner[index]);last=Math.Min(last,_rightCorner[index]);int curveFirst=Math.Max(first,index-(int)Math.Ceiling(radius)),curveLast=Math.Min(last,index+(int)Math.Ceiling(radius));double curvature=Math.Abs(_turnPrefix[curveLast+1]-_turnPrefix[curveFirst])/Math.Max(1,curveLast-curveFirst+1);if(curvature>.0001)radius=Math.Min(radius,Math.Max(1.5,.6/curvature));double s0=0,s1=0,s2=0,s3=0,s4=0;var b0=Vector2.Zero;var b1=Vector2.Zero;var b2=Vector2.Zero;first=Math.Max(first,index-(int)Math.Ceiling(radius*1.6));last=Math.Min(last,index+(int)Math.Ceiling(radius*1.6));var edge=Raw(last);if(_fitFirst[index]==first&&_fitLast[index]==last&&_fitRadius[index]==radius&&_fitEdge[index]==edge)return _knots[index];_fitFirst[index]=first;_fitLast[index]=last;_fitRadius[index]=radius;_fitEdge[index]=edge;var center=Raw(index);for(int other=first;other<=last;other++){double coordinate=other-index;if(other==_points.Count)coordinate-=1-_points[^1].DistanceTo(_tip)/_spacing;double t=coordinate/radius,t2=t*t,weight=Math.Exp(-2*t2);var weighted=(Raw(other)-center)*(float)weight;s0+=weight;s1+=weight*t;s2+=weight*t2;s3+=weight*t2*t;s4+=weight*t2*t2;b0+=weighted;b1+=weighted*(float)t;b2+=weighted*(float)t2;}double determinant=s0*(s2*s4-s3*s3)-s1*(s1*s4-s3*s2)+s2*(s1*s3-s2*s2);if(Math.Abs(determinant)<.000001)return Raw(index);var offset=(b0*(float)(s2*s4-s3*s3)+b1*(float)(s2*s3-s1*s4)+b2*(float)(s1*s3-s2*s2))/(float)determinant;double amount=1-Math.Pow(1-_strength,1.5),limit=_spacing*radius*.5*_strength;return Raw(index)+offset.LimitLength((float)limit)*(float)amount;
    }
    public Vector2 tangent(int index)
    {
        if(_corners[index]!=0)return Vector2.Zero;if(index==0)return _knots[Math.Min(1,_knots.Count-1)]-_knots[0];if(index==_knots.Count-1)return _knots[index]-_knots[index-1];var a=_knots[index]-_knots[index-1];var b=_knots[index+1]-_knots[index];return((a+b)*.5f).LimitLength(Math.Min(a.Length(),b.Length())*1.5f);
    }
    public Vector2[] path(int first,int last)
    {
        var result=new List<Vector2>{_knots[first]};if(_strength<=0){for(int index=first+1;index<=last;index++)result.Add(_knots[index]);return result.ToArray();}for(int index=first;index<last;index++){var a=_knots[index];var b=_knots[index+1];var ta=tangent(index);var tb=tangent(index+1);if(_corners[index]!=0)ta=b-a;if(_corners[index+1]!=0)tb=b-a;int divisions=Math.Clamp((int)Math.Ceiling(a.DistanceTo(b)/.75),1,12);for(int step=1;step<=divisions;step++){double t=(double)step/divisions,t2=t*t,t3=t2*t;result.Add(a*(float)(2*t3-3*t2+1)+ta*(float)(t3-2*t2+t)+b*(float)(-2*t3+3*t2)+tb*(float)(t3-t2));}}return result.ToArray();
    }
    public Vector2[] close_gap(int count)
    {
        if(count<32||_points[0].DistanceTo(_tip)>ConnectionRange||Math.Min(_rawBounds.Size.X,_rawBounds.Size.Y)<ConnectionRange*2||count*_spacing<ConnectionRange*8)return Array.Empty<Vector2>();double area=0;int stride=Math.Max(1,count/128);for(int index=0;index<count;index+=stride)area+=_knots[index].Cross(_knots[Math.Min(count-1,index+stride)]);area+=_knots[^1].Cross(_knots[0]);if(Math.Abs(area)*.5<_rawBounds.Area*.15)return Array.Empty<Vector2>();int span=Math.Min(Math.Clamp((int)Math.Ceiling(8/Math.Max(.1,_spacing)),1,12),(count-1)/5);var first=_knots[span];var last=_knots[count-1-span];var incoming=(last-_knots[Math.Max(0,count-1-span-2)]).Normalized();var outgoing=(_knots[Math.Min(count-1,span+2)]-first).Normalized();var chord=first-last;var direction=chord.Normalized();float handle=Math.Min(4,chord.Length()/3);if(incoming.Dot(direction)<.1)incoming=direction;if(outgoing.Dot(direction)<.1)outgoing=direction;var controlA=(last+incoming*handle).Clamp(_rawBounds.Position,_rawBounds.End);var controlB=(first-outgoing*handle).Clamp(_rawBounds.Position,_rawBounds.End);var result=new List<Vector2>(path(span,count-1-span));int divisions=Math.Clamp((int)Math.Ceiling(chord.Length()/.5),8,128);for(int step=1;step<=divisions;step++){double t=(double)step/divisions,u=1-t;result.Add(last*(float)(u*u*u)+controlA*(float)(3*u*u*t)+controlB*(float)(3*u*t*t)+first*(float)(t*t*t));}result[^1]=result[0];return result.ToArray();
    }
    public Settings update()
    {
        if(!_dirty)return new Settings();_viewVersion++;_dirty=false;int previousCount=_knots.Count,count=_points.Count+(_points[^1].IsEqualApprox(_tip)?0:1);Resize(_turnPrefix,count+1);for(int index=Math.Max(0,previousCount-3);index<count;index++){double turn=0;if(index>=2&&index<count-2)turn=(Raw(index)-Raw(index-2)).AngleTo(Raw(index+2)-Raw(index))*.25;_turnPrefix[index+1]=_turnPrefix[index]+turn;}Resize(_knots,count);Resize(_corners,count);Resize(_fitFirst,count);Resize(_fitLast,count);Resize(_fitRadius,count);Resize(_fitEdge,count);for(int index=Math.Max(0,previousCount-1-CornerSupport);index<count;index++)_corners[index]=(byte)(index==0||index==count-1||corner(index,count)?1:0);Resize(_leftCorner,count);Resize(_rightCorner,count);int cacheStart=Math.Max(0,previousCount-1-Support*2-CornerSupport),left=cacheStart>0?_leftCorner[cacheStart-1]:0;if(cacheStart>0&&_corners[cacheStart-1]!=0)left=cacheStart-1;for(int index=cacheStart;index<count;index++){_leftCorner[index]=left;if(_corners[index]!=0)left=index;}int right=count-1;for(int index=count-1;index>=cacheStart;index--){_rightCorner[index]=right;if(_corners[index]!=0)right=index;}for(int index=Math.Max(_sealed+1,previousCount-1-Support-CornerSupport);index<count;index++)_knots[index]=fit(index,count);_knots[0]=_points[0];int sealedCount=Math.Max(_sealed,count-Tail);var fixedPath=sealedCount>_sealed?path(_sealed,sealedCount):Array.Empty<Vector2>();var tail=path(sealedCount,count-1);_sealed=sealedCount;var patch=new Settings{["fixed"]=fixedPath,["tail"]=tail};if(_shapeRejected){patch["replace"]=path(0,count-1);return patch;}var closed=close_gap(count);if(closed.Length>0){patch["replace"]=closed;_gapClosed=true;}else if(_gapClosed){_shapeRejected=true;patch["replace"]=path(0,count-1);}return patch;
    }
}
public partial class StrokeCorrectorOperations:RefCounted
{
    public StrokeCorrectorKernel create()=>new();
}
