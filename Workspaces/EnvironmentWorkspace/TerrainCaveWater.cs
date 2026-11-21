using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class TerrainCaveWater : RefCounted
{
    private const float Dry=-1e20f;
    private static readonly Vector3I[] Directions={Vector3I.Left,Vector3I.Right,Vector3I.Up,Vector3I.Down,Vector3I.Forward,Vector3I.Back};
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private static bool Cancelled(Settings state)=>Get(state,"enabled",false).AsBool()&&GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/terrain/terrain_erosion.gd").Call("_cancel_requested",state).AsBool();
    private static double Void(Vector3 point,IReadOnlyList<TerrainCaveField> sources){double value=double.PositiveInfinity;foreach(var source in sources)value=Math.Min(value,source.Distance(point));return value;}
    public double void_distance(Vector3 point,GArray sources)=>Void(point,sources.Select(value=>new TerrainCaveField(value.As<Resource>())).ToArray());
    public Vector3[] clip(Vector3[] points,float[] field)
    {
        var result=new List<Vector3>();for(int index=0;index<points.Length;index++){int next=(index+1)%points.Length;double a=field[index],b=field[next];if(a>0)result.Add(points[index]);if((a>0)!=(b>0))result.Add(points[index].Lerp(points[next],(float)(a/(a-b))));}return result.ToArray();
    }
    public Settings generate(Resource terrain,Settings cancellation)
    {
        var sources=new List<TerrainCaveField>();var bounds=new Aabb();bool first=true;
        foreach(var value in terrain.Get("caves").AsGodotArray()){var cave=value.As<Resource>();if(cave==null||!cave.Get("enabled").AsBool())continue;cave.Call("prepare");var source=new TerrainCaveField(cave);sources.Add(source);bounds=first?source.Bounds():bounds.Merge(source.Bounds());first=false;}
        if(first)return new Settings();int n=terrain.Get("resolution").AsInt32();var water=terrain.Get("water_data").AsGodotDictionary();var levels=Get(water,"levels",Array.Empty<float>()).AsFloat32Array();var depths=Get(water,"depth",Array.Empty<float>()).AsFloat32Array();double highest=Dry;
        for(int index=0;index<levels.Length;index++)if(depths[index]>.0001)highest=Math.Max(highest,levels[index]);if(highest<=Dry*.5)return new Settings();
        var dimensions=terrain.Get("dimensions").AsVector2();var dxz=dimensions/(n-1);var begin=((new Vector2(bounds.Position.X,bounds.Position.Z)/dimensions+Vector2.One*.5f)*(n-1)).Floor();var finish=((new Vector2(bounds.End.X,bounds.End.Z)/dimensions+Vector2.One*.5f)*(n-1)).Ceil();
        var start=new Vector2I(Math.Max(0,(int)begin.X),Math.Max(0,(int)begin.Y));var end=new Vector2I(Math.Min(n-1,(int)finish.X),Math.Min(n-1,(int)finish.Y));double dy=Math.Max(.1,terrain.Get("voxel_height").AsDouble()),lower=Math.Floor(bounds.Position.Y/dy)*dy-dy,upper=Math.Min(highest+dy,bounds.End.Y+dy);
        if(end.X<=start.X||end.Y<=start.Y||upper<=lower)return new Settings();lower=highest-Math.Ceiling((highest-bounds.Position.Y)/dy)*dy-dy;
        var size=new Vector3I(end.X-start.X+1,(int)Math.Ceiling((upper-lower)/dy)+1,end.Y-start.Y+1);int count=checked(size.X*size.Y*size.Z);if(count>terrain.Get("voxel_cell_budget").AsInt64())return new Settings {["error"]="Cave water volume budget exceeded. Increase voxel height, reduce cave extent or increase the voxel budget."};
        var origin=new Vector3((float)((start.X/(double)(n-1)-.5)*dimensions.X),(float)lower,(float)((start.Y/(double)(n-1)-.5)*dimensions.Y));var spacing=new Vector3(dxz.X,(float)dy,dxz.Y);var air=new byte[count];var heads=new float[count];Array.Fill(heads,Dry);var heap=new PriorityQueue<int,(float,int)>();
        using var sampler=new TerrainVolumeMesher();sampler.configure(terrain,new GArray(),new GArray());
        for(int z=0;z<size.Z;z++)
        {
            if(Cancelled(cancellation))return new Settings {["cancelled"]=true};
            for(int x=0;x<size.X;x++)
            {
                int sourceIndex=start.X+x+(start.Y+z)*n;double ground=sampler.grid_height(start.X+x,start.Y+z);
                for(int y=0;y<size.Y;y++)
                {
                    int index=x+y*size.X+z*size.X*size.Y;var point=origin+new Vector3(x,y,z)*spacing;bool inside=point.Y>ground+.00001||Void(point,sources)<-.00001;
                    if(index%128==0&&Cancelled(cancellation))return new Settings {["cancelled"]=true};if(!inside)continue;air[index]=1;
                    if(point.Y>ground+.00001&&depths[sourceIndex]>.0001&&point.Y<=levels[sourceIndex]+.00001){heads[index]=levels[sourceIndex];heap.Enqueue(index,(-heads[index],index));}
                }
            }
        }
        var visited=new byte[count];int iterations=0;
        while(heap.Count>0)
        {
            iterations++;if(iterations%128==0&&Cancelled(cancellation))return new Settings {["cancelled"]=true};int index=heap.Dequeue();if(visited[index]!=0)continue;visited[index]=1;
            int x=index%size.X,y=index/size.X%size.Y,z=index/(size.X*size.Y);float head=heads[index];
            foreach(var offset in Directions){var p=new Vector3I(x,y,z)+offset;if(p.X<0||p.Y<0||p.Z<0||p.X>=size.X||p.Y>=size.Y||p.Z>=size.Z||origin.Y+p.Y*dy>head+.00001)continue;int neighbor=p.X+p.Y*size.X+p.Z*size.X*size.Y;if(air[neighbor]==0||visited[neighbor]!=0||heads[neighbor]>=head-.00001)continue;heads[neighbor]=head;heap.Enqueue(neighbor,(-head,neighbor));}
        }
        var columns=new float[size.X*size.Z];Array.Fill(columns,Dry);var floors=new float[columns.Length];Array.Fill(floors,float.PositiveInfinity);
        for(int z=0;z<size.Z;z++)for(int x=0;x<size.X;x++)for(int y=0;y<size.Y;y++){int index=x+y*size.X+z*size.X*size.Y;if(heads[index]<=Dry*.5)continue;columns[x+z*size.X]=Math.Max(columns[x+z*size.X],heads[index]);floors[x+z*size.X]=(float)Math.Min(floors[x+z*size.X],origin.Y+y*dy-dy*.5);}
        var mesh=Get(water,"mesh",new Settings()).AsGodotDictionary().Duplicate(true);
        var vertices=Get(mesh,"vertices",Array.Empty<Vector3>()).AsVector3Array().ToList();var normals=Get(mesh,"normals",Array.Empty<Vector3>()).AsVector3Array().ToList();var uv=Get(mesh,"uv",Array.Empty<Vector2>()).AsVector2Array().ToList();var uv2=Get(mesh,"uv2",Array.Empty<Vector2>()).AsVector2Array().ToList();var colors=Get(mesh,"colors",Array.Empty<Color>()).AsColorArray().ToList();var indices=Get(mesh,"indices",Array.Empty<int>()).AsInt32Array().ToList();
        var hydro=terrain.Get("hydrology").As<Resource>();int budget=hydro.Get("mesh_vertex_budget").AsInt32();var wave=hydro.Get("wave_direction").AsVector2();
        for(int z=0;z<size.Z-1;z++)
        {
            if(Cancelled(cancellation))return new Settings {["cancelled"]=true};
            for(int x=0;x<size.X-1;x++)foreach(var triangle in new[]{new[]{new Vector2I(x,z),new Vector2I(x+1,z),new Vector2I(x,z+1)},new[]{new Vector2I(x+1,z),new Vector2I(x+1,z+1),new Vector2I(x,z+1)}})
            {
                double head=Dry;foreach(var p in triangle)head=Math.Max(head,columns[p.X+p.Y*size.X]);if(head<=Dry*.5)continue;
                var points=new Vector3[3];var field=new float[3];double bed=head;
                for(int i=0;i<3;i++)
                {
                    var p=triangle[i];var point=new Vector3(origin.X+p.X*spacing.X,(float)head,origin.Z+p.Y*spacing.Z);double ground=sampler.grid_height(start.X+p.X,start.Y+p.Y);points[i]=point;int y=Math.Clamp((int)Math.Floor((head-origin.Y)/dy),0,size.Y-1);bool connected=heads[p.X+y*size.X+p.Y*size.X*size.Y]>=head-.001;
                    field[i]=(float)(connected?Math.Min(-Void(point,sources),ground-head):-dy);bed=Math.Min(bed,floors[p.X+p.Y*size.X]);
                }
                var polygon=clip(points,field);if(polygon.Length<3)continue;if(vertices.Count+polygon.Length>budget)return new Settings {["error"]="Cave water mesh budget exceeded."};int basis=vertices.Count;
                foreach(var point in polygon){vertices.Add(point);normals.Add(Vector3.Up);uv.Add(new Vector2(point.X,point.Z));uv2.Add(wave);colors.Add(new Color(0,(float)Math.Clamp((head-bed)/20,0,1),0,1));}
                for(int i=1;i<polygon.Length-1;i++){indices.Add(basis);indices.Add(basis+i);indices.Add(basis+i+1);}
            }
        }
        mesh["vertices"]=vertices.ToArray();mesh["normals"]=normals.ToArray();mesh["uv"]=uv.ToArray();mesh["uv2"]=uv2.ToArray();mesh["colors"]=colors.ToArray();mesh["indices"]=indices.ToArray();
        return new Settings {["origin"]=origin,["spacing"]=spacing,["size"]=size,["heads"]=heads,["floors"]=floors,["mesh"]=mesh,["voxels"]=count};
    }
    internal sealed class Sampler
    {
        private readonly Vector3 _origin,_spacing;
        private readonly Vector3I _size;
        private readonly float[] _heads=Array.Empty<float>();
        private readonly IReadOnlyList<TerrainCaveField> _sources=Array.Empty<TerrainCaveField>();
        internal Sampler(Resource terrain,IReadOnlyList<TerrainCaveField>? prepared=null)
        {
            var field=Get(terrain.Get("water_data").AsGodotDictionary(),"cave_volume",new Settings()).AsGodotDictionary();if(field.Count==0)return;
            _origin=field["origin"].AsVector3();_spacing=field["spacing"].AsVector3();_size=field["size"].AsVector3I();_heads=field["heads"].AsFloat32Array();
            if(prepared!=null){_sources=prepared;return;}
            var sources=new List<TerrainCaveField>();foreach(var value in terrain.Get("caves").AsGodotArray()){var cave=value.As<Resource>();if(cave==null||!cave.Get("enabled").AsBool())continue;if(cave.Get("_noise").As<FastNoiseLite>()==null)cave.Call("prepare");sources.Add(new TerrainCaveField(cave));}_sources=sources;
        }
        internal Settings Query(Vector3 point)
        {
            if(_heads.Length==0)return new Settings();var p=(Vector3I)((point-_origin)/_spacing).Round();
            if(p.X<0||p.Y<0||p.Z<0||p.X>=_size.X||p.Y>=_size.Y||p.Z>=_size.Z||Void(point,_sources)>=0)return new Settings();
            double head=_heads[p.X+p.Y*_size.X+p.Z*_size.X*_size.Y];if(head<=Dry*.5)return new Settings();int y=p.Y;
            while(y>0&&_heads[p.X+(y-1)*_size.X+p.Z*_size.X*_size.Y]>Dry*.5)y--;double bottom=_origin.Y+(y-.5)*_spacing.Y;
            return new Settings {["surface"]=new Vector3(point.X,(float)head,point.Z),["depth"]=head-bottom,["flow"]=Vector3.Zero,["inside"]=point.Y<=head&&point.Y>=bottom,["bottom"]=bottom,["cave"]=true};
        }
    }
    public Settings query(Resource terrain,Vector3 point)=>new Sampler(terrain).Query(point);
}
