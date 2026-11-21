using Godot;
public partial class EnvironmentAssetList : ItemList
{
    public override Variant _GetDragData(Vector2 point)
    {int index=GetItemAtPosition(point,true);if(index<0)return default;string path=GetItemMetadata(index).AsString();SetDragPreview(new Label {Text=path.GetFile()});return new Godot.Collections.Dictionary {["files"]=new Godot.Collections.Array {path}};}
}
