using Godot;

[GlobalClass]
public partial class AudioWorkToken : RefCounted
{
    private readonly object _gate=new();
    public bool cancelled {get{lock(_gate)return _cancelled;}set{lock(_gate)_cancelled=value;}}
    public double progress {get{lock(_gate)return _progress;}set{lock(_gate)_progress=value;}}
    public string description {get{lock(_gate)return _description;}set{lock(_gate)_description=value;}}
    private bool _cancelled;
    private double _progress;
    private string _description="";
    public void cancel(){lock(_gate)_cancelled=true;}
    public bool is_cancelled(){lock(_gate)return _cancelled;}
    public void update(double value) => update(value, "");
    public void update(double value,string message){lock(_gate){_progress=System.Math.Clamp(value,0,1);_description=message;}}
    public Godot.Collections.Dictionary status(){lock(_gate)return new Godot.Collections.Dictionary {["progress"]=_progress,["description"]=_description};}
}
