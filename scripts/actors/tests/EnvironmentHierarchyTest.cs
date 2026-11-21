using Godot;
using System;
using System.Threading.Tasks;

public partial class EnvironmentHierarchyTest : Node
{
    private int _checks;
    private void Check(bool value,string text){if(!value)throw new Exception(text);_checks++;GD.Print("PASS ",text);}
    private async Task Settle(){for(int i=0;i<6;i++)await ToSignal(GetTree(),SceneTree.SignalName.ProcessFrame);}
    public override async void _Ready()
    {
        Control? workspace=null;
        try
        {
            workspace=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/environment_workspace.gd").New().As<Control>();AddChild(workspace);await Settle();var session=workspace.Get("session").As<RefCounted>();var parent=session.Call("add_group","Parent").As<Resource>();var child=session.Call("add_group","Find child").As<Resource>();child.Set("parent_id",parent.Get("id"));var sibling=session.Call("add_group","Sibling").As<Resource>();session.Get("selected").AsGodotArray().Clear();workspace.Call("_refresh_tree");var tree=workspace.Get("hierarchy").As<Tree>();
            TreeItem? Find(TreeItem? row,string id){if(row==null)return null;if(row.GetMetadata(0).VariantType==Variant.Type.String&&row.GetMetadata(0).AsString()==id)return row;for(var next=row.GetFirstChild();next!=null;next=next.GetNext()){var found=Find(next,id);if(found!=null)return found;}return null;}
            TreeItem Row(Resource item)=>Find(tree.GetRoot(),item.Get("id").AsString())??throw new Exception("Missing hierarchy row");
            Check(Row(child).GetParent()==Row(parent),"Native hierarchy preserves component parenting");Row(parent).Collapsed=true;workspace.Call("_refresh_tree");Check(Row(parent).Collapsed,"Collapsed parent survives tree rebuild");
            workspace.Get("search").As<LineEdit>().Text="Find child";workspace.Call("_refresh_tree");Check(Find(tree.GetRoot(),sibling.Get("id").AsString())==null&&Row(child).GetParent()==Row(parent)&&!Row(parent).Collapsed,"Filtering retains matching descendants and expands their ancestors");
            workspace.Call("_tree_selected",Row(child),0,true);Check(session.Get("selected").AsGodotArray().Count==1&&session.Get("selected").AsGodotArray()[0].AsString()==child.Get("id").AsString(),"Hierarchy selection selects the intended component");workspace.Call("_tree_selected",Row(child),0,false);Check(session.Get("selected").AsGodotArray().Count==0,"Hierarchy deselection clears that component");
            workspace.Set("_building",true);workspace.Call("_tree_selected",Row(child),0,true);Check(session.Get("selected").AsGodotArray().Count==0,"Programmatic tree refresh cannot mutate selection");workspace.Set("_building",false);
            session.Get("_undo").AsGodotArray().Clear();session.Get("_redo").AsGodotArray().Clear();workspace.QueueFree();workspace=null;await Settle();GD.Print("ENVIRONMENT HIERARCHY: ",_checks," checks");GetTree().Quit();
        }
        catch(Exception error){GD.PushError(error.ToString());workspace?.QueueFree();await Settle();GetTree().Quit(1);}
    }
}
