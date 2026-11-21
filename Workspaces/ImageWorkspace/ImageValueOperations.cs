using Godot;
using System;
using GArray=Godot.Collections.Array;
using Settings=Godot.Collections.Dictionary;
public partial class ImageValueOperations:RefCounted
{
    private static Variant Get(Settings d,string key,Variant fallback=default)=>d.TryGetValue(key,out var value)?value:fallback;
    private static readonly (string Key,double Default)[] Basics={("brightness",0),("contrast",1),("saturation",1),("exposure",0),("gamma",1),("hue",0),("temperature",0),("tint",0)};
    private sealed class Operand
    {
        public string Kind="pixel";public float Scalar;public Vector4 Values=Vector4.Zero;public readonly int[] Channels={-1,-1,-1,-1};
        public Vector4 Evaluate(Vector4 pixel){if(Kind=="pixel")return pixel;if(Kind=="float")return Vector4.One*Scalar;var result=Values;for(int index=0;index<4;index++)if(Channels[index]>=0)result[index]=pixel[Channels[index]];return result;}
    }
    private sealed class Operation
    {
        public string Kind="";public bool Enabled,Structured,PreserveHue,AffectAlpha;public double Amount;public Operand A=new(),B=new(),C=new();
    }
    private static Operand CompileOperand(Settings value)
    {
        var result=new Operand{Kind=Get(value,"kind","pixel").AsString(),Scalar=(float)Get(value,"value",0).AsDouble()};if(result.Kind!="vector"){if(result.Kind!="float")result.Kind="pixel";return result;}var channels=Get(value,"channels",new GArray{1.0,1.0,1.0,1.0}).AsGodotArray();for(int index=0;index<4;index++){var channel=channels[index];if(channel.VariantType==Variant.Type.String){int source="rgba".IndexOf(channel.AsString(),StringComparison.Ordinal);if(source<0)throw new ArgumentException("Unknown pixel color channel: "+channel.AsString());result.Channels[index]=source;}else result.Values[index]=(float)channel.AsDouble();}return result;
    }
    private static Operation Compile(Settings data)=>new(){Kind=Get(data,"type","").AsString(),Enabled=Get(data,"enabled",true).AsBool(),Structured=data.ContainsKey("a"),PreserveHue=Get(data,"preserve_hue",true).AsBool(),AffectAlpha=Get(data,"affect_alpha",false).AsBool(),Amount=Get(data,"amount",1).AsDouble(),A=CompileOperand(Get(data,"a",new Settings{["kind"]="pixel"}).AsGodotDictionary()),B=CompileOperand(Get(data,"b",new Settings{["kind"]="pixel"}).AsGodotDictionary()),C=CompileOperand(Get(data,"c",new Settings{["kind"]="float",["value"]=1.0}).AsGodotDictionary())};
    private static Operation[] Compile(GArray operations){var result=new Operation[operations.Count];for(int index=0;index<result.Length;index++)result[index]=Compile(operations[index].AsGodotDictionary());return result;}
    public Settings new_operation(string kind)
    {
        double amount=kind is "multiply" or "divide" or "power" or "minimum"?1:kind=="snap"?.1:0;return new Settings{["type"]=kind,["enabled"]=true,["preserve_hue"]=true,["a"]=new Settings{["kind"]="pixel"},["b"]=kind=="lerp"?new Settings{["kind"]="vector",["channels"]=new GArray{1.0,1.0,1.0,1.0}}:new Settings{["kind"]="float",["value"]=amount},["c"]=new Settings{["kind"]="float",["value"]=kind=="lerp"?.5:1}};
    }
    public Vector4 operand_value(Settings operand,Vector4 pixel)=>CompileOperand(operand).Evaluate(pixel);
    public Vector4 evaluate_operation(Vector4 pixel,Settings operation)=>EvaluateOperation(pixel,Compile(operation));
    private static Vector4 EvaluateOperation(Vector4 pixel,Operation operation)
    {
        var a=operation.A.Evaluate(pixel);var b=operation.B.Evaluate(pixel);var c=operation.C.Evaluate(pixel);var result=a;if(operation.Kind=="snap"&&operation.PreserveHue){double peak=Math.Max(a.X,Math.Max(a.Y,a.Z)),step=Math.Max(.0001,Math.Abs(b.X)),ratio=Math.Floor(peak/step+.5)*step/Math.Max(.00001,peak);return new Vector4((float)(a.X*ratio),(float)(a.Y*ratio),(float)(a.Z*ratio),a.W);}for(int index=0;index<4;index++){double x=a[index],y=b[index],z=c[index];result[index]=(float)(operation.Kind switch{"add"=>x+y,"multiply"=>x*y,"subtract"=>x-y,"divide"=>x/(Math.Max(.0001,Math.Abs(y))*(y<0?-1:1)),"power"=>Math.Pow(Math.Max(0,x),Math.Max(.0001,y)),"minimum"=>Math.Min(x,y),"maximum"=>Math.Max(x,y),"clamp"=>Math.Clamp(x,Math.Min(y,z),Math.Max(y,z)),"lerp"=>x+(y-x)*z,"absolute"=>Math.Abs(x),"invert"=>index<3?1-x:x,"smoothstep"=>Mathf.SmoothStep(Math.Min(y,z),Math.Max(y,z)+.00001,x),"snap"=>Math.Floor(x/Math.Max(.0001,Math.Abs(y))+.5)*Math.Max(.0001,Math.Abs(y)),_=>x});}return result;
    }
    public GArray operations(Resource layer)
    {
        var properties=layer.Get("properties").AsGodotDictionary();var result=Get(properties,"value_operations",new GArray()).AsGodotArray().Duplicate(true);var basics=Get(properties,"value_basics",new Settings()).AsGodotDictionary();foreach(var item in Basics){double value=Get(basics,item.Key,item.Default).AsDouble();if(!Mathf.IsEqualApprox(value,item.Default))result.Add(new Settings{["type"]=item.Key,["amount"]=value});}return result;
    }
    private static Vector4 Evaluate(Vector4 value,Operation[] operations)
    {
        var result=value;foreach(var operation in operations){if(!operation.Enabled)continue;if(operation.Structured){var next=EvaluateOperation(result,operation);if(!operation.AffectAlpha)next.W=result.W;result=next;}else{var rgb=Legacy(new Vector3(result.X,result.Y,result.Z),operation);result=new Vector4(rgb.X,rgb.Y,rgb.Z,result.W);}}return result.Clamp(Vector4.Zero,Vector4.One);
    }
    public Vector4 evaluate_rgba(Vector4 value,GArray operations)=>Evaluate(value,Compile(operations));
    public Vector3 evaluate(Vector3 value,GArray operations){var result=Evaluate(new Vector4(value.X,value.Y,value.Z,1),Compile(operations));return new Vector3(result.X,result.Y,result.Z);}
    public Vector3 legacy_evaluate(Vector3 value,GArray operations){var result=value;foreach(var operation in Compile(operations)){if(!operation.Enabled)continue;if(operation.Structured){var next=EvaluateOperation(new Vector4(result.X,result.Y,result.Z,1),operation);result=new Vector3(next.X,next.Y,next.Z);}else result=Legacy(result,operation);}return result;}
    public Color inverse_color(Color color,Resource layer)
    {
        var raw=operations(layer);if(raw.Count==0)return color;var compiledOperations=Compile(raw);var target=new Vector4(color.R,color.G,color.B,color.A);var best=target;double error=double.PositiveInfinity;foreach(var seed in new[]{target,Vector4.Zero,Vector4.One,new Vector4(.5f,.5f,.5f,.5f)}){var point=seed;double score=Evaluate(point,compiledOperations).DistanceSquaredTo(target),step=.5;for(int iteration=0;iteration<36;iteration++){bool improved=false;for(int axis=0;axis<4;axis++)for(int direction=-1;direction<=1;direction+=2){var next=point;next[axis]=(float)Math.Clamp(next[axis]+step*direction,0,1);double nextScore=Evaluate(next,compiledOperations).DistanceSquaredTo(target);if(nextScore<score){point=next;score=nextScore;improved=true;}}if(!improved)step*=.5;}if(score<error){best=point;error=score;}}return new Color(best.X,best.Y,best.Z,best.W);
    }
}
