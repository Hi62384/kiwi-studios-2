using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class BuildingGeometryOperations
{
    public Settings generate(Resource source,Settings cancellation)=>Generate(source,()=>Get(cancellation,"enabled",false).AsBool()&&GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/architecture/building_geometry.gd").Call("_cancel_requested",cancellation).AsBool());
    internal Settings Generate(Resource source,Func<bool> cancelled)
    {
        using var styles=new BuildingStyleOperations();using var layouts=new BuildingLayoutOperations();var errors=_source.validate(source);var warnings=new List<string>();if(errors.Length>0)return new Settings {["document"]=default,["errors"]=errors,["warnings"]=Array.Empty<string>()};
        var document=new KiwiModelDocument();string owner=source.Get("source_id").AsString();var root=item(document,owner,source.Get("title").AsString(),"",null,Transform3D.Identity,source,0,"building");root.Get("parameters").AsGodotDictionary()["architecture_source"]=source;var floors=source.Get("floors").AsGodotArray();double slabThickness=source.Get("slab_thickness").AsDouble();
        Settings Cancelled()=>new() {["document"]=default,["errors"]=Array.Empty<string>(),["warnings"]=warnings.ToArray(),["cancelled"]=true};
        foreach(var floorValue in floors)
        {
            if(cancelled())return Cancelled();var floor=floorValue.AsGodotDictionary();var footprint=Get(floor,"footprint",source.Get("footprint")).AsVector2Array();string parent=owner+":"+floor["id"].AsString();double elevation=Get(floor,"elevation",0.0).AsDouble();var level=item(document,parent,Get(floor,"name","Level").AsString(),owner,null,new Transform3D(Basis.Identity,Vector3.Up*(float)elevation),source,0,"level");var cuts=floor_cuts(source,floor);var slab=cached_slab(footprint,cuts,slabThickness);var slabNode=item(document,parent+":slab","Floor slab",parent,slab,new Transform3D(Basis.Identity,Vector3.Down*(float)(slabThickness*.5)),source,1,"slab");slabNode.Get("structural").AsGodotDictionary()[new StringName("structure_role")]=elevation==0?1:0;
            foreach(var roomValue in Get(floor,"rooms",new GArray()).AsGodotArray()){var room=roomValue.AsGodotDictionary();var roomNode=item(document,parent+":room:"+room["id"].AsString(),Get(room,"name","Room").AsString(),parent,null,Transform3D.Identity,source,0,"room");roomNode.Get("parameters").AsGodotDictionary()["polygon"]=Get(room,"polygon",source.Get("footprint"));}
            var seen=new HashSet<(Vector2,Vector2)>();
            foreach(var wallValue in Get(floor,"walls",new GArray()).AsGodotArray())
            {
                if(cancelled())return Cancelled();var wall=wallValue.AsGodotDictionary();var a=wall["a"].AsVector2();var b=wall["b"].AsVector2();if(seen.Contains((a,b))||seen.Contains((b,a)))continue;seen.Add((a,b));var direction=b-a;double length=direction.Length(),height=_source.wall_height(source,floor,wall);var pose=new Transform3D(new Basis(Vector3.Up,-Mathf.Atan2(direction.Y,direction.X)),new Vector3(a.X,0,a.Y));var openings=Get(wall,"openings",new GArray()).AsGodotArray();double thickness=source.Get("wall_thickness").AsDouble();var mesh=_cache.GetOrBuild("wall",new GArray {length,height,thickness,openings},()=>Wall(length,height,thickness,openings).Build());string wallId=parent+":wall:"+wall["id"].AsString();var node=item(document,wallId,Get(wall,"name","Wall").AsString(),parent,mesh,pose,source,0,"wall");wall_finishes(node,source,floor,wall);
                foreach(var trimValue in interior_trim(source,floor,wall,length,height)){var trim=trimValue.AsGodotDictionary();string kind=trim["kind"].AsString();item(document,wallId+":"+kind,char.ToUpperInvariant(kind[0])+kind[1..],wallId,trim["mesh"].As<Resource>(),Transform3D.Identity,source,3,"interior trim");}
                node.Get("structural").AsGodotDictionary()[new StringName("structure_connections")]=new Settings {["slab"]=Connection(slabNode.Get("id").AsString(),Vector3.Zero,pose.Origin+Vector3.Up*(float)(slabThickness*.5))};foreach(var openingValue in openings)opening(document,node,openingValue.AsGodotDictionary(),length,source);
                var facade=styles.facade(source,floor,wall);if(facade.Get("faces").AsGodotArray().Count>0)item(document,wallId+":facade","Facade details",wallId,facade,Transform3D.Identity,source,3,"facade");
            }
            var ceilingCuts=cuts.Duplicate();double ceilingTop=Get(floor,"height",3.0).AsDouble();foreach(var stairValue in source.Get("stairs").AsGodotArray()){var stair=stairValue.AsGodotDictionary();if(stair_crosses(source,stair,elevation+ceilingTop))ceilingCuts.Add(stair_bounds(stair));}
            foreach(var otherValue in floors){var other=otherValue.AsGodotDictionary();if(Mathf.IsEqualApprox(other["elevation"].AsDouble(),elevation+ceilingTop)){ceilingTop-=slabThickness;break;}}
            item(document,parent+":ceiling","Ceiling",level.Get("id").AsString(),cached_slab(footprint,ceilingCuts,.01),new Transform3D(Basis.Identity,Vector3.Up*(float)(ceilingTop-.005)),source,6,"ceiling");
        }
        warnings.AddRange(build_stairs(document,source));if(cancelled())return Cancelled();var last=floors[^1].AsGodotDictionary();double top=Get(last,"elevation",0.0).AsDouble()+Get(last,"height",3.0).AsDouble();var roofSource=source;if(last.ContainsKey("footprint")){roofSource=_source.copy(source);roofSource.Set("footprint",last["footprint"]);}var roof=Roof(roofSource,warnings);if(roof!=null)item(document,owner+":roof","Roof",owner,roof.Build(),new Transform3D(Basis.Identity,Vector3.Up*(float)top),source,2,"roof");build_supports(document,source);
        var navigation=layouts.connectivity(source);root.Get("parameters").AsGodotDictionary()["architecture_navigation"]=navigation;warnings.AddRange(navigation["warnings"].AsStringArray());using var documents=new ModelDocumentOperations();return new Settings {["document"]=document,["errors"]=documents.validate(document),["warnings"]=warnings.ToArray()};
    }
}
