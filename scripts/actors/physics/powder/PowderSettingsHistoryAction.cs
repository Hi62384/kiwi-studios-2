using Godot;
using GArray=Godot.Collections.Array;
public partial class PowderSettingsHistoryAction:RefCounted
{
    private readonly WeakRef? _model;private readonly GArray? _before,_after;private readonly PowderSettingsOperations _operations=new();
    public PowderSettingsHistoryAction(){}public PowderSettingsHistoryAction(RefCounted model,GArray before,GArray after){_model=GodotObject.WeakRef(model);_before=before;_after=after;}
    private void Restore(GArray? entries){if(_model!=null&&entries!=null)_operations.assign(_model,entries);}
    public void restore_before()=>Restore(_before);public void restore_after()=>Restore(_after);
}
