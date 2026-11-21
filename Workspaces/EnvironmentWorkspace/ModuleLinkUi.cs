using Godot;
using System;
using System.Threading.Tasks;
using Settings=Godot.Collections.Dictionary;

public partial class ModuleLinkUi : RefCounted
{
    private readonly ModuleLinkOperations _links=new();
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private static BuildingEditOperations Edits()=>Engine.GetSingleton("KiwiNativeServices").Call("service","building_edit").As<BuildingEditOperations>();
    internal static async Task<bool> Flush(GodotObject waiter,RefCounted session,SceneTree tree)
    {
        bool success=true;while(true){var state=Edits().pending(session);if(state.Count==0)return success;await waiter.ToSignal(tree,SceneTree.SignalName.ProcessFrame);success&=state["success"].AsBool();}
    }
    public bool properties(Control workspace,Resource item,Node parent)
    {
        var values=item.Get("parameters").AsGodotDictionary();string path=Get(values,"architecture_module_source", "").AsString();if(path.Length==0)return false;bool linked=Get(values,"module_linked",false).AsBool();parent.AddChild(new Label {Text=(linked?"LINKED MODEL · ":"MODEL SNAPSHOT · ")+path.GetFile(),TooltipText=path,TextOverrunBehavior=TextServer.OverrunBehavior.TrimEllipsis});var open=new Button {Text="Open source ↗",Disabled=!Godot.FileAccess.FileExists(path)};parent.AddChild(open);open.Pressed+=()=>workspace.GetTree().GetFirstNodeInGroup("actor_scene_tabs")?.Call("open_model",path);string id=item.Get("id").AsString();foreach(var entry in new[]{("Refresh from source",false),("Reset source overrides",true)}){var button=new Button {Text=entry.Item1,Disabled=!linked};parent.AddChild(button);bool reset=entry.Item2;button.Pressed+=()=>_ = Refresh(workspace,id,reset);}var unique=new Button {Text="Make unique"};parent.AddChild(unique);unique.Pressed+=()=>_links.make_unique(workspace.Get("session").As<RefCounted>(),id);return true;
    }
    private async Task Refresh(Control workspace,string id,bool reset)
    {
        try{var session=workspace.Get("session").As<RefCounted>();if(!await Flush(this,session,workspace.GetTree())||!GodotObject.IsInstanceValid(workspace)||!workspace.IsInsideTree()||workspace.Get("session").As<RefCounted>()!=session)return;string error=_links.refresh(session,id,reset);workspace.Get("status").As<Label>().Text=error.Length>0?error:"Linked model updated";}catch(Exception failure){if(GodotObject.IsInstanceValid(workspace)&&workspace.IsInsideTree())workspace.Get("status").As<Label>().Text=failure.Message;GD.PushError(failure.ToString());}
    }
}
