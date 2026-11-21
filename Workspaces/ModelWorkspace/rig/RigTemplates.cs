using Godot;
using System;
using Settings = Godot.Collections.Dictionary;

public partial class RigTemplates : RefCounted
{
    public static readonly System.Collections.Generic.Dictionary<string,string[]> Categories=new()
    {
        ["Humanoid"]=new[]{"Humanoid","Simple humanoid"},["Animals"]=new[]{"Quadruped","Bird","Fish","Snake","Insect","Spider"},
        ["Flexible"]=new[]{"Tail","Tentacle","Flexible chain","Branch","Long neck"},["Mechanical"]=new[]{"Hinged arm","Rotating shaft","Slider","Robot arm","Rigid assembly"}
    };
    private readonly RigMath _math = new();
    public Resource create(string kind, Aabb bounds, int count)
    {
        var rig = new KiwiModelComponent();
        rig.Set("id",Guid.NewGuid().ToString("N")); rig.Set("title",kind+" Rig"); rig.Set("is_skeleton",true);
        Vector3 dimensions=bounds.Size.Max(Vector3.One*.1f), center=bounds.GetCenter();
        Vector3 P(float x,float y,float z)=>center+new Vector3(x,y,z)*dimensions;
        int Add(Vector3 head,Vector3 end,int parent,string title)=>_math.add_bone(rig,head,end,parent,title);
        if(kind is "Humanoid" or "Simple humanoid")
        {
            int pelvis=Add(P(0,-.12f,0),P(0,.08f,0),-1,"pelvis");
            int spine=Add(P(0,.08f,0),P(0,.30f,0),pelvis,"spine");
            int neck=Add(P(0,.30f,0),P(0,.37f,0),spine,"neck");
            Add(P(0,.37f,0),P(0,.49f,0),neck,"head");
            foreach(float side in new[]{-1f,1f})
            {
                string suffix=side<0?"_L":"_R";
                int arm=Add(P(side*.10f,.29f,0),P(side*.30f,.23f,0),spine,"upper_arm"+suffix);
                int forearm=Add(P(side*.30f,.23f,0),P(side*.44f,.17f,0),arm,"forearm"+suffix);
                if(kind=="Humanoid") Add(P(side*.44f,.17f,0),P(side*.49f,.15f,0),forearm,"hand"+suffix);
                int thigh=Add(P(side*.09f,-.10f,0),P(side*.11f,-.29f,.01f),pelvis,"thigh"+suffix);
                int shin=Add(P(side*.11f,-.29f,.01f),P(side*.12f,-.46f,0),thigh,"shin"+suffix);
                if(kind=="Humanoid") Add(P(side*.12f,-.46f,0),P(side*.12f,-.48f,-.13f),shin,"foot"+suffix);
            }
        }
        else if(kind is "Quadruped" or "Bird" or "Insect" or "Spider")
        {
            int torso=Add(P(0,0,.3f),P(0,0,-.25f),-1,"body"), head=Add(P(0,0,-.25f),P(0,.12f,-.45f),torso,"head");
            if(kind=="Quadruped") Add(P(0,0,.3f),P(0,.1f,.49f),torso,"tail");
            int pairs=kind=="Spider"?4:kind=="Insect"?3:kind=="Bird"?1:2;
            bool spread=kind is "Spider" or "Insect";
            for(int i=0;i<pairs;i++) foreach(float side in new[]{-1f,1f})
            {
                float z=Mathf.Lerp(-.25f,.25f,(float)i/Math.Max(1,pairs-1)); string suffix="_"+i+(side<0?"_L":"_R");
                int upper=Add(P(side*.08f,0,z),P(side*.28f,spread?.05f:-.22f,z),torso,"limb"+suffix);
                var bones=rig.Get("bones").AsGodotArray();
                Add(_math.tail(bones[upper].AsGodotDictionary(),_math.globals(bones,false)[upper]),P(side*(spread?.46f:.3f),-.47f,z-.04f),upper,"tip"+suffix);
            }
            if(kind=="Bird") foreach(float side in new[]{-1f,1f}) Add(P(side*.1f,0,-.1f),P(side*.49f,.15f,0),head,side<0?"wing_L":"wing_R");
        }
        else
        {
            int axis=(int)dimensions.MaxAxisIndex(); Vector3 start=center,end=center;
            start[axis]-=dimensions[axis]*.48f; end[axis]+=dimensions[axis]*.48f;
            count=kind is "Rotating shaft" or "Slider"?1:kind=="Hinged arm"?2:kind=="Robot arm"?3:Math.Clamp(count,1,64);
            int parent=-1;
            for(int i=0;i<count;i++) parent=Add(start.Lerp(end,(float)i/count),start.Lerp(end,(float)(i+1)/count),parent,$"joint_{i:00}");
            if(kind=="Branch")
            {
                var bones=rig.Get("bones").AsGodotArray(); var world=_math.globals(bones,false); int initialCount=bones.Count;
                for(int i=1;i<initialCount-1;i+=2) Add(world[i].Origin,world[i].Origin+new Vector3(dimensions.X*.3f,dimensions.Y*.12f,0),i,"branch_"+i);
            }
        }
        _math.ensure(rig);
        var result=rig.Get("bones").AsGodotArray();
        foreach(Variant value in result)
        {
            Settings bone=value.AsGodotDictionary(); string name=bone["name"].AsString(); if(!name.EndsWith("_L",StringComparison.Ordinal)) continue;
            foreach(Variant otherValue in result)
            {
                Settings other=otherValue.AsGodotDictionary(); if(other["name"].AsString()!=name[..^2]+"_R") continue;
                bone["mirror_id"]=other["id"]; other["mirror_id"]=bone["id"];
            }
        }
        return rig;
    }
}
