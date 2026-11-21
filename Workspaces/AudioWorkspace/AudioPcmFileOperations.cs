using Godot;
using System;
using System.Buffers.Binary;
using System.Text;
using Settings=Godot.Collections.Dictionary;

public partial class AudioPcmFileOperations : RefCounted
{
    public const int MaxHeader=1024*1024,MaxChunks=128,MaxReadFrames=16384;
    private static string Tag(byte[] data,int at)=>Encoding.ASCII.GetString(data,at,4);
    private static ushort U16(byte[] data,int at)=>BinaryPrimitives.ReadUInt16LittleEndian(data.AsSpan(at,2));
    private static uint U32(byte[] data,int at)=>BinaryPrimitives.ReadUInt32LittleEndian(data.AsSpan(at,4));
    public Settings inspect(string path)
    {
        using var file=Godot.FileAccess.Open(path,Godot.FileAccess.ModeFlags.Read);if(file==null)return new Settings {["error"]="Could not open PCM source."};ulong size=file.GetLength();var head=file.GetBuffer(12);if(head.Length!=12||Tag(head,0)!="RIFF"||Tag(head,8)!="WAVE")return new Settings {["error"]="File preview supports RIFF PCM WAV; RF64 and compressed WAV require conversion or a shorter render range."};var info=new Settings();ulong cursor=12;
        for(int chunk=0;chunk<MaxChunks;chunk++)
        {
            if(cursor+8>size||cursor+8>MaxHeader)break;file.Seek(cursor);var header=file.GetBuffer(8);if(header.Length!=8)break;string tag=Tag(header,0);uint bytes=U32(header,4);ulong start=cursor+8;if(bytes>size-start)break;
            if(tag=="fmt "&&bytes>=16){var fmt=file.GetBuffer(Math.Min(bytes,40));if(fmt.Length<16)break;uint format=U16(fmt,0);int channels=U16(fmt,2),rate=unchecked((int)U32(fmt,4)),align=U16(fmt,12),bits=U16(fmt,14);if(format==0xfffe){if(fmt.Length<40||U16(fmt,16)<22||U16(fmt,18)!=bits)break;ReadOnlySpan<byte> suffix=new byte[]{0,0,16,0,128,0,0,170,0,56,155,113};if(!fmt.AsSpan(28,12).SequenceEqual(suffix))break;format=U32(fmt,24);}if(channels is not 1 and not 2||rate<8000||rate>192000||align!=channels*(bits/8))break;if(!(format==1&&bits is 8 or 16 or 24 or 32)&&!(format==3&&bits==32))break;if(U32(fmt,8)!=(uint)(rate*align))break;info=new Settings {["format"]=(long)format,["channels"]=channels,["rate"]=rate,["bits"]=bits,["align"]=align};}
            else if(tag=="data"&&info.Count>0&&bytes>0&&bytes%info["align"].AsInt32()==0){long frames=bytes/info["align"].AsInt32();info["data_offset"]=(long)start;info["data_bytes"]=(long)bytes;info["frames"]=frames;info["duration"]=(double)frames/info["rate"].AsInt32();info["error"]="";info["file_bytes"]=(long)size;info["modified"]=(long)Godot.FileAccess.GetModifiedTime(path);return info;}cursor=start+bytes+(bytes%2);
        }
        return new Settings {["error"]="Unsupported/truncated WAV or metadata exceeds the 1 MiB/128-chunk header bound. Use PCM mono/stereo or a shorter converted source."};
    }
    public Vector2[] read_frames(Godot.FileAccess? file,Settings info,long first,int count)
    {
        if(file==null||first<0||count<=0||!info.TryGetValue("error",out var error)||error.AsString().Length>0)return Array.Empty<Vector2>();count=(int)Math.Min(MaxReadFrames,Math.Min(count,Math.Max(0,info["frames"].AsInt64()-first)));if(count==0)return Array.Empty<Vector2>();int align=info["align"].AsInt32(),bits=info["bits"].AsInt32(),format=info["format"].AsInt32(),width=bits/8;file.Seek((ulong)(info["data_offset"].AsInt64()+first*align));var bytes=file.GetBuffer(count*align);count=Math.Min(count,bytes.Length/align);var result=new Vector2[count];bool stereo=info["channels"].AsInt32()==2;for(int frame=0;frame<count;frame++){int at=frame*align;float left=(float)sample(bytes,at,bits,format),right=stereo?(float)sample(bytes,at+width,bits,format):left;result[frame]=new Vector2(left,right);}return result;
    }
    public double sample(byte[] bytes,int at,int bits,int format)
    {
        double value;if(format==3)value=BitConverter.Int32BitsToSingle(BinaryPrimitives.ReadInt32LittleEndian(bytes.AsSpan(at,4)));else if(bits==8)value=(bytes[at]-128)/128.0;else if(bits==16)value=BinaryPrimitives.ReadInt16LittleEndian(bytes.AsSpan(at,2))/32768.0;else if(bits==24){int signed=bytes[at]|(bytes[at+1]<<8)|(bytes[at+2]<<16);if((signed&0x800000)!=0)signed-=0x1000000;value=signed/8388608.0;}else value=BinaryPrimitives.ReadInt32LittleEndian(bytes.AsSpan(at,4))/2147483648.0;return double.IsFinite(value)?value:0;
    }
}
