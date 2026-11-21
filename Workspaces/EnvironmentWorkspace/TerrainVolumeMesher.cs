using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class TerrainVolumeMesher : RefCounted
{
    private static readonly Vector3I[] Offsets={new(0,0,0),new(1,0,0),new(0,1,0),new(1,1,0),new(0,0,1),new(1,0,1),new(0,1,1),new(1,1,1)};
    private static readonly int[][] Tetrahedra={new[]{0,1,3,7},new[]{0,3,2,7},new[]{0,2,6,7},new[]{0,6,4,7},new[]{0,4,5,7},new[]{0,5,1,7}};
    private int _resolution;
    private Vector2 _dimensions;
    private float[] _base=Array.Empty<float>(),_edits=Array.Empty<float>(),_water=Array.Empty<float>(),_values=Array.Empty<float>();
    private readonly List<TerrainCaveField> _caves=new();private readonly List<Aabb> _bounds=new();
    private readonly List<Vector3> _vertices=new(),_normals=new();private readonly List<Vector2> _uv=new();private readonly List<int> _indices=new();private readonly List<byte> _kind=new();
    private readonly Dictionary<ulong,int> _edges=new();
    private float _epsilon=.05f;
    private Vector3 _origin,_spacing=Vector3.One;
    private Vector3I _counts=Vector3I.One;
    public void configure(Resource source,GArray caves,GArray bounds)
    {
        _resolution=source.Get("resolution").AsInt32();_dimensions=source.Get("dimensions").AsVector2();_base=source.Get("_base").AsFloat32Array();_edits=source.Get("edits").AsFloat32Array();
        var hydrology=source.Get("hydrology").As<Resource>();_water=hydrology!=null&&hydrology.Get("enabled").AsBool()?source.Get("water_delta").AsFloat32Array():Array.Empty<float>();
        _caves.Clear();_bounds.Clear();for(int index=0;index<caves.Count;index++){_caves.Add(new TerrainCaveField(caves[index].As<Resource>()));_bounds.Add(bounds[index].AsAabb());}
    }
    public double grid_height(int x,int z)=>Height(x,z);
    private double Height(int x,int z){int index=Math.Clamp(x,0,_resolution-1)+Math.Clamp(z,0,_resolution-1)*_resolution;return (double)_base[index]+_edits[index]+(_water.Length==_resolution*_resolution?_water[index]:0);}
    public double height(Vector2 point)
    {
        var p=((point/_dimensions+Vector2.One*.5f)*(_resolution-1)).Clamp(Vector2.Zero,Vector2.One*(_resolution-1));var cell=(Vector2I)p.Floor();var f=p-(Vector2)cell;
        return Mathf.Lerp(Mathf.Lerp(Height(cell.X,cell.Y),Height(cell.X+1,cell.Y),f.X),Mathf.Lerp(Height(cell.X,cell.Y+1),Height(cell.X+1,cell.Y+1),f.X),f.Y);
    }
    public double void_subtracted(Vector3 point,double surface)
    {double distance=double.PositiveInfinity;for(int index=0;index<_caves.Count;index++)if(_bounds[index].HasPoint(point))distance=Math.Min(distance,_caves[index].Distance(point));return Math.Max(surface,-distance);}
    public double density(Vector3 point)=>void_subtracted(point,point.Y-height(new Vector2(point.X,point.Z)));
    public Vector3 gradient(Vector3 point)
    {var x=new Vector3(_epsilon,0,0);var y=new Vector3(0,_epsilon,0);var z=new Vector3(0,0,_epsilon);return new Vector3((float)(density(point+x)-density(point-x)),(float)(density(point+y)-density(point-y)),(float)(density(point+z)-density(point-z))).Normalized();}
    public int index(Vector3I point)=>point.X+point.Y*_counts.X+point.Z*_counts.X*_counts.Y;
    public Vector3 position(int index)=>_origin+new Vector3(index%_counts.X,index/_counts.X%_counts.Y,index/(_counts.X*_counts.Y))*_spacing;
    public int edge(int a,int b)
    {
        ulong key=((ulong)(uint)Math.Min(a,b)<<32)|(uint)Math.Max(a,b);if(_edges.TryGetValue(key,out int existing))return existing;
        float amount=(float)Math.Clamp((double)_values[a]/((double)_values[a]-_values[b]),0,1);var point=position(a).Lerp(position(b),amount);int id=_vertices.Count;_vertices.Add(point);_normals.Add(gradient(point));_uv.Add(new Vector2(point.X,point.Z)/_dimensions);_edges[key]=id;return id;
    }
    public void triangle(int a,int b,int c)
    {
        var cross=(_vertices[b]-_vertices[a]).Cross(_vertices[c]-_vertices[a]);if(cross.LengthSquared()<.0000000001)return;
        var center=(_vertices[a]+_vertices[b]+_vertices[c])/3;_kind.Add(center.Y<height(new Vector2(center.X,center.Z))-_epsilon*.5? (byte)1:(byte)0);
        _indices.Add(a);if(cross.Dot(_normals[a]+_normals[b]+_normals[c])>0){_indices.Add(c);_indices.Add(b);}else{_indices.Add(b);_indices.Add(c);}
    }
    private static bool Cancelled(Settings cancellation)=>cancellation.TryGetValue("enabled",out var enabled)&&enabled.AsBool()&&GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/terrain/terrain_erosion.gd").Call("_cancel_requested",cancellation).AsBool();
    public Settings build(Resource source,Vector2I coordinate,GArray sources,double heightStep,int budget,Settings cancellation)
    {
        ulong started=Time.GetTicksUsec();
        // The façade prepares the source with its original cancel callback first.
        _vertices.Clear();_normals.Clear();_uv.Clear();_indices.Clear();_kind.Clear();_edges.Clear();
        var selected=new GArray();var bounds=new GArray();configure(source,selected,bounds);var start=coordinate*32;var cells=new Vector2I(Math.Min(32,_resolution-1-start.X),Math.Min(32,_resolution-1-start.Y));var horizontal=_dimensions/(_resolution-1);
        if(cells.X<=0||cells.Y<=0)return new Settings {["error"]="The volume chunk is outside its terrain."};
        double minimum=double.PositiveInfinity,maximum=double.NegativeInfinity;
        for(int z=0;z<=cells.Y;z++)for(int x=0;x<=cells.X;x++){double elevation=Height(start.X+x,start.Y+z);minimum=Math.Min(minimum,elevation);maximum=Math.Max(maximum,elevation);}
        double step=Math.Max(.1,heightStep);var chunkBounds=new Aabb(new Vector3((float)((start.X/(double)(_resolution-1)-.5)*_dimensions.X),-100000,(float)((start.Y/(double)(_resolution-1)-.5)*_dimensions.Y)),new Vector3(cells.X*horizontal.X,200000,cells.Y*horizontal.Y)).Grow(.001f);
        foreach(var value in sources)
        {
            var cave=value.As<Resource>();if(cave==null||!cave.Get("enabled").AsBool())continue;var field=new TerrainCaveField(cave);var box=field.Bounds();if(!box.Intersects(chunkBounds))continue;
            cave.Call("prepare");selected.Add(cave);bounds.Add(box);minimum=Math.Min(minimum,box.Position.Y);
        }
        configure(source,selected,bounds);int low=(int)Math.Floor(minimum/step),high=(int)Math.Ceiling(maximum/step);low-=2;high+=2;_counts=new Vector3I(cells.X+1,high-low+1,cells.Y+1);int total=checked(cells.X*cells.Y*(_counts.Y-1));
        if(total>budget)return new Settings {["error"]=$"Cave voxel budget exceeded ({total} cells). Increase vertical voxel size, reduce depth, or generate a smaller region.",["cells"]=total};
        _spacing=new Vector3(horizontal.X,(float)step,horizontal.Y);_epsilon=(float)(Math.Min(Math.Min(horizontal.X,horizontal.Y),step)*.2);_origin=new Vector3(chunkBounds.Position.X+.001f,(float)(low*step),chunkBounds.Position.Z+.001f);_values=new float[checked(_counts.X*_counts.Y*_counts.Z)];
        for(int z=0;z<_counts.Z;z++)
        {
            if(Cancelled(cancellation))return new Settings {["cancelled"]=true};
            for(int x=0;x<_counts.X;x++)
            {
                if(Cancelled(cancellation))return new Settings {["cancelled"]=true};double worldX=_origin.X+(double)x*_spacing.X,worldZ=_origin.Z+(double)z*_spacing.Z,elevation=height(new Vector2((float)worldX,(float)worldZ));
                for(int y=0;y<_counts.Y;y++){if(y%8==0&&Cancelled(cancellation))return new Settings {["cancelled"]=true};var point=new Vector3((float)worldX,(float)(_origin.Y+(double)y*_spacing.Y),(float)worldZ);_values[index(new Vector3I(x,y,z))]=(float)void_subtracted(point,point.Y-elevation);}
            }
        }
        var cornerIds=new int[8];var inside=new int[4];var outside=new int[4];
        for(int z=0;z<cells.Y;z++)
        {
            if(Cancelled(cancellation))return new Settings {["cancelled"]=true};
            for(int y=0;y<_counts.Y-1;y++)
            {
                if(Cancelled(cancellation))return new Settings {["cancelled"]=true};
                for(int x=0;x<cells.X;x++)
                {
                    bool air=false,solid=false;for(int i=0;i<8;i++){int id=index(new Vector3I(x,y,z)+Offsets[i]);cornerIds[i]=id;if(_values[id]<0)solid=true;else air=true;}if(!air||!solid)continue;
                    foreach(var tetrahedron in Tetrahedra)
                    {
                        int ni=0,no=0;foreach(int corner in tetrahedron){int id=cornerIds[corner];if(_values[id]<0)inside[ni++]=id;else outside[no++]=id;}
                        if(ni==1)triangle(edge(inside[0],outside[0]),edge(inside[0],outside[1]),edge(inside[0],outside[2]));
                        else if(ni==3)triangle(edge(outside[0],inside[0]),edge(outside[0],inside[1]),edge(outside[0],inside[2]));
                        else if(ni==2){int a=edge(inside[0],outside[0]),b=edge(inside[0],outside[1]),c=edge(inside[1],outside[0]),d=edge(inside[1],outside[1]);triangle(a,b,c);triangle(b,d,c);}
                    }
                }
            }
        }
        return new Settings {["vertices"]=_vertices.ToArray(),["normals"]=_normals.ToArray(),["uv"]=_uv.ToArray(),["indices"]=_indices.ToArray(),["triangle_kind"]=_kind.ToArray(),["cells"]=total,["milliseconds"]=(Time.GetTicksUsec()-started)/1000.0,["cancelled"]=false,["error"]="",["caves"]=selected,["cave_bounds"]=bounds};
    }
}
