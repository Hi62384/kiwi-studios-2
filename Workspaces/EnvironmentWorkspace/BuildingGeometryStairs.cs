using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;
using Topology=ModelGeometryOperations.Topology;

public partial class BuildingGeometryOperations
{
    private static void Post(Topology target,Vector3 point)
    {using var primitives=new ModelPrimitives();using var cylinder=primitives.create("Cylinder",new Settings {["radius"]=.025,["height"]=1.0,["segments"]=6});target.Append(Top(cylinder),new Transform3D(Basis.Identity,point+Vector3.Up*.5f));}
    private static void Beam(Topology target,Vector3 a,Vector3 b,float width)
    {var direction=b-a;if(direction.Length()<.0001)return;target.Append(ModelPrimitives.Box(new Vector3(width,width,direction.Length())),new Transform3D(Basis.LookingAt(-direction.Normalized(),Vector3.Up),(a+b)*.5f));}
    public string[] build_stairs(Resource document,Resource source)
    {
        var warnings=new List<string>();var floors=source.Get("floors").AsGodotArray();string owner=source.Get("source_id").AsString();
        foreach(var value in source.Get("stairs").AsGodotArray())
        {
            var stair=value.AsGodotDictionary();Settings? from=null,to=null;foreach(var floorValue in floors){var floor=floorValue.AsGodotDictionary();string floorId=floor["id"].AsString();if(floorId==Get(stair,"from", "").AsString())from=floor;if(floorId==Get(stair,"to", "").AsString())to=floor;}
            if(from==null||to==null){warnings.Add("A staircase references a missing level.");continue;}
            float height=(float)(to["elevation"].AsDouble()-from["elevation"].AsDouble()),width=(float)Math.Max(.3,Get(stair,"width",1.0).AsDouble()),length=(float)Math.Max(.5,Get(stair,"length",4.0).AsDouble());int steps=Math.Clamp(Get(stair,"steps",Mathf.CeilToInt(height/.18f)).AsInt32(),2,80),kind=Math.Clamp(Get(stair,"type",0).AsInt32(),0,3);
            if(height<=0){warnings.Add("A staircase must rise to a higher level.");continue;}
            if(height/length>.8&&kind!=3)warnings.Add("This staircase is steep. Increase its run for easier access.");
            if(height/steps>.22)warnings.Add("Stair risers exceed 0.22 m; add steps for easier access.");
            if(width<.8)warnings.Add("This staircase is narrower than 0.8 m.");
            if(kind==3&&height/Math.Max(.5,Get(stair,"turns",1.0).AsDouble())<2.1)warnings.Add("Spiral stair headroom is below 2.1 m per turn; reduce turns or increase the rise.");
            if(kind!=3&&length/steps<.22)warnings.Add("Stair treads are shallower than 0.22 m; increase the run or reduce steps.");
            var position=Get(stair,"position",Vector2.Zero).AsVector2();var pose=new Transform3D(new Basis(Vector3.Up,Mathf.DegToRad((float)Get(stair,"yaw",0.0).AsDouble())),new Vector3(position.X,(float)from["elevation"].AsDouble(),position.Y));string id=owner+":stairs:"+Get(stair,"id","stairs").AsString();var parent=item(document,id,"Staircase",owner,null,pose,source,3,"stairs");var mesh=new Topology();var rails=new Topology();var landings=new Topology();
            if(kind==3)
            {
                float radius=width*1.3f,inner=width*.2f,turns=(float)Math.Max(.5,Get(stair,"turns",1.0).AsDouble());var previous=Vector3.Zero;
                for(int step=0;step<steps;step++)
                {
                    float a=Mathf.Tau*turns*step/steps,b=Mathf.Tau*turns*(step+1)/steps,y=height*(step+1)/steps;var profile=new[]{new Vector2(Mathf.Cos(a),Mathf.Sin(a))*inner,new Vector2(Mathf.Cos(a),Mathf.Sin(a))*radius,new Vector2(Mathf.Cos(b),Mathf.Sin(b))*radius,new Vector2(Mathf.Cos(b),Mathf.Sin(b))*inner};mesh.Append(ModelPrimitives.Prism(profile,.1,0,1),new Transform3D(Basis.Identity,Vector3.Up*(y-.05f)));var point=new Vector3(Mathf.Cos(b)*radius,y,Mathf.Sin(b)*radius);Post(rails,point);if(step>0)Beam(rails,previous+Vector3.Up,point+Vector3.Up,.05f);previous=point;
                }
                using var primitives=new ModelPrimitives();using var cylinder=primitives.create("Cylinder",new Settings {["radius"]=.12,["height"]=height,["segments"]=12});mesh.Append(Top(cylinder),new Transform3D(Basis.Identity,Vector3.Up*height*.5f));
            }
            else
            {
                var flights=new List<(Vector2 A,Vector2 B,float Low,float High)>();
                if(kind==0)flights.Add((Vector2.Zero,new Vector2(0,length),0,height));
                else if(kind==1)
                {flights.Add((Vector2.Zero,new Vector2(0,length*.5f),0,height*.5f));flights.Add((new Vector2(width*.5f,length*.5f+width*.5f),new Vector2(length*.5f+width*.5f,length*.5f+width*.5f),height*.5f,height));landings.Append(ModelPrimitives.Box(new Vector3(width,height*.5f,width)),new Transform3D(Basis.Identity,new Vector3(0,height*.25f,length*.5f+width*.5f)));}
                else
                {flights.Add((Vector2.Zero,new Vector2(0,length*.5f),0,height*.5f));flights.Add((new Vector2(width*2,length*.5f),new Vector2(width*2,0),height*.5f,height));landings.Append(ModelPrimitives.Box(new Vector3(width*3,height*.5f,width)),new Transform3D(Basis.Identity,new Vector3(width,height*.25f,length*.5f+width*.5f)));}
                foreach(var flight in flights)
                {
                    var delta=flight.B-flight.A;int count=Math.Max(2,Mathf.CeilToInt((float)steps/flights.Count));var direction=delta.Normalized();var basis=new Basis(Vector3.Up,-Mathf.Atan2(direction.Y,direction.X)+Mathf.Pi*.5f);Vector3[] previous=Array.Empty<Vector3>();
                    for(int step=0;step<count;step++)
                    {
                        float t=(step+.5f)/count,y=Mathf.Lerp(flight.Low,flight.High,(float)(step+1)/count);var p=flight.A.Lerp(flight.B,t);mesh.Append(ModelPrimitives.Box(new Vector3(width,y,delta.Length()/count+.002f)),new Transform3D(basis,new Vector3(p.X,y*.5f,p.Y)));var current=new Vector3[2];int sideIndex=0;
                        foreach(float sign in new[]{-1f,1f}){var point=new Vector3(p.X,y,p.Y)+basis.X*width*.48f*sign;current[sideIndex]=point;Post(rails,point);if(previous.Length>0)Beam(rails,previous[sideIndex]+Vector3.Up,point+Vector3.Up,.05f);sideIndex++;}previous=current;
                    }
                }
            }
            using(var upper=upper_landing(stair,height))landings.Append(Top(upper),Transform3D.Identity);
            var treads=item(document,id+":treads","Steps",parent.Get("id").AsString(),mesh.Build(),Transform3D.Identity,source,3,"stair treads");var lookup=ModelDocumentOperations.Lookup(document);var origin=ModelDocumentOperations.WorldTransform(lookup,treads).Origin;if(lookup.TryGetValue(owner+":"+from["id"].AsString()+":slab",out var floorSlab))connect_support(document,treads,floorSlab,origin,"base");
            if(landings.Faces.Count>0)
            {var landing=item(document,id+":landings","Landing",parent.Get("id").AsString(),landings.Build(),Transform3D.Identity,source,1,"landing");connect_support(document,landing,treads,origin,"steps");if(lookup.TryGetValue(owner+":"+to["id"].AsString()+":slab",out var upperSlab))connect_support(document,landing,upperSlab,pose*new Vector3(0,height,0),"upper floor");}
            if(Get(stair,"railings",true).AsBool()){var railing=item(document,id+":rails","Railings",parent.Get("id").AsString(),rails.Build(),Transform3D.Identity,source,3,"railing");connect_support(document,railing,treads,origin,"steps");}
        }
        return warnings.ToArray();
    }
}
