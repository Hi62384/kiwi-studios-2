using Godot;
using System.Linq;
using GArray=Godot.Collections.Array;
public partial class ActorTimelineHistoryAction:RefCounted
{
    private readonly WeakRef? _owner;private readonly string _forward="",_backward="";private readonly GArray? _doArgs,_undoArgs;
    public ActorTimelineHistoryAction(){}
    public ActorTimelineHistoryAction(RefCounted owner,string forward,GArray doArgs,string backward,GArray undoArgs){_owner=GodotObject.WeakRef(owner);_forward=forward;_backward=backward;_doArgs=doArgs;_undoArgs=undoArgs;}
    private void Apply(string method,GArray? arguments){if(_owner==null||arguments==null)return;using var reference=_owner.GetRef();if(reference.AsGodotObject() is RefCounted owner&&GodotObject.IsInstanceValid(owner))owner.Call(method,arguments.ToArray());}
    public void perform_do()=>Apply(_forward,_doArgs);
    public void perform_undo()=>Apply(_backward,_undoArgs);
}
