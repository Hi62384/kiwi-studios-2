using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class TerrainHydrologyOperations
{
    private sealed partial class Context
    {
        internal void Flood(int[] seeds,double level,float[] ground,float[] levels,byte[] kinds,byte kind)
        {
            var queue=new List<int>(seeds);var seen=new bool[N*N];int cursor=0;
            while(cursor<queue.Count)
            {
                if(cursor%128==0&&Cancelled())return;int index=queue[cursor++];if(seen[index])continue;seen[index]=true;if(ground[index]>=level-.000001||levels[index]>=level-.000001)continue;levels[index]=(float)level;kinds[index]=kind;var point=new Vector2I(index%N,index/N);
                foreach(var direction in Directions){var next=point+direction;if(next.X>=0&&next.Y>=0&&next.X<N&&next.Y<N)queue.Add(next.X+next.Y*N);}
            }
        }
        internal List<Settings> Rivers(float[] source,float[] filled,int[] downstream,float[] accumulation,float[] levels)
        {
            var eligible=new byte[N*N];var parents=new int[N*N];var heads=new List<int>();double threshold=Math.Max(.01,D("catchment_threshold"));
            for(int index=0;index<eligible.Length;index++)if(downstream[index]>=0&&accumulation[index]>=threshold&&levels[index]<Dry*.5)eligible[index]=1;
            for(int index=0;index<eligible.Length;index++)if(eligible[index]!=0&&downstream[index]>=0&&eligible[downstream[index]]!=0)parents[downstream[index]]++;
            for(int index=0;index<eligible.Length;index++)if(eligible[index]!=0&&parents[index]==0)heads.Add(index);
            var sorted=heads.OrderByDescending(index=>accumulation[index]).ThenBy(index=>index);var seen=new Dictionary<int,float>();var paths=new List<Settings>();
            foreach(int start in sorted)
            {
                if(Cancelled())return paths;var cells=new List<int>();int current=start;double length=0;
                while(current>=0&&cells.Count<N*N){if(cells.Count>0)length+=Point(current).DistanceTo(Point(cells[^1]));cells.Add(current);if(seen.ContainsKey(current)||levels[current]>Dry*.5)break;current=downstream[current];}
                if(cells.Count<2||(double)filled[cells[0]]-filled[cells[^1]]<Math.Max(.0001,length*Math.Max(0,D("minimum_river_slope"))))continue;
                var points=new Vector3[cells.Count];var widths=new float[cells.Count];double depth=Math.Max(.01,D("river_depth"));
                for(int i=0;i<cells.Count;i++)
                {
                    int index=cells[i];var point=Point(index);point.Y=seen.TryGetValue(index,out float previous)?previous:levels[index]>Dry*.5?levels[index]:(float)(filled[index]-depth*.35);points[i]=point;
                    widths[i]=(float)Math.Max(Math.Max(Spacing.X,Spacing.Y)*1.25,Math.Max(.1,D("river_width"))*Math.Clamp(Math.Sqrt(accumulation[index]/threshold),1,4));
                }
                for(int i=points.Length-2;i>=0;i--)points[i].Y=Math.Max(points[i].Y,points[i+1].Y);for(int i=0;i<cells.Count;i++)seen[cells[i]]=points[i].Y;
                paths.Add(new Settings {["id"]=$"drainage:{start}",["points"]=points,["widths"]=widths,["depth"]=depth,["automatic"]=true});if(paths.Count>Math.Clamp(I("maximum_rivers"),1,256))break;
            }
            return paths;
        }
        internal void Carve(Settings path,float[] source,float[] delta,float[] levels,Vector2[] flow,GArray waterfalls)
        {
            var points=path["points"].AsVector3Array();var widths=path["widths"].AsFloat32Array();double depth=Math.Max(.01,path["depth"].AsDouble());
            for(int segment=0;segment<points.Length-1;segment++)
            {
                var a=points[segment];var b=points[segment+1];var a2=new Vector2(a.X,a.Z);var b2=new Vector2(b.X,b.Z);var direction=b2-a2;if(direction.LengthSquared()<.000001)continue;
                double bank=Math.Max(widths[segment],widths[segment+1])*.5/.860662966;var begin=((a2.Min(b2)-Vector2.One*(float)bank)/Dimensions+Vector2.One*.5f)*(N-1);var finish=(((a2.Max(b2)+Vector2.One*(float)bank)/Dimensions+Vector2.One*.5f)*(N-1)).Ceil();
                for(int z=Math.Max(0,(int)begin.Y);z<=Math.Min(N-1,(int)finish.Y);z++)for(int x=Math.Max(0,(int)begin.X);x<=Math.Min(N-1,(int)finish.X);x++)
                {
                    int index=x+z*N;var point=Point(index);var p=new Vector2(point.X,point.Z);double along=Math.Clamp((p-a2).Dot(direction)/(double)direction.LengthSquared(),0,1),distance=p.DistanceTo(a2+direction*(float)along),width=Mathf.Lerp((double)widths[segment],widths[segment+1],along),radius=width*.5/.860662966;if(distance>radius)continue;
                    double water=Mathf.Lerp((double)a.Y,b.Y,along),weight=Math.Max(0,1-distance*distance/(radius*radius)),target=Mathf.Lerp(source[index],water-depth,weight);delta[index]=(float)Math.Min(delta[index],target-source[index]);
                    if(distance<=width*.5+Math.Max(Spacing.X,Spacing.Y)*.1){levels[index]=(float)Math.Max(levels[index],water);flow[index]=direction.Normalized()*(float)D("flow_speed");}
                }
                if((double)a.Y-b.Y>=Math.Max(.1,D("waterfall_drop")))waterfalls.Add(new Settings {["from"]=a,["to"]=b,["width"]=((double)widths[segment]+widths[segment+1])*.5,["drop"]=(double)a.Y-b.Y,["flow"]=direction.Normalized()});
            }
        }
        internal float[] Distance(byte[] wet,bool toWater)
        {
            var distance=new float[wet.Length];Array.Fill(distance,Dimensions.Length()*2);var heap=new PriorityQueue<int,(float,int)>();
            for(int index=0;index<wet.Length;index++)if((wet[index]!=0)==toWater){distance[index]=0;heap.Enqueue(index,(0,index));}
            int iterations=0;
            while(heap.Count>0)
            {
                iterations++;if(iterations%128==0&&Cancelled())return distance;heap.TryDequeue(out int index,out var item);if(item.Item1>distance[index]+.00001)continue;var point=new Vector2I(index%N,index/N);
                for(int dz=-1;dz<=1;dz++)for(int dx=-1;dx<=1;dx++)
                {
                    if(dx==0&&dz==0)continue;var next=point+new Vector2I(dx,dz);if(next.X<0||next.Y<0||next.X>=N||next.Y>=N)continue;int neighbor=next.X+next.Y*N;double value=(double)distance[index]+(new Vector2(dx,dz)*Spacing).Length();if(value<distance[neighbor]){distance[neighbor]=(float)value;heap.Enqueue(neighbor,((float)value,neighbor));}
                }
            }
            return distance;
        }
    }
}
