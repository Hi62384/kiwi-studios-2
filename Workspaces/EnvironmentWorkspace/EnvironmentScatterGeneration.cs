using Godot;
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class EnvironmentScatterOperations
{
    public Settings generate(Resource owner,Resource? terrain,Settings cancellation)
    {
        ulong started=Time.GetTicksUsec();var batches=new Settings();var ids=new Settings();var placements=new Settings();var errors=validate(owner);
        if(terrain==null||errors.Length>0)return new Settings {["batches"]=batches,["count"]=0,["error"]=terrain==null?"Choose a terrain.":string.Join("\n",errors)};
        terrain.Call("prepare");long seed=owner.Get("seed").AsInt64();using var rng=new RandomNumberGenerator {Seed=unchecked((ulong)seed)};var bounds=owner.Get("region").AsRect2().Abs();var palette=owner.Get("palette").AsGodotArray();double totalWeight=0;var weights=new float[palette.Count];var masks=new Masks(owner);double patchScale=owner.Get("patch_scale").AsDouble(),patchStrength=owner.Get("patch_strength").AsDouble();using var noise=new FastNoiseLite {Seed=unchecked((int)seed),Frequency=(float)(1/Math.Max(.01,patchScale)),FractalOctaves=2};
        for(int index=0;index<palette.Count;index++){totalWeight+=Math.Max(0,Get(palette[index].AsGodotDictionary(),"weight",1.0).AsDouble());weights[index]=(float)totalWeight;}if(totalWeight<=0)return new Settings {["batches"]=batches,["count"]=0,["error"]="At least one palette weight must be positive."};
        int desired=(int)Math.Min(Math.Clamp(owner.Get("budget").AsInt32(),1,20000),Math.Max(0,Math.Round(bounds.Area*Math.Max(0,owner.Get("density").AsDouble()),MidpointRounding.AwayFromZero))),count=0,attempts=0,maxAttempts=Math.Min(200000,Math.Max(100,desired*20));double spacing=Math.Max(.001,owner.Get("minimum_distance").AsDouble()),gridSize=spacing/Math.Sqrt(2);
        bool useAnchors=owner.Get("use_anchors").AsBool(),align=owner.Get("align_normal").AsBool();var anchors=owner.Get("anchor_points").AsGodotArray().Select(value=>value.AsTransform3D()).ToArray();var anchorIds=owner.Get("anchor_ids").AsStringArray();if(useAnchors){desired=Math.Min(Math.Clamp(owner.Get("budget").AsInt32(),1,20000),anchors.Length);maxAttempts=anchors.Length;}
        var clusters=new Vector2[Math.Clamp(owner.Get("cluster_count").AsInt32(),0,4096)];for(int index=0;index<clusters.Length;index++)clusters[index]=bounds.Position+new Vector2(rng.Randf(),rng.Randf())*bounds.Size;
        int domain=owner.Get("surface_domain").AsInt32();var caves=new List<TerrainCaveField>();if(domain>0){using var operations=new TerrainCaveOperations();foreach(var value in terrain.Get("caves").AsGodotArray()){var cave=value.As<Resource>();if(cave==null||!cave.Get("enabled").AsBool())continue;operations.prepare(cave);caves.Add(new TerrainCaveField(cave));}if(caves.Count==0)return new Settings {["batches"]=new Settings(),["count"]=0,["error"]="Cave scatter requires an enabled cave."};}
        using var sampler=new EnvironmentTerrainSampler(terrain);var occupied=new Dictionary<Vector2I,Vector2>();var paint=owner.Get("paint_regions").AsGodotArray().Select(value=>value.AsVector3()).ToArray();var erase=owner.Get("erase_regions").AsGodotArray().Select(value=>value.AsVector3()).ToArray();var overrides=owner.Get("overrides").AsGodotDictionary();
        var temperatureRange=owner.Get("temperature_range").AsVector2();var humidityRange=owner.Get("humidity_range").AsVector2();var shoreRange=owner.Get("shore_range").AsVector2();var waterRange=owner.Get("water_depth_range").AsVector2();var heightRange=owner.Get("height_range").AsVector2();var slopeRange=owner.Get("slope_range").AsVector2();var biomeIds=owner.Get("biome_ids").AsStringArray();double minimumBiome=owner.Get("minimum_biome_weight").AsDouble(),clusterRadius=Math.Max(.001,owner.Get("cluster_radius").AsDouble());var yaw=owner.Get("yaw_range").AsVector2();var scales=owner.Get("scale_range").AsVector2();int heightMode=owner.Get("anchor_height_mode").AsInt32();bool canCancel=Get(cancellation,"enabled",false).AsBool();using var candidateHash=new GArray {seed,0};using var emptyOverride=new Settings();var batchLists=new Dictionary<int,GArray>();var idLists=new Dictionary<int,GArray>();
        bool Outside(float[] field,int index,Vector2 limits)=>index<field.Length&&(field[index]<limits.X||field[index]>limits.Y);
        while(count<desired&&attempts<maxAttempts)
        {
            if(attempts%(domain>0?8:128)==0&&canCancel&&GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/terrain/terrain_erosion.gd").Call("_cancel_requested",cancellation).AsBool())return new Settings {["batches"]=new Settings(),["count"]=0,["error"]="Generation canceled."};
            attempts++;string identity=useAnchors&&anchorIds.Length>0?anchorIds[attempts-1]:seed.ToString(CultureInfo.InvariantCulture)+":"+attempts.ToString(CultureInfo.InvariantCulture);candidateHash[1]=useAnchors?Variant.From(identity):Variant.From(attempts);rng.Seed=unchecked((ulong)Hash(candidateHash));var replacement=overrides.TryGetValue(identity,out var overridden)?overridden.AsGodotDictionary():emptyOverride;if(Get(replacement,"deleted",false).AsBool())continue;
            var point=bounds.Position+new Vector2(rng.Randf(),rng.Randf())*bounds.Size;
            if(clusters.Length>0)point=clusters[rng.RandiRange(0,clusters.Length-1)]+Vector2.FromAngle((float)(rng.Randf()*Math.Tau))*(float)Math.Sqrt(rng.Randf())*(float)clusterRadius;
            if(useAnchors)point=new Vector2(anchors[attempts-1].Origin.X,anchors[attempts-1].Origin.Z);
            var caveHit=domain>0?CaveSurface(sampler,rng,caves,domain):null;if(domain>0){if(caveHit==null)continue;point=new Vector2(caveHit.Value.Position.X,caveHit.Value.Position.Z);}
            if(!bounds.HasPoint(point)||masks.Included.Length>0&&!masks.Included.Any(polygon=>Geometry2D.IsPointInPolygon(point,polygon))||masks.Excluded(point))continue;
            if(patchScale>0&&patchStrength>0){double coverage=Mathf.SmoothStep(-.35,.35,noise.GetNoise2Dv(point)),probability=Mathf.Lerp(1,coverage,patchStrength);if(rng.Randf()>probability)continue;}
            bool permitted=paint.Length==0;foreach(var area in paint)if(point.DistanceTo(new Vector2(area.X,area.Y))<=area.Z){permitted=true;break;}if(!permitted)continue;foreach(var area in erase)if(point.DistanceTo(new Vector2(area.X,area.Y))<=area.Z){permitted=false;break;}if(!permitted)continue;
            var cell=(Vector2I)(point/(float)gridSize).Floor();bool close=false;for(int y=-2;y<=2&&!close;y++)for(int x=-2;x<=2;x++)if(occupied.TryGetValue(cell+new Vector2I(x,y),out var other)&&point.DistanceTo(other)<spacing){close=true;break;}if(close)continue;
            if(domain==0&&!sampler.Inside(point))continue;double elevation=domain>0?caveHit!.Value.Position.Y:sampler.Height(point);var normal=domain>0?caveHit!.Value.Normal:sampler.Normal(point);int sampleIndex=sampler.Index(point);
            bool unsuitable=Outside(sampler.Temperature,sampleIndex,temperatureRange)||Outside(sampler.Humidity,sampleIndex,humidityRange)||Outside(sampler.Shore,sampleIndex,shoreRange);double waterDepth=0;
            if(waterRange.X>0||waterRange.Y<1000000)
            {
                bool nearby=domain>0;var position=(point/sampler.Dimensions+Vector2.One*.5f)*(sampler.N-1);var waterCell=(Vector2I)position.Floor();for(int z=0;z<2;z++)for(int x=0;x<2;x++){int index=Math.Clamp(waterCell.X+x,0,sampler.N-1)+Math.Clamp(waterCell.Y+z,0,sampler.N-1)*sampler.N;if(index<sampler.Depths.Length&&sampler.Depths[index]>0)nearby=true;}if(nearby)waterDepth=sampler.WaterDepth(new Vector3(point.X,(float)(elevation+.001),point.Y));
            }
            if(waterDepth<waterRange.X||waterDepth>waterRange.Y)unsuitable=true;if(unsuitable)continue;double slope=Mathf.RadToDeg(Math.Acos(Math.Clamp(domain>0?Math.Abs(normal.Y):normal.Y,-1,1)));if(elevation<heightRange.X||elevation>heightRange.Y||slope<slopeRange.X||slope>slopeRange.Y)continue;
            if(biomeIds.Length>0){double suitability=0;var biome=domain>0?sampler.CaveBiome(caveHit!.Value.Position):sampler.Biome(point);foreach(string id in biomeIds)if(biome.TryGetValue(id,out double value))suitability+=value;if(suitability<minimumBiome||rng.Randf()>Math.Clamp(suitability,0,1))continue;}
            double choice=rng.Randf()*totalWeight;int selected=0;while(selected<weights.Length-1&&choice>weights[selected])selected++;selected=Math.Clamp(Get(replacement,"palette",selected).AsInt32(),0,palette.Count-1);
            var basis=align?new Basis(new Quaternion(Vector3.Up,normal)):Basis.Identity;if(useAnchors)basis*=anchors[attempts-1].Basis;basis*=new Basis(Vector3.Up,(float)Mathf.DegToRad((double)rng.RandfRange(yaw.X,yaw.Y)));basis=basis.Scaled(Vector3.One*rng.RandfRange((float)Math.Max(.001,Math.Min(scales.X,scales.Y)),(float)Math.Max(.001,Math.Max(scales.X,scales.Y))));
            if(!batchLists.ContainsKey(selected)){var batch=new GArray();var identities=new GArray();batchLists[selected]=batch;idLists[selected]=identities;batches[selected]=batch;ids[selected]=identities;}if(useAnchors&&heightMode!=0)elevation=anchors[attempts-1].Origin.Y+(heightMode==1?elevation:0);var pose=Get(replacement,"transform",new Transform3D(basis,new Vector3(point.X,(float)elevation,point.Y))).AsTransform3D();batchLists[selected].Add(pose);idLists[selected].Add(identity);placements[identity]=new Settings {["transform"]=pose,["palette"]=selected};occupied[cell]=point;count++;
        }
        return new Settings {["batches"]=batches,["ids"]=ids,["placements"]=placements,["count"]=count,["requested"]=desired,["attempts"]=attempts,["milliseconds"]=(Time.GetTicksUsec()-started)/1000.0,["error"]="",["warning"]=count==desired?"":$"Placed {count} / {desired}: spacing, slope, height or painted region limits prevented denser placement."};
    }
}
