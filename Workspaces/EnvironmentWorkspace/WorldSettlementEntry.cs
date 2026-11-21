using Godot;
using System;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class WorldSettlementOperations
{
    public Resource? entry(Resource authored,Settings plot,Settings road,string worldId)
    {
        var pose=plot["pose"].AsTransform3D();var door=pose*new Vector3(0,0,(float)(-plot["depth"].AsDouble()*.5));var access=road_access(door,road);if(access.Count==0)return null;
        var origin=access["position"].AsVector3();var difference=door-origin;double rise=difference.Y;difference.Y=0;double run=difference.Length();if(run<.1||rise<-.05||rise>2)return null;
        int steps=Math.Clamp((int)Math.Ceiling(Math.Max(0,rise)/.18),1,12);double footing=.3;var basis=Basis.LookingAt(-difference.Normalized(),Vector3.Up);var topology=new ModelGeometryOperations.Topology();
        for(int step=0;step<steps;step++){double top=Math.Max(.02,rise*(step+1)/steps);topology.Append(ModelPrimitives.Box(new Vector3(1.2f,(float)(top+footing),(float)(run/steps+.005))),new Transform3D(Basis.Identity,new Vector3(0,(float)((top-footing)*.5),(float)(run*(step+.5)/steps))));}
        var item=new KiwiModelComponent();string id=authored.Get("source_id").AsString()+":entry";var mesh=topology.Build();item.Set("id",id);item.Set("title","Entrance steps");item.Set("parent_id",authored.Get("source_id"));item.Set("mesh",mesh);var transform=pose.AffineInverse()*new Transform3D(basis,origin);item.Set("transform",transform);var materials=item.Get("surface_materials").AsGodotArray();materials.Add(authored.Get("materials").AsGodotArray()[0]);item.Set("parameters",new Settings {["world_generated"]=true,["world_owner"]=worldId,["world_key"]=id.StartsWith(worldId,StringComparison.Ordinal)?id[worldId.Length..]:id,["world_pose"]=transform,["world_mesh_key"]=unchecked((uint)GD.Hash(new GArray {mesh.Get("vertices"),mesh.Get("faces")})),["world_plot"]=plot["id"],["architecture_type"]="entry stairs",["world_materials"]=materials.Duplicate(),["world_structure"]=new Settings()});return item;
    }
}
