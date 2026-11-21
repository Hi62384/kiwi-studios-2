using Godot;
[GlobalClass]
public partial class AudioLibraryDragList : ItemList
{
    public override Variant _GetDragData(Vector2 position)
    {using var operations=new AudioLibraryOperations();return operations.drag_data(this);}
}
