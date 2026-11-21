using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class WorldSettlementOperations
{
    public Settings layout_initial(Resource source)
    {
        var nodes=new Settings();var roads=new Godot.Collections.Array<Settings>();var plots=new Godot.Collections.Array<Settings>();var blocks=new Godot.Collections.Array<Settings>();var warnings=new List<string>();
        foreach(var value in source.Get("settlements").AsGodotArray())
        {
            var settlement=value.AsGodotDictionary();if(!Get(settlement,"enabled",true).AsBool()||Get(settlement,"layout_mode","Grid").AsString()=="Road network")continue;
            string prefix=settlement["id"].AsString(),profile=Get(settlement,"profile","Town").AsString();var center=settlement["center"].AsVector3();double radius=Get(settlement,"radius",48.0).AsDouble();using var rng=new RandomNumberGenerator();rng.Seed=unchecked((ulong)Get(settlement,"seed",1).AsInt64());
            if(profile=="Village")
            {
                const int spokes=5;for(int spoke=0;spoke<spokes;spoke++)
                {
                    double angle=Math.Tau*spoke/spokes+rng.RandfRange(-.18f,.18f);var direction=new Vector3((float)Math.Cos(angle),0,(float)Math.Sin(angle));var side=new Vector3(-direction.Z,0,direction.X);var end=center+direction*(float)radius*rng.RandfRange(.8f,1);string startId=prefix+":center",endId=prefix+":end:"+spoke,roadId=prefix+":lane:"+spoke;nodes[startId]=center;nodes[endId]=end;roads.Add(road(roadId,startId,endId,new[]{center,center.Lerp(end,.5f)+side*rng.RandfRange(-3,3),end},3,prefix));
                    for(int row=0;row<2;row++)foreach(float sign in new[]{-1f,1f})
                    {double depth=rng.RandfRange(7,10),width=rng.RandfRange(6,9);var position=center+direction*(float)radius*(float)(.38+row*.35)+side*sign*(float)(depth*.5+4);var pose=new Transform3D(Basis.LookingAt(-side*sign,Vector3.Up),position);string id=prefix+":plot:"+spoke+":"+row+":"+(sign<0?"-1.0":"1.0");plots.Add(new Settings {["id"]=id,["settlement"]=prefix,["block"]="",["polygon"]=rectangle(pose,width+2,depth+2),["pose"]=pose,["width"]=width,["depth"]=depth,["frontage"]=roadId,["district"]="Rural",["reserved"]=false});}
                }
            }
            else
            {
                int count=Math.Clamp(Get(settlement,"blocks",3).AsInt32(),1,6);double step=radius*2/count,roadWidth=profile=="City"&&radius>=24?8:5;
                for(int line=0;line<=count;line++)for(int axis=0;axis<2;axis++)
                {var a=center+new Vector3((float)-radius,0,(float)-radius);var b=a;if(axis==0){a.X+=(float)(step*line);b=new Vector3(a.X,center.Y,(float)(center.Z+radius));}else{a.Z+=(float)(step*line);b=new Vector3((float)(center.X+radius),center.Y,a.Z);}string roadId=prefix+":street:"+axis+":"+line,from=roadId+":a",to=roadId+":b";nodes[from]=a;nodes[to]=b;roads.Add(road(roadId,from,to,new[]{a,b},roadWidth,prefix));}
                for(int z=0;z<count;z++)for(int x=0;x<count;x++)
                {
                    var position=center+new Vector3((float)(-radius+step*(x+.5)),0,(float)(-radius+step*(z+.5)));string blockId=prefix+":block:"+x+":"+z,district=profile=="City"&&x==count/2&&z==count/2?"Downtown":profile=="City"&&z==count-1?"Industrial":"Residential";double usable=step-roadWidth-2*Get(settlement,"setback",2.0).AsDouble();if(usable<6){warnings.Add(Get(settlement,"name",prefix).AsString()+": blocks are too small for usable buildings.");continue;}var pose=new Transform3D(Basis.Identity,position);var polygon=rectangle(pose,usable,usable);blocks.Add(new Settings {["id"]=blockId,["settlement"]=prefix,["polygon"]=polygon,["district"]=district});plots.Add(new Settings {["id"]=blockId+":plot",["settlement"]=prefix,["block"]=blockId,["polygon"]=polygon,["pose"]=pose,["width"]=usable*rng.RandfRange(.65f,.85f),["depth"]=usable*rng.RandfRange(.65f,.85f),["frontage"]=prefix+":street:1:"+z,["district"]=district,["reserved"]=false});
                }
            }
        }
        return new Settings {["nodes"]=nodes,["roads"]=roads,["plots"]=plots,["blocks"]=blocks,["warnings"]=warnings.ToArray()};
    }
}
