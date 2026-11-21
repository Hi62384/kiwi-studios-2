using Godot;

public partial class FileModelImportOperations : RefCounted
{
    public PackedScene? load_3d_model(string path)
    {
        bool fbx=path.GetExtension().ToLowerInvariant()=="fbx";using GltfDocument document=fbx?new FbxDocument():new GltfDocument();using GltfState state=fbx?new FbxState():new GltfState();if(document.AppendFromFile(path,state)!=Error.Ok)return null;var scene=document.GenerateScene(state);if(scene==null)return null;
        try{var packed=new PackedScene();if(packed.Pack(scene)==Error.Ok)return packed;packed.Dispose();return null;}
        finally{scene.Free();}
    }
}
