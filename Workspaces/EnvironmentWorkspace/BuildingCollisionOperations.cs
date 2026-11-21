using Godot;
using System.Collections.Generic;
using GArray=Godot.Collections.Array;

public partial class BuildingCollisionOperations : RefCounted
{
    public int root(int[] parents,int index)
    {while(parents[index]!=index)index=parents[index];return index;}
    public GArray parts(Resource mesh)
    {
        var snapshot=new ModelMeshOperations.Snapshot(mesh);var parents=new int[snapshot.Vertices.Length];for(int i=0;i<parents.Length;i++)parents[i]=i;
        int Find(int index){int result=index;while(parents[result]!=result)result=parents[result];while(parents[index]!=index){int next=parents[index];parents[index]=result;index=next;}return result;}
        foreach(var face in snapshot.Faces){if(face.Length==0)continue;for(int index=1;index<face.Length;index++){int a=Find(face[0]),b=Find(face[index]);if(a!=b)parents[b]=a;}}
        var groups=new Dictionary<int,List<Vector3>>();for(int index=0;index<parents.Length;index++){int group=Find(index);if(!groups.TryGetValue(group,out var vertices)){vertices=new List<Vector3>();groups[group]=vertices;}vertices.Add(snapshot.Vertices[index]);}var result=new GArray();foreach(var vertices in groups.Values)if(vertices.Count>=4)result.Add(vertices.ToArray());return result;
    }
}
