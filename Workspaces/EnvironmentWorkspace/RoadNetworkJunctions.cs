using Godot;
using Settings=Godot.Collections.Dictionary;

public partial class RoadNetworkOperations
{
    public Settings junction_plan(Settings graphData)
    {
        var edges=new Settings();var junctions=new Settings();
        foreach(var value in graphData["edges"].AsGodotArray())
        {var edge=value.AsGodotDictionary();edges[edge["id"]]=edge;edge["_cross_sections"]=new Settings();}
        var section=new RoadSectionOperations();
        foreach(var pair in graphData["adjacency"].AsGodotDictionary())
        {
            var adjacent=pair.Value.AsGodotArray();if(adjacent.Count<2)continue;
            if(adjacent.Count!=2){junctions[pair.Key]=true;continue;}
            var a=edges[adjacent[0]].AsGodotDictionary();var b=edges[adjacent[1]].AsGodotDictionary();
            var roads=new[]{a,b};var directions=new Vector3[2];
            for(int i=0;i<2;i++)
            {var points=roads[i]["points"].AsVector3Array();var direction=roads[i]["from"].AsString()==pair.Key.AsString()?points[1]-points[0]:points[^2]-points[^1];direction.Y=0;directions[i]=direction.Normalized();}
            if(directions[0].Dot(directions[1])>-.95||!Mathf.IsEqualApprox(a["width"].AsDouble(),b["width"].AsDouble())||!Mathf.IsEqualApprox(section.outer_half(a),section.outer_half(b)))
            {junctions[pair.Key]=true;continue;}
            for(int i=0;i<2;i++)
            {
                var edge=roads[i];bool start=edge["from"].AsString()==pair.Key.AsString();var away=(directions[i]-directions[1-i]).Normalized();var tangent=start?away:-away;
                var side=new Vector3(-tangent.Z,0,tangent.X);var localSide=new Vector3(-directions[i].Z,0,directions[i].X);
                side/=(float)System.Math.Max(.5,System.Math.Abs(side.Dot(localSide)));edge["_cross_sections"].AsGodotDictionary()[start?"start":"end"]=side;
            }
        }
        return junctions;
    }
}
