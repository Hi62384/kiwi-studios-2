using Godot;
using Settings=Godot.Collections.Dictionary;

/// <summary>Shared serialized connection schema used by authored and generated structures.</summary>
public partial class StructureConnectionOperations : RefCounted
{
    public Settings connection(string target,Vector3 pivot,Vector3 targetPivot,int kind)=>Create(target,pivot,targetPivot,kind);
    internal static Settings Create(string target,Vector3 pivot,Vector3 targetPivot,int kind=0)=>new()
    {
        ["target"]=target,["type"]=kind,["enabled"]=true,["pivot"]=pivot,["target_pivot"]=targetPivot,["orientation"]=Vector3.Zero,
        ["strength"]=1.0,["stiffness"]=100000.0,["angular_stiffness"]=100000.0,["breaking_force"]=10000.0,["breaking_torque"]=10000.0,
        ["tension"]=1.0,["compression"]=1.0,["shear"]=1.0,["bending"]=1.0,["damping"]=.15,["damage_rate"]=.05,["initial_damage"]=0.0,
        ["break_at"]=-1.0,["prevent_failure"]=false,["length"]=0.0,["limit"]=1.0,["tension_only"]=true,["material_strength"]=false,["exclude_collision"]=true
    };
}
