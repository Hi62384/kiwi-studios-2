using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class EnvironmentScatterOperations
{
    private static double CaveDistance(Vector3 point,IReadOnlyList<TerrainCaveField> caves)
    {double value=double.PositiveInfinity;foreach(var cave in caves)value=Math.Min(value,cave.Distance(point));return value;}
    private static (Vector3 Position,Vector3 Normal)? CaveSurface(EnvironmentTerrainSampler terrain,RandomNumberGenerator rng,IReadOnlyList<TerrainCaveField> caves,int domain)
    {
        var cave=caves[rng.RandiRange(0,caves.Count-1)];var origin=Vector3.Zero;
        if(cave.Paths.Length>0){var path=cave.Paths[rng.RandiRange(0,cave.Paths.Length-1)];if(path.Length<2)return null;int index=rng.RandiRange(0,path.Length-2);origin=path[index].Lerp(path[index+1],rng.Randf());}
        else if(cave.Chambers.Length>0){var chamber=cave.Chambers[rng.RandiRange(0,cave.Chambers.Length-1)];origin=new Vector3(chamber.X,chamber.Y,chamber.Z);}else return null;
        origin+=new Vector3(rng.RandfRange(-.3f,.3f),rng.RandfRange(-.3f,.3f),rng.RandfRange(-.3f,.3f))*(float)cave.Radius;double angle=rng.Randf()*Math.Tau;
        var direction=domain==1?Vector3.Down:domain==2?Vector3.Up:new Vector3((float)Math.Cos(angle),rng.RandfRange(-.1f,.1f),(float)Math.Sin(angle)).Normalized();if(CaveDistance(origin,caves)>=0)return null;double distance=0,limit=Math.Min(1000,cave.Bounds().Size.Length()*2.0);
        for(int step=0;step<256;step++)
        {
            double air=CaveDistance(origin+direction*(float)distance,caves);
            if(air>=0)
            {
                double low=0,high=distance;for(int i=0;i<16;i++){double middle=(low+high)*.5;if(CaveDistance(origin+direction*(float)middle,caves)<0)low=middle;else high=middle;}
                var hit=origin+direction*(float)((low+high)*.5);var point=new Vector2(hit.X,hit.Z);if(!terrain.Inside(point)||hit.Y>=terrain.Height(point)-.02)return null;
                var x=new Vector3(.01f,0,0);var y=new Vector3(0,.01f,0);var z=new Vector3(0,0,.01f);var normal=-new Vector3((float)(CaveDistance(hit+x,caves)-CaveDistance(hit-x,caves)),(float)(CaveDistance(hit+y,caves)-CaveDistance(hit-y,caves)),(float)(CaveDistance(hit+z,caves)-CaveDistance(hit-z,caves))).Normalized();
                if(domain==1&&normal.Y<.5||domain==2&&normal.Y>-.5||domain==3&&Math.Abs(normal.Y)>.5)return null;return(hit,normal);
            }
            distance+=Math.Clamp(-air*.7,.03,.5);if(distance>limit)break;
        }
        return null;
    }
    public Settings cave_surface(Resource owner,Resource terrain,RandomNumberGenerator rng,GArray caves)
    {terrain.Call("prepare");using var sampler=new EnvironmentTerrainSampler(terrain);var hit=CaveSurface(sampler,rng,caves.Select(value=>new TerrainCaveField(value.As<Resource>())).ToArray(),owner.Get("surface_domain").AsInt32());return hit.HasValue?new Settings {["position"]=hit.Value.Position,["normal"]=hit.Value.Normal}:new Settings();}
    public double cave_distance(Vector3 point,GArray caves)=>CaveDistance(point,caves.Select(value=>new TerrainCaveField(value.As<Resource>())).ToArray());
}
