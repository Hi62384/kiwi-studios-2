using Godot;
using System;
using System.Collections.Generic;
using System.Linq;

public partial class ModelSelection : RefCounted
{
    public int[] expand(Resource mesh,string mode,int[] selected,string operation)
    {
        var faces=mesh.Get("faces").AsGodotArray().Select(value=>value.AsInt32Array()).ToArray();var edges=ModelGeometryOperations.Edges(faces);int count=mode=="Vertex"?mesh.Get("vertices").AsVector3Array().Length:mode=="Edge"?edges.Count:faces.Length;
        var graph=Enumerable.Range(0,count).Select(_=>new HashSet<int>()).ToArray();
        void Pair(int a,int b){if(a>=0&&a<count&&b>=0&&b<count)graph[a].Add(b);}
        if(mode=="Vertex")foreach(var edge in edges){Pair(edge.A,edge.B);Pair(edge.B,edge.A);}
        else if(mode=="Face"){foreach(var edge in edges)foreach(int a in edge.Faces)foreach(int b in edge.Faces)if(a!=b)Pair(a,b);}
        else
        {
            var incident=new Dictionary<int,List<int>>();for(int i=0;i<edges.Count;i++)foreach(int vertex in new[]{edges[i].A,edges[i].B}){if(!incident.TryGetValue(vertex,out var list)){list=new();incident[vertex]=list;}list.Add(i);}
            foreach(var list in incident.Values)foreach(int a in list)foreach(int b in list)if(a!=b)Pair(a,b);
        }
        var used=new Dictionary<int,bool>();foreach(int index in selected)if(index>=0&&index<count)used[index]=true;
        if(operation=="Shrink selection")
        {var original=new HashSet<int>(used.Keys);foreach(int index in selected)if(index>=0&&index<count&&graph[index].Any(neighbor=>!original.Contains(neighbor)))used.Remove(index);}
        else if(operation=="Select connected")
        {var queue=used.Keys.ToList();for(int at=0;at<queue.Count;at++)foreach(int neighbor in graph[queue[at]])if(used.TryAdd(neighbor,true))queue.Add(neighbor);}
        else foreach(int index in selected)if(index>=0&&index<count)foreach(int neighbor in graph[index])used[neighbor]=true;
        return used.Keys.ToArray();
    }
}
