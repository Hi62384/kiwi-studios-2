using Godot;
using System;
using System.IO;
using System.Text;
using Settings=Godot.Collections.Dictionary;
public partial class AudioOptionalProcessOperations:RefCounted
{
    public Settings run(string executable,string[] args,string input,RefCounted? job,double seconds,int maxBytes)
    {
        if(job!=null&&job.Call("is_cancelled").AsBool())return new Settings{["success"]=false,["error"]="Cancelled."};var process=OS.ExecuteWithPipe(executable,args,false);if(process.Count==0)return new Settings{["success"]=false,["error"]="Could not start the configured optional tool."};using var pipe=process["stdio"].As<Godot.FileAccess>();using var errors=process["stderr"].As<Godot.FileAccess>();int pid=process["pid"].AsInt32();if(input.Length>0)pipe.StoreBuffer(Encoding.UTF8.GetBytes(input+"\n"));using var output=new MemoryStream();long total=0;ulong deadline=Time.GetTicksMsec()+(ulong)(Math.Clamp(seconds,1,1800)*1000);string problem="";bool exited=false;using var encoder=new AudioEncoderProcessOperations();
        while(true)
        {
            for(int i=0;i<8;i++){var block=encoder.available(pipe);var diagnostic=encoder.available(errors);total+=block.LongLength+diagnostic.LongLength;if(output.Length+block.LongLength<=maxBytes)output.Write(block);if(block.Length==0&&diagnostic.Length==0)break;}if(total>maxBytes)problem="Optional tool exceeded its output limit.";if(job!=null&&job.Call("is_cancelled").AsBool())problem="Cancelled.";if(Time.GetTicksMsec()>=deadline)problem="Optional tool exceeded its time limit.";
            if(problem.Length>0){exited=!OS.IsProcessRunning(pid)||OS.Kill(pid)==Error.Ok;break;}if(!OS.IsProcessRunning(pid)){exited=true;break;}OS.DelayMsec(10);
        }
        int code=OS.GetProcessExitCode(pid);for(int i=0;i<8;i++){var block=encoder.available(pipe);if(block.Length==0)break;if(output.Length+block.LongLength>maxBytes){problem="Optional tool exceeded its output limit.";break;}output.Write(block);}pipe.Close();errors.Close();if(problem.Length==0&&code!=0)problem="Optional tool failed. Check its executable/model configuration.";return new Settings{["success"]=problem.Length==0,["error"]=problem,["stdout"]=problem.Length==0?Encoding.UTF8.GetString(output.GetBuffer(),0,(int)output.Length):"",["process_exited"]=exited};
    }
}
public partial class AudioCredentialVaultOperations:RefCounted
{
    public bool available()=>OS.GetName()=="Windows";
    public bool valid_id(string id){if(id.Length==0||id.Length>64)return false;foreach(char c in id)if(!((c>='a'&&c<='z')||(c>='0'&&c<='9')||c is '_' or '-'))return false;return true;}
    public Settings request(string action,string id,string secret,RefCounted? job)
    {
        Settings Fail(string error)=>new(){["success"]=false,["error"]=error};if(!available())return Fail("Windows Credential Manager is unavailable on this platform.");if(!valid_id(id)||action is not ("read" or "write" or "delete")||secret.Length>1200||Encoding.UTF8.GetByteCount(secret)>2400)return Fail("Invalid credential request.");string source=Godot.FileAccess.GetFileAsString("res://scripts/actors/audio/windows_credentials.ps1");if(source.Length==0)return Fail("Could not load the credential helper.");string encoded=Convert.ToBase64String(Encoding.Unicode.GetBytes(source));using var helper=new AudioOptionalProcessOperations();var result=helper.run("powershell.exe",new[]{"-NoProfile","-NonInteractive","-EncodedCommand",encoded},Json.Stringify(new Settings{["action"]=action,["id"]=id,["secret"]=secret}),job,15,16384);if(!result["success"].AsBool())return Fail("Windows Credential Manager request failed; no credentials were logged.");var response=Json.ParseString(result["stdout"].AsString().Trim());return response.VariantType==Variant.Type.Dictionary?response.AsGodotDictionary():Fail("Invalid credential helper response.");
    }
    public string read(string id){var result=request("read",id,"",null);return result["success"].AsBool()&&result.TryGetValue("secret",out var secret)?secret.AsString():"";}
}
