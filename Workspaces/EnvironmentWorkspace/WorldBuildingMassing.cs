using Godot;
using System.Collections.Generic;
using Topology=ModelGeometryOperations.Topology;

public partial class WorldBuildingMassing : RefCounted
{
    public Resource mesh(Resource source)
    {
        var result=new Topology();var floors=source.Get("floors").AsGodotArray();var footprint=source.Get("footprint").AsVector2Array();foreach(var value in floors){var floor=value.AsGodotDictionary();var polygon=floor.TryGetValue("footprint",out var outline)?outline.AsVector2Array():footprint;double height=floor.TryGetValue("height",out var levelHeight)?levelHeight.AsDouble():3,elevation=floor.TryGetValue("elevation",out var bottom)?bottom.AsDouble():0;result.Append(ModelPrimitives.Prism(polygon,height,0,1),new Transform3D(Basis.Identity,Vector3.Up*(float)(elevation+height*.5)));}double depth=source.Get("foundation_depth").AsDouble();if(depth>0)result.Append(ModelPrimitives.Prism(footprint,depth,0,1),new Transform3D(Basis.Identity,Vector3.Down*(float)depth*.5f));var roof=BuildingGeometryOperations.Roof(source,new List<string>());if(roof!=null&&floors.Count>0){var last=floors[^1].AsGodotDictionary();double height=last.TryGetValue("height",out var levelHeight)?levelHeight.AsDouble():3;result.Append(roof,new Transform3D(Basis.Identity,Vector3.Up*(float)(last["elevation"].AsDouble()+height)),2);}return result.Build();
    }
    public long stamp(Resource? mesh,int version)
    {if(mesh==null)return 0;var values=new Godot.Collections.Array {mesh.Get("vertices"),mesh.Get("faces")};if(version>=2){values.Add(mesh.Get("uv"));values.Add(mesh.Get("materials"));}return unchecked((uint)GD.Hash(values));}
}
