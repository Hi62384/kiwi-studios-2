using Godot;
using System;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;
using Topology=ModelGeometryOperations.Topology;

public partial class BuildingGeometryOperations
{
    private static Settings Connection(string target,Vector3 pivot,Vector3 targetPivot,int kind=0)=>StructureConnectionOperations.Create(target,pivot,targetPivot,kind);
    public void connect_support(Resource document,Resource part,Resource target,Vector3 point,string key)
    {
        var structure=part.Get("structural").AsGodotDictionary();var name=new StringName("structure_connections");if(!structure.ContainsKey(name))structure[name]=new Settings();var lookup=ModelDocumentOperations.Lookup(document);structure[name].AsGodotDictionary()[key]=Connection(target.Get("id").AsString(),ModelDocumentOperations.WorldTransform(lookup,part).AffineInverse()*point,ModelDocumentOperations.WorldTransform(lookup,target).AffineInverse()*point);
    }
    public void build_supports(Resource document,Resource source)
    {
        var floors=source.Get("floors").AsGodotArray();string owner=source.Get("source_id").AsString();double foundationDepth=source.Get("foundation_depth").AsDouble(),slabThickness=source.Get("slab_thickness").AsDouble();var lookup=ModelDocumentOperations.Lookup(document);
        if(foundationDepth>0)
        {
            var first=floors[0].AsGodotDictionary();double elevation=Get(first,"elevation",0.0).AsDouble();var foundation=item(document,owner+":foundation","Foundation",owner,ConvexSlab(Get(first,"footprint",source.Get("footprint")).AsVector2Array(),foundationDepth).Build(),new Transform3D(Basis.Identity,Vector3.Up*(float)(elevation-slabThickness-foundationDepth*.5)),source,0,"foundation");foundation.Get("structural").AsGodotDictionary()[new StringName("structure_role")]=1;
            if(lookup.TryGetValue(owner+":"+first["id"].AsString()+":slab",out var floorSlab))connect_support(document,floorSlab,foundation,new Vector3(0,(float)(elevation-slabThickness),0),"foundation");
        }
        for(int index=0;index<floors.Count;index++)
        {
            var floor=floors[index].AsGodotDictionary();string targetId=index==floors.Count-1?owner+":roof":owner+":"+floors[index+1].AsGodotDictionary()["id"].AsString()+":slab";if(!lookup.TryGetValue(targetId,out var target))continue;
            foreach(var value in floor["walls"].AsGodotArray())
            {var wall=value.AsGodotDictionary();if(!lookup.TryGetValue(owner+":"+floor["id"].AsString()+":wall:"+wall["id"].AsString(),out var part))continue;var mesh=part.Get("mesh").As<Resource>();if(mesh==null)continue;using var meshes=new ModelMeshOperations();var bounds=meshes.bounds(mesh);var point=ModelDocumentOperations.WorldTransform(lookup,part)*new Vector3(bounds.GetCenter().X,bounds.End.Y,0);connect_support(document,target,part,point,wall["id"].AsString());}
        }
    }
    public void opening(Resource document,Resource wall,Settings opening,double length,Resource source)
    {
        float width=(float)Get(opening,"width",1.0).AsDouble(),height=(float)Get(opening,"height",2.0).AsDouble(),bottom=(float)Get(opening,"bottom",0.0).AsDouble(),center=(float)(Get(opening,"t",.5).AsDouble()*length),thickness=(float)source.Get("wall_thickness").AsDouble(),trim=.07f;string id=wall.Get("parent_id").AsString()+":opening:"+Get(opening,"id","opening").AsString(),kind=Get(opening,"type","door").AsString(),wallId=wall.Get("id").AsString();if(kind=="arch")return;
        var frame=new Topology();foreach(var part in new[]{(new Vector3(trim,height,thickness+.06f),new Vector3(center-width*.5f+trim*.5f,bottom+height*.5f,0)),(new Vector3(trim,height,thickness+.06f),new Vector3(center+width*.5f-trim*.5f,bottom+height*.5f,0)),(new Vector3(width,trim,thickness+.06f),new Vector3(center,bottom+height-trim*.5f,0))})frame.Append(ModelPrimitives.Box(part.Item1),new Transform3D(Basis.Identity,part.Item2));
        // Include the sill before publishing the frame so derived mesh signatures stay valid.
        if(kind=="window")frame.Append(ModelPrimitives.Box(new Vector3(width,.07f,thickness+.06f)),new Transform3D(Basis.Identity,new Vector3(center,bottom+.035f,0)));
        item(document,id+":frame",kind=="window"?"Window frame":"Door frame",wallId,frame.Build(),Transform3D.Identity,source,3,"trim");
        if(kind=="window"){item(document,id+":glass","Glass",wallId,ModelPrimitives.Box(new Vector3(width-trim*2,height-trim*2,.015f)).Build(),new Transform3D(Basis.Identity,new Vector3(center,bottom+height*.5f,0)),source,4,"window");return;}
        var leaf=ModelPrimitives.Box(new Vector3(width-trim*2,height-trim,.05f));for(int index=0;index<leaf.Points.Count;index++)leaf.Points[index]+=new Vector3(width*.5f,(height-trim)*.5f,0);var hinge=new Vector3(center-width*.5f,bottom,0);var pose=new Transform3D(new Basis(Vector3.Up,Mathf.DegToRad((float)Get(opening,"angle",0.0).AsDouble())),hinge);bool slider=kind=="slider";if(slider)pose=new Transform3D(Basis.Identity,hinge+Vector3.Right*(float)Get(opening,"slide",0.0).AsDouble()*width);var door=item(document,id+":leaf",slider?"Sliding door":"Door",wallId,leaf.Build(),pose,source,3,"door");var connection=Connection(wallId,Vector3.Zero,hinge,slider?2:1);if(slider){connection["orientation"]=new Vector3(0,0,-90);connection["limit"]=width;}door.Get("structural").AsGodotDictionary()[new StringName("structure_connections")]=new Settings {["hinge"]=connection};
    }
}
