using Godot;
using System;
using GArray=Godot.Collections.Array;
using Settings=Godot.Collections.Dictionary;
public partial class ActorTextSettingsOperations:RefCounted
{
    private static Variant Get(Settings settings,string key,Variant fallback=default)=>settings.TryGetValue(key,out var value)||settings.TryGetValue(new StringName(key),out value)?value:fallback;
    private static bool IsScript(Resource? resource,string path){var script=resource?.GetScript().As<Script>();while(script!=null){if(script.ResourcePath==path||script.ResourcePath==LegacyResourceLoader.NativeScriptPath(path))return true;script=script.GetBaseScript();}return false;}
    public string[] system_fonts()
    {
        var families=ActorTextSettings.Families;if(families.Length>0)return families;families=OS.GetSystemFonts();if(families.Length==0&&OS.GetName()=="Windows"){var output=new GArray();OS.Execute("powershell.exe",new[]{"-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",ProjectSettings.GlobalizePath("res://scripts/actors/core/system_fonts.ps1")},output);var text=new System.Text.StringBuilder();foreach(var line in output)text.Append(line.AsString());var installed=Json.ParseString(text.ToString());if(installed.VariantType==Variant.Type.Array){var names=installed.AsGodotArray();families=new string[names.Count];for(int i=0;i<families.Length;i++)families[i]=names[i].AsString();}}Array.Sort(families,StringComparer.Ordinal);ActorTextSettings.Families=families;return families;
    }
    public Settings values(Variant reference)
    {
        Resource? resource=reference.VariantType==Variant.Type.Object?reference.AsGodotObject() as Resource:null;if(IsScript(resource,"res://scripts/actors/core/actor_object_reference.gd"))resource=GD.Load<CSharpScript>("res://scripts/actors/core/ActorAnimation.cs").Call("resolve_reference",reference).As<Resource>();return IsScript(resource,"res://scripts/actors/core/actor_object_data.gd")?resource!.Get("values").AsGodotDictionary():new Settings();
    }
    public Font font(Settings settings)
    {
        string family=Get(settings,"font","Arial").AsString();bool bold=Get(settings,"bold",false).AsBool(),italic=Get(settings,"italic",false).AsBool();string key=family+":"+(bold?"true":"false")+":"+(italic?"true":"false");var fonts=ActorTextSettings.Fonts;if(!fonts.ContainsKey(key))fonts[key]=new SystemFont{FontNames=new[]{family},FontWeight=bold?700:400,FontItalic=italic};return fonts[key].As<Font>();
    }
    public void apply_label(Label label,Settings settings)
    {
        bool shadow=Get(settings,"shadow",false).AsBool();label.LabelSettings=new LabelSettings{Font=font(settings),FontSize=Math.Max(1,Get(settings,"font_size",48).AsInt32()),FontColor=Get(settings,"color",Colors.White).AsColor(),OutlineSize=Math.Max(0,Get(settings,"outline_size",0).AsInt32()),OutlineColor=Get(settings,"outline_color",Colors.Black).AsColor(),ShadowSize=shadow?1:0,ShadowColor=shadow?Get(settings,"shadow_color",new Color(0,0,0,.65f)).AsColor():Colors.Transparent,ShadowOffset=Get(settings,"shadow_offset",new Vector2(2,2)).AsVector2()};
    }
}
