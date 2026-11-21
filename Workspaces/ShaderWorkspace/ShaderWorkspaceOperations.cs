using Godot;
using System;
using System.Globalization;
using System.Linq;
using System.Text.RegularExpressions;
using Settings=Godot.Collections.Dictionary;

public partial class ShaderWorkspaceOperations : RefCounted
{
    private static T Item<[MustBeVariant] T>(Control owner,string key) where T:GodotObject=>owner.Get(key).As<T>();
    private static CodeEdit Code(Control owner)=>Item<Control>(owner,"editor").Get("code").As<CodeEdit>();
    private static readonly Regex FloatLiteral=new(@"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$",RegexOptions.CultureInvariant);
    private static bool Float(string text,out double value){text=text.Trim();value=0;return FloatLiteral.IsMatch(text)&&double.TryParse(text,NumberStyles.Float,CultureInfo.InvariantCulture,out value);}
    private static string TrimSuffix(string text,char suffix)=>text.EndsWith(suffix)?text[..^1]:text;
    public Settings declared_uniform_default(string source,StringName name,int valueType)
    {
        var found=Regex.Match(source,@"(?m)\buniform\s+[A-Za-z_][A-Za-z0-9_]*\s+"+Regex.Escape(name.ToString())+@"(?:\s*:[^=;]+)?\s*=\s*([^;]+);");Settings Missing()=>new() {["found"]=false};Settings Value(Variant value)=>new() {["found"]=true,["value"]=value};if(!found.Success)return Missing();string expression=found.Groups[1].Value.Trim();var type=(Variant.Type)valueType;
        if(type==Variant.Type.Bool&&expression is "true" or "false")return Value(expression=="true");if(type==Variant.Type.Int&&long.TryParse(TrimSuffix(expression,'u'),NumberStyles.AllowLeadingSign,CultureInfo.InvariantCulture,out var integer))return Value(integer);if(type==Variant.Type.Float&&Float(TrimSuffix(expression,'f'),out var number))return Value(number);
        if(type is Variant.Type.Vector2 or Variant.Type.Vector3 or Variant.Type.Vector4 or Variant.Type.Color)
        {
            var constructor=Regex.Match(expression,@"^(?:vec[234]|ivec[234]|uvec[234])\s*\((.*)\)$");if(!constructor.Success)return Missing();int count=type==Variant.Type.Vector2?2:type==Variant.Type.Vector3?3:4;var pieces=constructor.Groups[1].Value.Split(',');var values=new System.Collections.Generic.List<double>();foreach(string piece in pieces){if(!Float(TrimSuffix(piece.Trim(),'f'),out var value))return Missing();values.Add(value);}if(values.Count==1)while(values.Count<count)values.Add(values[0]);if(values.Count!=count)return Missing();return type switch {Variant.Type.Vector2=>Value(new Vector2((float)values[0],(float)values[1])),Variant.Type.Vector3=>Value(new Vector3((float)values[0],(float)values[1],(float)values[2])),Variant.Type.Vector4=>Value(new Vector4((float)values[0],(float)values[1],(float)values[2],(float)values[3])),_=>Value(new Color((float)values[0],(float)values[1],(float)values[2],(float)values[3]))};
        }
        return Missing();
    }
    public Variant shader_uniform_default(Control owner,StringName name,int valueType)
    {
        if(valueType==(int)Variant.Type.Object)return default;var declared=declared_uniform_default(Code(owner).Text,name,valueType);if(declared["found"].AsBool())return declared["value"];var value=RenderingServer.ShaderGetParameterDefault(Item<Shader>(owner,"preview_shader").GetRid(),name);if(value.VariantType!=Variant.Type.Nil)return value;return (Variant.Type)valueType switch {Variant.Type.Bool=>Variant.From(false),Variant.Type.Int=>Variant.From(0L),Variant.Type.Float=>Variant.From(0.0),Variant.Type.Vector2=>Variant.From(Vector2.Zero),Variant.Type.Vector3=>Variant.From(Vector3.Zero),Variant.Type.Vector4=>Variant.From(Vector4.Zero),Variant.Type.Color=>Variant.From(Colors.White),_=>default};
    }
    public float[] hint_range(string hint)
    {var pieces=hint.Split(',');return pieces.Length>=2&&Float(pieces[0],out var first)&&Float(pieces[1],out var last)?new[]{(float)first,(float)last}:Array.Empty<float>();}
    public int uniform_type(Control owner,StringName name)
    {foreach(var value in Item<Shader>(owner,"preview_shader").GetShaderUniformList()){var info=value.AsGodotDictionary();if(info.TryGetValue("name",out var found)&&found.AsString()==name.ToString())return info.TryGetValue("type",out var type)?type.AsInt32():0;}return 0;}
    public string shader_type(string source)
    {var found=Regex.Match(source,@"(?m)^\s*shader_type\s+([A-Za-z_][A-Za-z0-9_]*)\s*;");return found.Success?found.Groups[1].Value:"spatial";}
    public StyleBoxFlat box(Color background,Color border,int radius)
    {var style=new StyleBoxFlat {BgColor=background,BorderColor=border,ContentMarginLeft=9,ContentMarginRight=9,ContentMarginTop=7,ContentMarginBottom=7};style.SetBorderWidthAll(1);style.SetCornerRadiusAll(radius);return style;}
    public Button button(string text,bool accent)
    {var button=new Button {Text=text,CustomMinimumSize=new Vector2(0,32)};button.AddThemeStyleboxOverride("normal",box(new Color(accent?"20544e":"1d2f3e"),new Color(accent?"69d8c1":"3c586b"),7));button.AddThemeStyleboxOverride("hover",box(new Color(accent?"2d6e63":"29495d"),new Color("91f0d9"),7));return button;}
    public void style_parameter_color(ColorPickerButton button,Color value)
    {button.Text="  "+value.ToHtml(value.A<1).ToUpperInvariant();var border=value.Luminance<.45?Colors.White:new Color("1b2a35");foreach(string state in new[]{"normal","hover","pressed"})button.AddThemeStyleboxOverride(state,box(value,border,6));button.AddThemeColorOverride("font_color",value.Luminance<.45?Colors.White:new Color("101820"));}
    public string document_title(Control owner)
    {string path=owner.Get("current_path").AsString();if(path.Length>0)return path.GetFile();var source=owner.Get("current_source");return source.VariantType==Variant.Type.Object&&source.AsGodotObject() is Shader shader&&shader.ResourceName.Length>0?shader.ResourceName:"Untitled Shader";}
    public string viewport_help(Control owner)=>"Speed "+owner.Get("camera_speed").AsDouble().ToString("F1",CultureInfo.InvariantCulture)+" m/s  ·  Wheel changes speed  ·  Right-drag + WASD/QE to fly";
}
