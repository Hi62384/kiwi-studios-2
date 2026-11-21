using Godot;
using System;
using System.Buffers.Binary;

[GlobalClass]
public partial class AudioFloatStageReader : RefCounted
{
    public Godot.FileAccess? file {get;set;}
    public long frames {get;set;}
    public long first {get;set;}=-1;
    public Vector2[] values {get;set;}=Array.Empty<Vector2>();
    public string error {get;set;}="";
    public bool open(string path){file=Godot.FileAccess.Open(path,Godot.FileAccess.ModeFlags.Read);if(file==null){error="Could not open the staged Doppler input.";return false;}ulong size=file.GetLength();if(size==0||size%8!=0||size>512L*1024*1024){error="Doppler needs a nonempty stereo f32le stage no larger than 512 MiB. Split or bake a shorter region.";close();return false;}frames=(long)size/8;return true;}
    public Vector2 sample(long frame)
    {
        if(frame<0||frame>=frames||error.Length>0)return Vector2.Zero;if(frame<first||frame>=first+values.Length){first=Math.Max(0,frame-1024);int count=(int)Math.Min(4096,frames-first);file!.Seek((ulong)(first*8));var data=file.GetBuffer(count*8);if(data.Length!=count*8){error="Could not read the complete staged Doppler input.";return Vector2.Zero;}values=new Vector2[count];for(int index=0;index<count;index++){float left=BitConverter.Int32BitsToSingle(BinaryPrimitives.ReadInt32LittleEndian(data.AsSpan(index*8,4))),right=BitConverter.Int32BitsToSingle(BinaryPrimitives.ReadInt32LittleEndian(data.AsSpan(index*8+4,4)));if(!float.IsFinite(left)||!float.IsFinite(right)){error="Non-finite audio in the staged Doppler input.";return Vector2.Zero;}values[index]=new Vector2(left,right);}}return values[(int)(frame-first)];
    }
    public void close(){if(file!=null){file.Close();file.Dispose();file=null;}values=Array.Empty<Vector2>();}
}
