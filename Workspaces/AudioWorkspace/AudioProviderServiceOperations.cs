using Godot;
using System;
using System.IO;
using System.Text;
using GArray=Godot.Collections.Array;
using Settings=Godot.Collections.Dictionary;
public partial class AudioProviderServiceOperations:RefCounted
{
    private static Variant Get(Settings d,string key,Variant fallback=default)=>d.TryGetValue(key,out var v)?v:fallback;
    private static bool B(Settings d,string key,bool fallback=false)=>Get(d,key,fallback).AsBool();
    private static Settings Providers(RefCounted o)=>o.Get("providers").AsGodotDictionary();
    private static Settings Fail(string error)=>new(){["success"]=false,["error"]=error};
    public Error register(RefCounted o,RefCounted provider){string id=Get(provider.Call("descriptor").AsGodotDictionary(),"id","").AsString();if(id.Length==0||Providers(o).ContainsKey(id))return Error.InvalidParameter;Providers(o)[id]=provider;return Error.Ok;}
    public GArray catalog(RefCounted o){var result=new GArray();foreach(var raw in Providers(o).Values)result.Add(raw.AsGodotObject().Call("descriptor").AsGodotDictionary().Duplicate(true));return result;}
    public Settings run(RefCounted o,string providerId,Settings request,Settings consent,RefCounted? job)
    {
        if(!Providers(o).TryGetValue(providerId,out var selected))return Fail("No compatible provider is configured.");var provider=selected.AsGodotObject();var info=provider.Call("descriptor").AsGodotDictionary();string task=Get(request,"task","sound_effect").AsString();if(!Get(info,"tasks",new GArray()).AsGodotArray().Contains(task))return Fail("The provider does not support this task.");if(!B(consent,"send_request"))return Fail("Confirm sending this prompt and any selected audio to the named provider first.");if(task=="speech"&&!B(consent,"voice_authorized"))return Fail("Confirm that you are authorized to use the requested voice.");var estimate=provider.Call("estimate",request).AsGodotDictionary();bool known=B(estimate,"known");if(!known&&!B(consent,"unknown_cost"))return Fail("Provider cost is unknown. Explicit approval is required.");if(known&&(Get(consent,"currency","").AsString()!=Get(estimate,"currency","").AsString()||Get(consent,"maximum_cost",0).AsDouble()<Get(estimate,"amount",0).AsDouble()))return Fail("The request exceeds the approved provider cost.");if(job!=null&&job.Call("is_cancelled").AsBool())return Fail("Cancelled before transmission.");string credential="";
        if(B(info,"credential_required",true)){if(!o.Call("_has_credential_reader").AsBool())return Fail("A secure OS-credential-vault adapter has not been configured. Project files cannot store API keys.");credential=o.Call("_read_credential",providerId).AsString();if(credential.Length==0)return Fail("The provider credential is missing from the secure vault.");}
        var result=provider.Call("generate",request.Duplicate(true),credential,job!).AsGodotDictionary();credential="";if(job!=null&&job.Call("is_cancelled").AsBool())return Fail("Cancelled. A submitted provider request may already have consumed quota.");if(!B(result,"success"))return Fail("Provider generation failed. Check its status in the provider adapter; credentials and raw responses are not logged.");var stream=Get(result,"stream").AsGodotObject() as AudioStream;if(stream==null||stream.GetLength()<=0)return Fail("The provider did not return valid editable audio.");return new Settings{["success"]=true,["stream"]=stream,["metadata"]=new Settings{["origin"]="provider_generated",["provider"]=providerId,["model"]=Get(request,"model",""),["task"]=task,["synthetic_voice"]=task=="speech",["created"]=Time.GetUnixTimeFromSystem()}};
    }
}
public partial class AudioElevenLabsOperations:RefCounted
{
    private static Variant Get(Settings d,string key,Variant fallback=default)=>d.TryGetValue(key,out var v)?v:fallback;
    private static Settings Fail(string error)=>new(){["success"]=false,["error"]=error};
    public Settings descriptor()=>new(){["id"]="elevenlabs",["label"]="ElevenLabs speech (optional)",["tasks"]=new GArray{"speech"},["models"]=new GArray{"eleven_multilingual_v2"},["supports_cancel"]=true,["credential_required"]=true};
    public Settings generate(RefCounted o,Settings request,string credential,RefCounted? job)
    {
        string text=Get(request,"prompt","").AsString(),voice=Get(request,"voice_id","").AsString(),model=Get(request,"model","eleven_multilingual_v2").AsString();if(text.Trim().Length==0||text.Length>3000||voice.Length==0||voice.Length>128||credential.Length==0)return Fail("Enter text (up to 3000 characters), a voice ID and a stored credential.");if(credential.Contains('\r')||credential.Contains('\n'))return Fail("Invalid provider credential.");foreach(char c in voice)if(!((c>='a'&&c<='z')||(c>='A'&&c<='Z')||(c>='0'&&c<='9')||c is '_' or '-'))return Fail("Invalid voice ID.");if(!descriptor()["models"].AsGodotArray().Contains(model))return Fail("Unsupported speech model.");byte[] body=Encoding.UTF8.GetBytes(Json.Stringify(new Settings{["text"]=text,["model_id"]=model}));var result=o.Call("_has_transport").AsBool()?o.Call("_dispatch_transport",voice,body,credential,job!).AsGodotDictionary():request_audio(voice,body,credential,job);if(!Get(result,"success",false).AsBool())return Fail(Get(result,"error","Speech request failed.").AsString());var data=Get(result,"data",Array.Empty<byte>()).AsByteArray();if(data.Length==0||data.Length>16*1024*1024)return Fail("Invalid or oversized speech response.");var stream=AudioStreamMP3.LoadFromBuffer(data);if(stream==null||stream.GetLength()<=0||stream.GetLength()>180){stream?.Dispose();return Fail("Provider audio exceeds the three-minute limit or could not be decoded.");}return new Settings{["success"]=true,["stream"]=stream};
    }
    public Settings request_audio(string voice,byte[] body,string key,RefCounted? job)
    {
        using var client=new HttpClient();var error=client.ConnectToHost("api.elevenlabs.io",443,TlsOptions.Client());if(error!=Error.Ok)return Fail("Could not initialize the provider connection.");ulong deadline=Time.GetTicksMsec()+180000;bool sent=false;using var data=new MemoryStream();int status=0;string problem="";
        while(Time.GetTicksMsec()<deadline)
        {
            if(job!=null&&job.Call("is_cancelled").AsBool()){problem="Cancelled.";break;}if(client.Poll()!=Error.Ok){problem="Provider connection failed; TLS verification remains enabled.";break;}var state=client.GetStatus();if(state==HttpClient.Status.Connected&&!sent){error=client.RequestRaw(HttpClient.Method.Post,"/v1/text-to-speech/"+voice+"?output_format=mp3_44100_128",new[]{"Content-Type: application/json","Accept: audio/mpeg","xi-api-key: "+key},body);key="";sent=true;if(error!=Error.Ok){problem="Could not send the approved speech request.";break;}}
            if(client.HasResponse()){status=client.GetResponseCode();if(status!=200){problem="Provider rejected the request (HTTP "+status+"). Check quota, credential and voice access.";break;}if(client.GetResponseBodyLength()>16*1024*1024){problem="Provider response exceeds the 16 MiB limit.";break;}}
            if(state==HttpClient.Status.Body){var block=client.ReadResponseBodyChunk();if(data.Length+block.LongLength>16*1024*1024){problem="Provider response exceeds the 16 MiB limit.";break;}data.Write(block);}else if(sent&&status==200&&state==HttpClient.Status.Connected){client.Close();return new Settings{["success"]=true,["data"]=data.ToArray()};}else if(state is HttpClient.Status.CantResolve or HttpClient.Status.CantConnect or HttpClient.Status.ConnectionError or HttpClient.Status.TlsHandshakeError or HttpClient.Status.Disconnected){problem="Provider connection closed or failed.";break;}OS.DelayMsec(10);
        }
        client.Close();return Fail(problem.Length>0?problem:"Provider request timed out.");
    }
}
