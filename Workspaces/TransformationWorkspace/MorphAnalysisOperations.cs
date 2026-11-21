using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class MorphAnalysisOperations : RefCounted
{
    private sealed class Bin {public double Mass;public Vector2 Point;public Vector3 Rgb;}
    public Settings analyze(Image? image)
    {
        Settings Empty()=>new() {["empty"]=true,["regions"]=0,["holes"]=0,["palette"]=new GArray()};if(image==null||image.IsEmpty())return Empty();var size=image.GetSize();using var data=(Image)image.Duplicate();data.Convert(Image.Format.Rgba8);var pixels=data.GetData();var mask=new byte[checked(size.X*size.Y)];var bins=new Dictionary<int,Bin>();double mass=0;var center=Vector2.Zero;float maximum=0;for(int index=0;index<mask.Length;index++)maximum=Math.Max(maximum,pixels[index*4+3]/255f);if(maximum<.003f)return Empty();float threshold=Math.Min(.12f,maximum*.5f);
        for(int index=0;index<mask.Length;index++){int offset=index*4;float alpha=pixels[offset+3]/255f;mask[index]=(byte)(alpha>=threshold?1:0);if(alpha<threshold)continue;var uv=(new Vector2(index%size.X,index/size.X)+Vector2.One*.5f)/(Vector2)size;mass+=alpha;center+=uv*alpha;int r=pixels[offset],g=pixels[offset+1],b=pixels[offset+2],id=(r>>5)*64+(g>>5)*8+(b>>5);if(!bins.TryGetValue(id,out var bin)){bin=new Bin();bins[id]=bin;}bin.Mass+=alpha;bin.Point+=uv*alpha;bin.Rgb+=new Vector3(r,g,b)/255f*alpha;}
        center/=(float)Math.Max(.00001,mass);var features=new List<Settings>();foreach(var bin in bins.Values){if(bin.Mass<Math.Max(1,mass*.0005))continue;features.Add(new Settings {["point"]=bin.Point/(float)bin.Mass,["color"]=bin.Rgb/(float)bin.Mass,["mass"]=bin.Mass/mass});}features.Sort((first,last)=>last["mass"].AsDouble().CompareTo(first["mass"].AsDouble()));var palette=new GArray();for(int index=0;index<Math.Min(32,features.Count);index++)palette.Add(features[index]);
        using var bitmap=new Bitmap();bitmap.CreateFromImageAlpha(data,threshold);var polygons=bitmap.OpaqueToPolygons(new Rect2I(Vector2I.Zero,size),1.25f);var contour=Array.Empty<Vector2>();double area=0;foreach(var polygon in polygons){var points=polygon;double candidate=Math.Abs(signed_area(points));if(candidate>area){area=candidate;contour=(Vector2[])points.Clone();}}for(int index=0;index<contour.Length;index++)contour[index]=(contour[index]/(Vector2)size).Clamp(Vector2.Zero,Vector2.One);if(signed_area(contour)<0)Array.Reverse(contour);var topology=regions(mask,size);var bounds=new Rect2(center,Vector2.Zero);if(contour.Length>0){bounds=new Rect2(contour[0],Vector2.Zero);foreach(var point in contour)bounds=bounds.Expand(point);}return new Settings {["empty"]=false,["valid"]=contour.Length>=3,["contour"]=contour,["bounds"]=bounds,["center"]=center,["palette"]=palette,["mask"]=mask,["size"]=size,["regions"]=topology["regions"],["holes"]=topology["holes"]};
    }
    public double signed_area(Vector2[] points){double area=0;for(int index=0;index<points.Length;index++)area+=points[index].Cross(points[(index+1)%points.Length]);return area*.5;}
    public Settings regions(byte[] mask,Vector2I size)
    {
        var visited=new byte[mask.Length];var queue=new int[mask.Length];int regions=0,holes=0;for(int start=0;start<mask.Length;start++){if(visited[start]!=0)continue;byte ink=mask[start];queue[0]=start;int tail=1,cursor=0;visited[start]=1;bool border=false;while(cursor<tail){int index=queue[cursor++],x=index%size.X,y=index/size.X;border|=x==0||y==0||x==size.X-1||y==size.Y-1;void Visit(int next){if(next>=0&&visited[next]==0&&mask[next]==ink){visited[next]=1;queue[tail++]=next;}}Visit(x>0?index-1:-1);Visit(x<size.X-1?index+1:-1);Visit(y>0?index-size.X:-1);Visit(y<size.Y-1?index+size.X:-1);}if(ink!=0)regions++;else if(!border)holes++;}return new Settings {["regions"]=regions,["holes"]=holes};
    }
    public Vector2[] resample(Vector2[] points,int count)
    {
        if(points.Length<3)return Array.Empty<Vector2>();var result=new Vector2[Math.Max(0,count)];var lengths=new double[points.Length+1];double total=0;for(int index=0;index<points.Length;index++){total+=points[index].DistanceTo(points[(index+1)%points.Length]);lengths[index+1]=total;}int segment=0;for(int index=0;index<count;index++){double distance=total*index/count;while(segment+1<points.Length&&lengths[segment+1]<distance)segment++;result[index]=points[segment].Lerp(points[(segment+1)%points.Length],(float)((distance-lengths[segment])/Math.Max(.000001,lengths[segment+1]-lengths[segment])));}return result;
    }
    public Settings match(Settings first,Settings last,int count,string alignment)
    {
        var source=resample(first["contour"].AsVector2Array(),count);var target=resample(last["contour"].AsVector2Array(),count);double best=double.PositiveInfinity;int phase=0;var firstBounds=first["bounds"].AsRect2();var lastBounds=last["bounds"].AsRect2();for(int shift=0;shift<count;shift++){double score=0;for(int index=0;index<count;index++){int next=(index+shift)%count;var p=source[index];var q=target[next];if(alignment=="Bounds"){p=(p-firstBounds.Position)/firstBounds.Size.Max(Vector2.One*.001f);q=(q-lastBounds.Position)/lastBounds.Size.Max(Vector2.One*.001f);}float a=(source[(index+count-2)%count]-source[index]).Normalized().Dot((source[(index+2)%count]-source[index]).Normalized());float b=(target[(next+count-2)%count]-target[next]).Normalized().Dot((target[(next+2)%count]-target[next]).Normalized());score+=p.DistanceSquaredTo(q)+.06*Math.Abs(a-b);}if(score<best){best=score;phase=shift;}}var paired=new Vector2[count];for(int index=0;index<count;index++)paired[index]=target[(index+phase)%count];return new Settings {["a"]=source,["b"]=paired,["cost"]=best/count,["phase"]=phase};
    }
    public Godot.Collections.Array<Settings> landmarks(Settings first,Settings last)
    {
        var result=new Godot.Collections.Array<Settings>();var used=new HashSet<int>();var target=last["palette"].AsGodotArray();foreach(var raw in first["palette"].AsGodotArray()){var feature=raw.AsGodotDictionary();double best=.025;int chosen=-1;for(int index=0;index<target.Count;index++){if(used.Contains(index))continue;var other=target[index].AsGodotDictionary();double gap=feature["color"].AsVector3().DistanceSquaredTo(other["color"].AsVector3());double a=feature["mass"].AsDouble(),b=other["mass"].AsDouble();if(gap>best||Math.Min(a,b)/Math.Max(a,b)<.025)continue;best=gap;chosen=index;}if(chosen>=0){used.Add(chosen);result.Add(new Settings {["a"]=feature["point"],["b"]=target[chosen].AsGodotDictionary()["point"],["color"]=feature["color"]});}}return result;
    }
}

