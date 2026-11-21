using Godot;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class WorldPlacementOperations
{
    public string hierarchy_plan(Resource document,string root,Settings removed,Settings replacement,GArray parts,Settings poses)
    {
        var parents=new Settings();
        foreach(var value in document.Get("components").AsGodotArray())
        {
            var item=value.As<Resource>();var id=item.Get("id");if(removed.ContainsKey(id))continue;
            var parent=item.Get("parent_id");
            if(removed.ContainsKey(parent)&&!replacement.ContainsKey(parent))
            {
                // This surviving independent object will be reparented at commit.
                // Validate that intended hierarchy, retaining its current world pose.
                poses[id]=document.Call("world_transform",item);parents[id]=root;
            }
            else parents[id]=parent;
        }
        foreach(var value in parts){var item=value.As<Resource>();parents[item.Get("id")]=item.Get("parent_id");}
        foreach(var id in parents.Keys)
        {
            string cursor=id.AsString();var visited=new System.Collections.Generic.HashSet<string>();
            while(cursor.Length>0)
            {
                if(!visited.Add(cursor)||!parents.TryGetValue(cursor,out var parent))
                    return "Regeneration would create an invalid parent hierarchy. Reparent the affected component before regenerating.";
                cursor=parent.AsString();
            }
        }
        return "";
    }
}
