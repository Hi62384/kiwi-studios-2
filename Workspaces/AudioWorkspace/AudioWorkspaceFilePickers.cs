using Godot;
using System;
using GArray=Godot.Collections.Array;
using Settings=Godot.Collections.Dictionary;
public partial class AudioWorkspaceOperations
{
    public Settings picker_context(Control o)=>new(){["session"]=Session(o),["revision"]=Session(o).Get("revision")};
    private static bool PickerCurrent(Control o,Settings context)=>Session(o)==context["session"].AsGodotObject()&&Session(o).Get("revision").AsInt64()==context["revision"].AsInt64();
    public Resource file_property(string[] extensions){var property=new ActorProperty();property.Set("options",new Settings{["extensions"]=extensions});return property;}
    public Resource audio_property()=>file_property(new[]{"wav","mp3","ogg","flac"});
    public void complete_import(Control o,Settings context,string chosen,bool empty){if(!PickerCurrent(o,context)){notice(o,"The composition changed while choosing a file. Repeat this action in the intended document.");return;}if(chosen.Length==0||empty)return;queue_import(o,chosen,Position(o),Session(o).Get("selected_track").AsString());}
    public void queue_import(Control o,string chosen,double at,string trackId)
    {
        if(_frameLanes.is_lane(Document(o).Call("track_for_id",trackId).AsGodotDictionary())){notice(o,"Select an audio or instrument track before importing audio.");return;}Work(o,"import",unchecked((long)Document(o).GetInstanceId()),job=>{job.Call("update",0,"Reading audio duration");var seconds=GD.Load<CSharpScript>("res://scripts/actors/core/ActorAudio.cs").Call("file_duration",chosen,job);return new Settings{["path"]=chosen,["seconds"]=seconds,["at"]=at,["track"]=trackId};},false);
    }
    public void complete_open(Control o,string chosen,bool empty){if(chosen.Length==0||empty)return;var tabs=o.GetTree().GetFirstNodeInGroup("actor_scene_tabs");if(tabs!=null&&tabs.HasMethod("open_audio"))tabs.Call("open_audio",chosen);else open_source(o,chosen,new Settings(),false,false);}
    public void batch_effects(Control o)
    {
        if(Items(Session(o),"selected_ids").Count==0)return;var effects=Get(effect_owner(o),"effects",new GArray()).AsGodotArray().Duplicate(true);SessionAction(o,"Apply effect chain to selected clips",()=>{using var edits=new AudioEditSessionOperations();using var crypto=new Crypto();foreach(var id in Items(Session(o),"selected_ids")){if(!edits.can_edit(Session(o),id.AsString()))continue;var copied=effects.Duplicate(true);foreach(var raw in copied)raw.AsGodotDictionary()["id"]=Convert.ToHexString(crypto.GenerateRandomBytes(16)).ToLowerInvariant();Document(o).Call("actor_for_clip",id).AsGodotObject().Get("values").AsGodotDictionary()[new StringName("effects")]=copied;}});
    }
    public void complete_effect_impulse(Control o,Settings context,Settings effect,string chosen,bool empty){if(chosen.Length==0||empty)return;if(!PickerCurrent(o,context)){notice(o,"The composition changed while choosing the impulse. Choose it again.");return;}SessionAction(o,"Choose convolution impulse",()=>effect["parameters"].AsGodotDictionary()["impulse"]=chosen);refresh_effects(o);}
    public void add_effect_dialog(Control o)
    {
        if(!effect_editable(o))return;var dialog=window(o,"Add effect",new Vector2I(620,520));var host=dialog["host"].As<Node>();var windowNode=dialog["window"].As<Window>();var search=new LineEdit{PlaceholderText="Search effects\u2026"};host.AddChild(search);var scroller=new ScrollContainer{SizeFlagsVertical=Control.SizeFlags.ExpandFill};host.AddChild(scroller);var choices=new VBoxContainer{SizeFlagsHorizontal=Control.SizeFlags.ExpandFill};scroller.AddChild(choices);void Rebuild(){clear(choices);using var library=new AudioLibraryOperations();foreach(var definition in library.ranked_effects(Field<Control>(o,"library"))){string labelText=definition["label"].AsString(),category=definition["category"].AsString();if(search.Text.Length>0&&!(labelText+" "+category).ToLowerInvariant().Contains(search.Text.ToLowerInvariant()))continue;ActionButton(choices,labelText+" · "+category+(definition["realtime"].AsBool()?"  [live]":"  [offline]"),()=>{if(!effect_editable(o))return;Field<Control>(o,"library").Call("remember_effect",definition["id"].AsString());var owner=effect_owner(o);SessionAction(o,"Add effect",()=>{var stack=Get(owner,"effects",new GArray()).AsGodotArray();using var effects=new AudioEffectsOperations();stack.Add(effects.create(definition["id"].AsString()));owner["effects"]=stack;});windowNode.QueueFree();});}}search.TextChanged+=_=>Rebuild();Rebuild();
    }
    public void effect_chain_dialog(Control o)
    {
        if(!effect_editable(o))return;var dialog=window(o,"Effect chain",new Vector2I(400,430));var host=dialog["host"].As<Node>();var windowNode=dialog["window"].As<Window>();using var templates=new AudioTemplateOperations();foreach(string name in templates.chain_names())ActionButton(host,name,()=>{var owner=effect_owner(o);SessionAction(o,"Apply effect chain",()=>{using var chains=new AudioTemplateOperations();owner["effects"]=chains.chain(name);});windowNode.QueueFree();});
    }
}
