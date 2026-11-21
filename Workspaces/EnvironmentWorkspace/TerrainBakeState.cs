using Godot;
public partial class TerrainBakeState : RefCounted
{
    public bool cancelled {get;set;}
    public double progress {get;set;}
    public string error {get;set;}="";
    public void cancel()=>cancelled=true;
}
