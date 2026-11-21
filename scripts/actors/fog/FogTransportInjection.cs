using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
public partial class FogTransportOperations
{
    internal void InjectVaried(Settings state,List<int> cells,List<float> weights,double mass,Vector3[] velocities)
    {
        if(cells.Count!=weights.Count||cells.Count!=velocities.Length||mass<=0||!double.IsFinite(mass))return;var rho=state["fog_density"].AsFloat32Array();var velocity=state["fog_velocity"].AsVector3Array();var solid=state["fog_solid"].AsByteArray();double sum=0;for(int k=0;k<cells.Count;k++){int i=cells[k];if(i>=0&&i<rho.Length&&solid[i]==0)sum+=Math.Max(0,weights[k]);}if(sum<=0)return;var size=state["fog_size"].AsVector3();double volume=(double)size.X*size.Y*size.Z/rho.Length;for(int k=0;k<cells.Count;k++){int i=cells[k];if(i<0||i>=rho.Length||solid[i]!=0)continue;float added=(float)(mass*Math.Max(0,weights[k])/sum/volume),next=rho[i]+added;velocity[i]=(velocity[i]*rho[i]+velocities[k]*added)/Math.Max(.000001f,next);rho[i]=next;}state["fog_density"]=rho;state["fog_velocity"]=velocity;state["fog_emitted"]=Number(state,"fog_emitted")+mass;
    }
}
