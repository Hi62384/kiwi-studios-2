using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
public partial class ActorProjectFileScan:RefCounted
{
    private sealed class Frame
    {
        public readonly string Path;public readonly string[] Files,Folders;public int FileIndex,FolderIndex;public readonly Godot.Collections.Array<string> Matches=new();public readonly Godot.Collections.Array<Settings> Children=new();public int Count;
        public Frame(string path){Path=path;Files=DirAccess.GetFilesAt(path);Folders=DirAccess.GetDirectoriesAt(path);Array.Sort(Files,StringComparer.Ordinal);Array.Sort(Folders,StringComparer.Ordinal);}
        public Settings Result()=>new Settings{["path"]=Path,["files"]=Matches,["folders"]=Children,["count"]=Count};
    }
    private Node? _owner;private int _generation;private readonly Stack<Frame> _frames=new();private readonly ActorProjectFilePickerOperations _picker=new();private Settings _result=new();private bool _done;
    public ActorProjectFileScan(){}
    public ActorProjectFileScan(Node owner,string path,int generation){_owner=owner;_generation=generation;_frames.Push(new Frame(path));}
    public Settings result()=>_result;
    public bool step(int budget)
    {
        if(_done)return true;if(_owner==null||!GodotObject.IsInstanceValid(_owner)||_owner.Get("_resolved").AsBool()||_owner.Get("clipboard_source").AsBool()||_generation!=_owner.Get("_tree_generation").AsInt32()){_frames.Clear();_done=true;return true;}budget=Math.Max(1,budget);
        while(_frames.Count>0&&budget>0)
        {
            var current=_frames.Peek();if(current.FileIndex<current.Files.Length){string path=current.Path.PathJoin(current.Files[current.FileIndex++]).SimplifyPath();_owner.Set("_scan_entries",_owner.Get("_scan_entries").AsInt64()+1);if(_picker.path_allowed(_owner,path)){current.Matches.Add(path);current.Count++;_owner.Get("_indexed_paths").AsGodotArray().Add(path);}budget--;continue;}
            if(current.FolderIndex<current.Folders.Length){string name=current.Folders[current.FolderIndex++];budget--;if(name.StartsWith(".",StringComparison.Ordinal))continue;using var directory=DirAccess.Open(current.Path);if(directory!=null&&directory.IsLink(name))continue;_frames.Push(new Frame(current.Path.PathJoin(name).SimplifyPath()));continue;}
            var completed=current.Result();_frames.Pop();if(_frames.Count==0){_result=completed;_done=true;return true;}if(current.Count>0){_frames.Peek().Children.Add(completed);_frames.Peek().Count+=current.Count;}
        }
        return false;
    }
}
