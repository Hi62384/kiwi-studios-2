using Godot;
using System;
using System.Text.RegularExpressions;
public partial class NaturalMaterialShaderSourceOperations:RefCounted
{
    private static readonly string[] Functions={"nm_metal","nm_wood","nm_fabric","nm_stone","nm_ground","nm_organic","nm_weather","nm_illustration","nm_geometry","nm_noise"};
    private static readonly string[] Symbols={"seamless","family","variant","density","thickness","roughness","distortion","detail","knots","contrast","brightness","seed","noise_map","primary","secondary","h","n","cell","line","pattern","raw_pattern","natural_color","natural_surface","nm_fbm","nm_threads","nm_wood","nm_metal","nm_fabric","nm_stone","nm_ground","nm_organic","nm_weather","nm_illustration","nm_geometry","nm_noise"};
    private readonly NaturalMaterialDefinitionOperations _definitions=new();
    
    public int family_index(string id){var categories=NaturalMaterialCatalog.categories();string category=_definitions.category(id);int index=0;foreach(var key in categories.Keys){if(key.AsString()==category)return index;index++;}return 0;}
    public string pattern_source(string source,string id)
    {
        string selected=Functions[family_index(id)];foreach(string function in Functions)if(function!=selected)source=replace_function(source,"float "+function+"(","");
        return replace_function(source,"float raw_pattern(","float raw_pattern(vec2 p){p*=max(.01,density);float v="+selected+"(p);return clamp((v-.5)*contrast+.5+brightness,0.,1.);}");
    }
    public string secondary_source(string source,string id){string result=pattern_source(source,id);foreach(string symbol in Symbols)result=Regex.Replace(result,@"\b"+symbol+@"\b","secondary_"+symbol);return result;}
    public string replace_function(string code,string marker,string replacement){int start=code.IndexOf(marker,StringComparison.Ordinal);if(start<0)return code;int opening=code.IndexOf('{',start);int end=block_end(code,opening);return code[..start]+replacement+code[(end+1)..];}
    public int block_end(string code,int opening){int depth=0;for(int i=Math.Max(0,opening);i<code.Length;i++){if(code[i]=='{')depth++;else if(code[i]=='}'&&--depth==0)return i;}return code.Length-1;}
    public string constants(string code,string id,string prefix){code=Regex.Replace(code,"uniform int "+prefix+@"family=\d+;","const int "+prefix+"family="+family_index(id)+";");return Regex.Replace(code,"uniform int "+prefix+@"variant=\d+;","const int "+prefix+"variant="+_definitions.variant(id)+";");}
}
