using Godot;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;
[GlobalClass]
public partial class KiwiAudioTemplates : RefCounted
{
    public static string[] names()
    {using var operations=new AudioTemplateOperations();return operations.names();}
    public static KiwiAudioDocument create(string label)
    {using var operations=new AudioTemplateOperations();return (KiwiAudioDocument)operations.create(label);}
    public static string[] chain_names()
    {using var operations=new AudioTemplateOperations();return operations.chain_names();}
    public static GArray chain(string name)
    {using var operations=new AudioTemplateOperations();return operations.chain(name);}
    public static Settings _fx(string type,Settings values)
    {using var operations=new AudioTemplateOperations();return operations.effect(type,values);}
    public static Settings export_presets()
    {using var operations=new AudioTemplateOperations();return operations.export_presets();}
    public static RefCounted _native()=>Engine.GetSingleton("KiwiNativeServices").Call("service","audio_templates").As<RefCounted>();
}
