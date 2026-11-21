using Godot;
using System;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class BuildingGeometryOperations
{
    public bool stair_crosses(Resource source,Settings stair,double elevation)
    {
        double low=double.PositiveInfinity,high=double.NegativeInfinity;
        foreach(var value in source.Get("floors").AsGodotArray())
        {
            var floor=value.AsGodotDictionary();string id=Get(floor,"id", "").AsString();
            if(id==Get(stair,"from", "").AsString())low=Get(floor,"elevation",0.0).AsDouble();
            if(id==Get(stair,"to", "").AsString())high=Get(floor,"elevation",0.0).AsDouble();
        }
        return high>low&&elevation>low+.001&&elevation<=high+.001;
    }
    public Rect2 stair_bounds(Settings stair)
    {
        float width=(float)Math.Max(.3,Get(stair,"width",1.0).AsDouble()),length=(float)Math.Max(.5,Get(stair,"length",4.0).AsDouble());int kind=Get(stair,"type",0).AsInt32();
        var bounds=new Rect2(-width*.5f,-.05f,width,length+.1f);
        if(kind==1)bounds=new Rect2(-width*.5f,-.05f,length*.5f+width,length*.5f+width+.1f);
        if(kind==2)bounds=new Rect2(-width*.5f,-.05f,width*3,length*.5f+width+.1f);
        if(kind==3)bounds=new Rect2(-Vector2.One*width*1.4f,Vector2.One*width*2.8f);
        var position=Get(stair,"position",Vector2.Zero).AsVector2();float angle=Mathf.DegToRad((float)Get(stair,"yaw",0.0).AsDouble());var result=new Rect2();bool first=true;
        foreach(var corner in new[]{bounds.Position,new Vector2(bounds.End.X,bounds.Position.Y),bounds.End,new Vector2(bounds.Position.X,bounds.End.Y)})
        {var point=corner.Rotated(-angle)+position;result=first?new Rect2(point,Vector2.Zero):result.Expand(point);first=false;}
        return result;
    }
    public GArray floor_cuts(Resource source,Settings floor)
    {
        var cuts=Get(floor,"cuts",new GArray()).AsGodotArray().Duplicate();
        foreach(var value in source.Get("stairs").AsGodotArray()){var stair=value.AsGodotDictionary();if(stair_crosses(source,stair,Get(floor,"elevation",0.0).AsDouble()))cuts.Add(stair_bounds(stair));}
        return cuts;
    }
    public Resource upper_landing(Settings stair,double height)
    {
        float width=(float)Math.Max(.3,Get(stair,"width",1.0).AsDouble()),length=(float)Math.Max(.5,Get(stair,"length",4.0).AsDouble());int kind=Get(stair,"type",0).AsInt32();var end=new Vector2(0,length);var direction=Vector2.Down;
        if(kind==1){end=new Vector2(length*.5f+width*.5f,length*.5f+width*.5f);direction=Vector2.Right;}
        else if(kind==2){end=new Vector2(width*2,0);direction=Vector2.Up;}
        else if(kind==3){float angle=(float)(Math.Tau*Math.Max(.5,Get(stair,"turns",1.0).AsDouble()));end=new Vector2(Mathf.Cos(angle),Mathf.Sin(angle))*width*.75f;direction=new Vector2(-Mathf.Sin(angle),Mathf.Cos(angle));}
        float yaw=Mathf.DegToRad((float)Get(stair,"yaw",0.0).AsDouble());var position=Get(stair,"position",Vector2.Zero).AsVector2();var start=end-direction*.08f;var world=start.Rotated(-yaw)+position;var forward=direction.Rotated(-yaw);var bounds=stair_bounds(stair);float distance=float.PositiveInfinity;
        for(int axis=0;axis<2;axis++){if(Math.Abs(forward[axis])<.00001)continue;float edge=forward[axis]>0?bounds.End[axis]:bounds.Position[axis],travel=(edge-world[axis])/forward[axis];if(travel>=0)distance=Math.Min(distance,travel);}
        if(!float.IsFinite(distance))distance=.2f;float run=Math.Max(.12f,distance+.01f);var center=start+direction*run*.5f;var basis=new Basis(Vector3.Up,-Mathf.Atan2(direction.Y,direction.X)+Mathf.Pi*.5f);var mesh=new ModelGeometryOperations.Topology();mesh.Append(ModelPrimitives.Box(new Vector3(width,.1f,run)),new Transform3D(basis,new Vector3(center.X,(float)height-.05f,center.Y)));return mesh.Build();
    }
    public void post(Resource target,Vector3 point)
    {
        using var primitives=new ModelPrimitives();using var cylinder=primitives.create("Cylinder",new Settings {["radius"]=.025,["height"]=1.0,["segments"]=6});var mesh=Top(target);mesh.Append(Top(cylinder),new Transform3D(Basis.Identity,point+Vector3.Up*.5f));Assign(target,mesh);
    }
    public void beam(Resource target,Vector3 a,Vector3 b,double width)
    {
        var direction=b-a;if(direction.Length()<.0001)return;var mesh=Top(target);mesh.Append(ModelPrimitives.Box(new Vector3((float)width,(float)width,direction.Length())),new Transform3D(Basis.LookingAt(-direction.Normalized(),Vector3.Up),(a+b)*.5f));Assign(target,mesh);
    }
}
