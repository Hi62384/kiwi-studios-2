using Godot;
using System;
using Settings=Godot.Collections.Dictionary;

public partial class TerrainErosionOperations : RefCounted
{
    private static readonly Vector2I[] ThermalDirections={Vector2I.Right,Vector2I.Down};
    private static readonly Vector2I[] Directions={new(-1,0),new(1,0),new(0,-1),new(0,1)};
    private static double D(Resource operation,string key)=>operation.Get(key).AsDouble();
    private static bool Cancelled(Settings state)=>GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/terrain/terrain_erosion.gd").Call("_cancel_requested",state).AsBool();
    private static float Mask(Vector2 point,Settings values)
    {
        if(values.Count==0) return 1;
        double radius=Math.Max(.001,values.TryGetValue("radius",out var r)?r.AsDouble():1);
        var center=values.TryGetValue("center",out var c)?c.AsVector2():Vector2.Zero;
        double falloff=values.TryGetValue("falloff",out var f)?f.AsDouble():.25;
        double distance=point.DistanceTo(center)/radius;
        double weight=1-Mathf.SmoothStep(Math.Clamp(1-falloff,0,.999),1,distance);
        return (float)(values.TryGetValue("invert",out var invert)&&invert.AsBool()?1-weight:weight);
    }
    public Settings apply(Resource operation,float[] source,int n,Vector2 dimensions,Settings cancellation)
    {
        ulong started=Time.GetTicksUsec(); int count=checked(n*n);
        if(n<1 || source.Length!=count) throw new ArgumentException("Terrain erosion requires a square height grid.");
        var heights=(float[])source.Clone(); var eroded=new float[count];var deposited=new float[count];var water=new float[count];var sediment=new float[count];var accumulation=new float[count];var flow=new Vector2[count];var weights=new float[count];var rainPattern=new float[count];
        var spacing=dimensions/Math.Max(1,n-1); using var rng=new RandomNumberGenerator {Seed=unchecked((ulong)operation.Get("seed").AsInt64())}; var mask=operation.Get("mask").AsGodotDictionary();
        for(int z=0;z<n;z++) for(int x=0;x<n;x++) {int index=x+z*n; weights[index]=Mask((new Vector2(x,z)/Math.Max(1,n-1)-Vector2.One*.5f)*dimensions,mask);rainPattern[index]=rng.RandfRange(.8f,1.2f);}
        int iterations=Math.Clamp(operation.Get("iterations").AsInt32(),1,1000); bool thermal=operation.Get("mode").AsInt32()==1;
        double rainfall=Math.Max(0,D(operation,"rainfall")),flowRate=Math.Clamp(D(operation,"flow_rate"),0,1),minimum=D(operation,"minimum_slope"),capacityRate=Math.Max(0,D(operation,"sediment_capacity")),depositRate=Math.Clamp(D(operation,"deposition_rate"),0,1),strength=Math.Clamp(D(operation,"strength"),0,1),evaporation=Math.Clamp(D(operation,"evaporation"),0,1);
        bool canCancel=cancellation.TryGetValue("enabled",out var enabled)&&enabled.AsBool();
        var differences=new double[4];
        for(int iteration=0;iteration<iterations;iteration++)
        {
            if(canCancel&&Cancelled(cancellation)) return new Settings {["cancelled"]=true,["heights"]=source};
            if(thermal) {Thermal(operation,heights,n,spacing,weights,eroded,deposited);continue;}
            for(int index=0;index<count;index++) water[index]+=(float)(rainfall*rainPattern[index]*weights[index]);
            var nextWater=(float[])water.Clone();var nextSediment=(float[])sediment.Clone();var movedWater=new float[count];
            for(int z=0;z<n;z++)
            {
                if(z%8==0 && canCancel&&Cancelled(cancellation)) return new Settings {["cancelled"]=true,["heights"]=source};
                for(int x=0;x<n;x++)
                {
                    int index=x+z*n;if(water[index]<.000001)continue;
                    Array.Clear(differences);double total=0,head=(double)heights[index]+water[index];
                    for(int d=0;d<4;d++) {var neighbor=new Vector2I(x,z)+Directions[d];if(neighbor.X<0||neighbor.Y<0||neighbor.X>=n||neighbor.Y>=n)continue;int other=neighbor.X+neighbor.Y*n;double difference=Math.Max(0,head-heights[other]-water[other]);differences[d]=difference;total+=difference;}
                    if(total<=.000001)continue;
                    double outgoing=Math.Min(water[index],total*flowRate*.25),transferred=sediment[index]*(outgoing/water[index]);var vector=Vector2.Zero;
                    for(int d=0;d<4;d++) {if(differences[d]<=0)continue;double fraction=differences[d]/total;var neighbor=new Vector2I(x,z)+Directions[d];int other=neighbor.X+neighbor.Y*n;nextWater[other]+=(float)(outgoing*fraction);nextSediment[other]+=(float)(transferred*fraction);vector+=(Vector2)Directions[d]*spacing*(float)outgoing*(float)fraction;}
                    nextWater[index]-=(float)outgoing;nextSediment[index]-=(float)transferred;flow[index]+=vector;accumulation[index]+=(float)outgoing;movedWater[index]=(float)outgoing;
                }
            }
            water=nextWater;sediment=nextSediment;
            for(int z=0;z<n;z++)for(int x=0;x<n;x++)
            {
                int index=x+z*n;double slope=0;
                foreach(var direction in Directions) {var neighbor=new Vector2I(x,z)+direction;if(neighbor.X<0||neighbor.Y<0||neighbor.X>=n||neighbor.Y>=n)continue;double distance=direction.X!=0?spacing.X:spacing.Y;slope=Math.Max(slope,((double)heights[index]-heights[neighbor.X+neighbor.Y*n])/Math.Max(.001,distance));}
                double capacity=Math.Max(minimum,slope)*movedWater[index]*capacityRate;
                if(sediment[index]>capacity) {double amount=(sediment[index]-capacity)*depositRate*weights[index];sediment[index]-=(float)amount;heights[index]+=(float)amount;deposited[index]+=(float)amount;}
                else {double amount=Math.Min(.25,(capacity-sediment[index])*strength)*weights[index];sediment[index]+=(float)amount;heights[index]-=(float)amount;eroded[index]+=(float)amount;}
                water[index]*=(float)(1-evaporation);
                if(water[index]<.00001&&weights[index]>0) {heights[index]+=sediment[index];deposited[index]+=sediment[index];sediment[index]=0;}
            }
        }
        return new Settings {["heights"]=heights,["water"]=water,["sediment"]=sediment,["erosion"]=eroded,["deposition"]=deposited,["flow"]=flow,["accumulation"]=accumulation,["milliseconds"]=(Time.GetTicksUsec()-started)/1000.0,["cancelled"]=false};
    }
    public Settings thermal(Resource operation,float[] heights,int n,Vector2 spacing,float[] weights,float[] eroded,float[] deposited)
    { Thermal(operation,heights,n,spacing,weights,eroded,deposited); return new Settings {["heights"]=heights,["erosion"]=eroded,["deposition"]=deposited}; }
    private static void Thermal(Resource operation,float[] heights,int n,Vector2 spacing,float[] weights,float[] eroded,float[] deposited)
    {
        var delta=new float[n*n];double angle=Math.Tan(Mathf.DegToRad(Math.Clamp(D(operation,"talus_angle"),0,85))),rate=Math.Clamp(D(operation,"strength")*D(operation,"mobility"),0,1)*.25;
        for(int z=0;z<n;z++)for(int x=0;x<n;x++)
        {
            int index=x+z*n;
            foreach(var direction in ThermalDirections)
            {
                var neighbor=new Vector2I(x,z)+direction;if(neighbor.X>=n||neighbor.Y>=n)continue;int other=neighbor.X+neighbor.Y*n;
                double difference=(double)heights[index]-heights[other],threshold=angle*(direction.X!=0?spacing.X:spacing.Y),amount=Math.Max(0,Math.Abs(difference)-threshold)*rate*Math.Min(weights[index],weights[other]);
                if(difference>0) {delta[index]-=(float)amount;delta[other]+=(float)amount;} else {delta[index]+=(float)amount;delta[other]-=(float)amount;}
            }
        }
        for(int index=0;index<delta.Length;index++){heights[index]+=delta[index];if(delta[index]>0)deposited[index]+=delta[index];else eroded[index]-=delta[index];}
    }
}
