using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class BuildingLayoutOperations
{
    public Settings generate(Resource authored,int roomCount,double corridorWidth,string[] types,float[] weights)
    {
        var source=_source.copy(authored);var errors=new List<string>(_source.validate(source));if(errors.Count>0)return new Settings {["source"]=default,["errors"]=errors.ToArray()};if(roomCount<2||roomCount>12)errors.Add("Choose between two and twelve rooms per level.");if(corridorWidth<.9)errors.Add("The hallway must be at least 0.9 m wide.");
        // Invalid counts cannot be used for allocation or division while collecting plan errors.
        if(roomCount<2||roomCount>12||!double.IsFinite(corridorWidth))return new Settings {["source"]=default,["errors"]=errors.Count>0?errors.ToArray():new[]{"The hallway width must be finite."}};
        foreach(var floorValue in source.Get("floors").AsGodotArray())
        {
            var floor=floorValue.AsGodotDictionary();var footprint=Get(floor,"footprint",source.Get("footprint")).AsVector2Array();var bounds=new Rect2(footprint[0],Vector2.Zero);foreach(var point in footprint)bounds=bounds.Expand(point);if(footprint.Length!=4||!rectangle(footprint,bounds)){errors.Add("Automatic layouts support rectangular, axis-aligned levels. Edit this footprint manually.");continue;}if(bounds.Size.X<corridorWidth+3||bounds.Size.Y<3){errors.Add("This footprint is too small for two room wings and a usable hallway.");continue;}
            var walls=new GArray();foreach(var wallValue in floor["walls"].AsGodotArray())
            {
                var wall=wallValue.AsGodotDictionary();var a=wall["a"].AsVector2();var b=wall["b"].AsVector2();bool boundary=(Mathf.IsEqualApprox(a.X,b.X)&&(Mathf.IsEqualApprox(a.X,bounds.Position.X)||Mathf.IsEqualApprox(a.X,bounds.End.X)))||(Mathf.IsEqualApprox(a.Y,b.Y)&&(Mathf.IsEqualApprox(a.Y,bounds.Position.Y)||Mathf.IsEqualApprox(a.Y,bounds.End.Y)));if(!boundary)continue;var openings=new GArray();foreach(var openingValue in Get(wall,"openings",new GArray()).AsGodotArray())if(Get(openingValue.AsGodotDictionary(),"type", "").AsString()!="window")openings.Add(openingValue);wall["openings"]=openings;walls.Add(wall);
            }
            float center=bounds.GetCenter().X,left=center-(float)corridorWidth*.5f,right=center+(float)corridorWidth*.5f;var rooms=new GArray {new Settings {["id"]="hall",["name"]="Hallway",["type"]="corridor",["polygon"]=polygon(new Rect2(left,bounds.Position.Y,(float)corridorWidth,bounds.Size.Y))}};
            for(int side=0;side<2;side++)
            {
                int count=side==0?(roomCount+1)/2:roomCount/2;using var rng=new RandomNumberGenerator();using var seedValues=new GArray {source.Get("seed"),floor["id"].AsString(),side};rng.Seed=unchecked((uint)GD.Hash(seedValues));var sizes=new double[count];double total=0;for(int index=0;index<count;index++){int ordinal=index*2+side;double weight=ordinal<weights.Length?weights[ordinal]:1,size=Math.Max(.1,weight)*rng.RandfRange(.92f,1.08f);sizes[index]=size;total+=size;}
                double cursor=bounds.Position.Y;float x=side==0?left:right;for(int index=0;index<count;index++)
                {
                    int ordinal=index*2+side;double end=index==count-1?bounds.End.Y:cursor+bounds.Size.Y*sizes[index]/total;if(end-cursor<1.5){errors.Add("Some rooms are narrower than 1.5 m. Reduce the room count or enlarge the footprint.");continue;}var area=new Rect2(side==0?bounds.Position.X:right,(float)cursor,side==0?left-bounds.Position.X:bounds.End.X-right,(float)(end-cursor));string kind=ordinal<types.Length?types[ordinal]:new[]{"Living area","Kitchen","Bedroom","Bedroom","Bathroom"}[ordinal%5];rooms.Add(new Settings {["id"]="layout:room"+ordinal,["name"]=kind,["type"]=kind.ToSnakeCase(),["polygon"]=polygon(area)});walls.Add(new Settings {["id"]="layout:doorwall"+ordinal,["a"]=new Vector2(x,(float)cursor),["b"]=new Vector2(x,(float)end),["height_mode"]="level",["openings"]=new GArray {new Settings {["id"]="layout:door"+ordinal,["type"]="door",["t"]=.5,["width"]=.85,["height"]=2.05,["bottom"]=0.0,["angle"]=0.0}}});if(index>0)walls.Add(new Settings {["id"]="layout:partition"+ordinal,["a"]=new Vector2(area.Position.X,(float)cursor),["b"]=new Vector2(area.End.X,(float)cursor),["height_mode"]="level",["openings"]=new GArray()});cursor=end;
                }
            }
            foreach(var roomValue in rooms)
            {
                var room=roomValue.AsGodotDictionary();if(Get(room,"type", "").AsString()=="corridor")continue;var roomPolygon=room["polygon"].AsVector2Array();var roomBounds=new Rect2(roomPolygon[0],Vector2.Zero);foreach(var point in roomPolygon)roomBounds=roomBounds.Expand(point);float sideX=roomBounds.Position.X<left?bounds.Position.X:bounds.End.X;var midpoint=new Vector2(sideX,roomBounds.GetCenter().Y);
                foreach(var wallValue in walls){var wall=wallValue.AsGodotDictionary();var a=wall["a"].AsVector2();var b=wall["b"].AsVector2();if(!Mathf.IsEqualApprox(a.X,sideX)||!Mathf.IsEqualApprox(b.X,sideX)||midpoint.Y<Math.Min(a.Y,b.Y)||midpoint.Y>Math.Max(a.Y,b.Y))continue;wall["openings"].AsGodotArray().Add(new Settings {["id"]="layout:window:"+room["id"].AsString(),["type"]="window",["t"]=(midpoint-a).Dot(b-a)/a.DistanceSquaredTo(b),["width"]=Math.Min(1.4,roomBounds.Size.Y*.5),["height"]=1.2,["bottom"]=1.0});break;}
            }
            floor["rooms"]=rooms;floor["walls"]=walls;
        }
        if(errors.Count==0)errors.AddRange(_source.validate(source));return new Settings {["source"]=errors.Count==0?Variant.From(source):default,["errors"]=errors.ToArray()};
    }
}
