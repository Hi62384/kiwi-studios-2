using Godot;

[GlobalClass]
public partial class NodeOperations : Node
{
    public static void delete_children(Node node)
    {
        foreach (Node child in node.GetChildren()) child.QueueFree();
    }
}
