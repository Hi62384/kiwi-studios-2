using Godot;
using System;
using System.Globalization;
using Settings=Godot.Collections.Dictionary;

public partial class ShaderBrowserOperations
{
    private static double Component(Variant value,int axis,Variant.Type type)
    {if(value.VariantType==Variant.Type.Nil)return 0;return type==Variant.Type.Vector2?value.AsVector2()[axis]:type==Variant.Type.Vector3?value.AsVector3()[axis]:value.AsVector4()[axis];}
    private static Variant ChangedVector(Variant value,int axis,double next,Variant.Type type)
    {if(type==Variant.Type.Vector2){var vector=value.VariantType==Variant.Type.Nil?Vector2.Zero:value.AsVector2();vector[axis]=(float)next;return vector;}if(type==Variant.Type.Vector3){var vector=value.VariantType==Variant.Type.Nil?Vector3.Zero:value.AsVector3();vector[axis]=(float)next;return vector;}var last=value.VariantType==Variant.Type.Nil?Vector4.Zero:value.AsVector4();last[axis]=(float)next;return last;}
    private static double Number(string text)=>double.TryParse(text,NumberStyles.Float,CultureInfo.InvariantCulture,out var value)?value:0;
    public void build_uniforms(Control owner)
    {
        var parent=Node<VBoxContainer>(owner,"uniforms");foreach(var child in parent.GetChildren()){parent.RemoveChild(child);child.QueueFree();}var live=Live(owner);if(live.error_text.Length>0)return;var shader=live.shader;
        foreach(var value in shader.GetShaderUniformList())
        {
            var info=value.AsGodotDictionary();var type=(Variant.Type)Get(info,"type",0).AsInt32();if(type is not (Variant.Type.Float or Variant.Type.Int or Variant.Type.Bool or Variant.Type.Color or Variant.Type.Vector2 or Variant.Type.Vector3 or Variant.Type.Vector4))continue;var name=new StringName(info["name"].AsString());var row=new HBoxContainer();parent.AddChild(row);row.AddChild(new Label {Text=name.ToString().Capitalize(),SizeFlagsHorizontal=Control.SizeFlags.ExpandFill});var initial=RenderingServer.ShaderGetParameterDefault(shader.GetRid(),name);
            bool Valid()=>Fresh(owner,row)&&live.shader==shader;
            if(type==Variant.Type.Bool){var check=new CheckButton();check.SetPressedNoSignal(initial.AsBool());check.Toggled+=next=>{if(Valid())live.material.SetShaderParameter(name,next);};row.AddChild(check);}
            else if(type==Variant.Type.Color){var color=new ColorPickerButton {CustomMinimumSize=new Vector2(70,25),Color=initial.VariantType==Variant.Type.Color?initial.AsColor():Colors.White};color.ColorChanged+=next=>{if(Valid())live.material.SetShaderParameter(name,next);};row.AddChild(color);}
            else if(type is Variant.Type.Vector2 or Variant.Type.Vector3 or Variant.Type.Vector4)
            {int components=type==Variant.Type.Vector2?2:type==Variant.Type.Vector3?3:4;for(int axis=0;axis<components;axis++){int index=axis;var component=new SpinBox {MinValue=-100,MaxValue=100,Step=.05,Value=Component(initial,axis,type),CustomMinimumSize=new Vector2(56,0)};component.ValueChanged+=next=>{if(!Valid())return;var vector=live.material.GetShaderParameter(name);if(vector.VariantType==Variant.Type.Nil)vector=initial;live.material.SetShaderParameter(name,ChangedVector(vector,index,next,type));};row.AddChild(component);}}
            else
            {var range=Get(info,"hint_string","").AsString().Split(',');bool hinted=Get(info,"hint",0).AsInt32()==(int)PropertyHint.Range&&range.Length>=2;var number=new SpinBox {MinValue=hinted?Number(range[0]):-100,MaxValue=hinted?Number(range[1]):100,Step=type==Variant.Type.Int?1:.01,Value=initial.VariantType==Variant.Type.Nil?0:initial.AsDouble()};number.ValueChanged+=next=>{if(Valid())live.material.SetShaderParameter(name,type==Variant.Type.Int?Variant.From((long)next):Variant.From(next));};row.AddChild(number);}
        }
    }
}
