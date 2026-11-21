using Godot;
using System;
using GArray=Godot.Collections.Array;
using Settings=Godot.Collections.Dictionary;
public partial class AudioTemplateOperations:RefCounted
{
    private const string ChainJson="""
{"Voice cleanup":[["highpass",{"frequency":75}],["hum_remove",{"frequency":60,"harmonics":3}],["noise_reduce",{"reduction":8,"floor":-50}],["compressor",{"threshold":-20,"ratio":3}],["deesser",{"intensity":0.4,"amount":0.3}]],"Telephone voice":[["telephone",{}],["saturate",{"drive":0.18,"output":-2}]],"Radio voice":[["highpass",{"frequency":180}],["lowpass",{"frequency":5000}],["compressor",{"threshold":-24,"ratio":6}],["bitcrusher",{"bits":12,"reduction":1}]],"Robot voice":[["ring",{"frequency":80,"mix":0.9}],["delay",{"time":0.05,"mix":0.15,"feedback":0.25}]],"Monster voice":[["pitch",{"semitones":-7}],["saturate",{"drive":0.25,"output":-5}],["reverb",{"size":0.7,"mix":0.2}]],"Underwater voice":[["lowpass",{"frequency":700,"q":0.8}],["chorus",{"rate":0.3,"depth":3,"mix":0.3}]],"Distant voice":[["highpass",{"frequency":200}],["lowpass",{"frequency":3500}],["gain",{"db":-9}],["reverb",{"size":0.8,"mix":0.45}]],"Warm tape-style":[["saturate",{"drive":0.15,"output":-3}],["lowpass",{"frequency":12000}],["vibrato",{"rate":0.4,"depth":0.04}]],"Bright master":[["highpass",{"frequency":30}],["high_shelf",{"frequency":7000,"db":1.5}],["compressor",{"threshold":-15,"ratio":2}],["limiter",{"ceiling":-1}]]}
""";
    public string[] names()=>new[]{"Sound Effect Design","Voice Editing","YouTube Commentary","Podcast","Music Production","Cinematic Soundtrack","Cartoon Sound Design","Game Audio","Ambient Soundscape"};
    public string[] chain_names()=>new[]{"Voice cleanup","Telephone voice","Radio voice","Robot voice","Monster voice","Underwater voice","Distant voice","Warm tape-style","Bright master"};
    public Settings effect(string type,Settings values){using var effects=new AudioEffectsOperations();var result=effects.create(type);var parameters=result["parameters"].AsGodotDictionary();foreach(var key in values.Keys)parameters[key]=values[key];return result;}
    public GArray chain(string name){var result=new GArray();var catalog=Json.ParseString(ChainJson).AsGodotDictionary();if(catalog.TryGetValue(name,out var rows))foreach(var raw in rows.AsGodotArray()){var row=raw.AsGodotArray();result.Add(effect(row[0].AsString(),row[1].AsGodotDictionary()));}return result;}
    public RefCounted create(string label)
    {
        var document=new KiwiAudioDocument();document.Set("title",label);(string Name,string Kind)[] tracks=label switch
        {
            "Sound Effect Design"=>new[]{("Transient","audio"),("Body","audio"),("Texture","audio"),("Tail","audio")},
            "Voice Editing"=>new[]{("Dialogue","audio"),("Alternate Takes","audio")},
            "YouTube Commentary"=>new[]{("Commentary","audio"),("Music","audio"),("Sound Effects","audio")},
            "Podcast"=>new[]{("Host","audio"),("Guest","audio"),("Theme","audio")},
            "Music Production"=>new[]{("Drums","instrument"),("Bass","instrument"),("Chords","instrument"),("Lead","instrument")},
            "Cinematic Soundtrack"=>new[]{("Low Strings","instrument"),("Pads","instrument"),("Percussion","instrument"),("Impacts","audio")},
            "Cartoon Sound Design"=>new[]{("Foley","audio"),("Cartoon Effects","audio"),("Music Cues","instrument"),("Dialogue","audio")},
            "Game Audio"=>new[]{("UI","audio"),("Movement","audio"),("Impacts","audio"),("Ambience","audio")},
            "Ambient Soundscape"=>new[]{("Texture","audio"),("Environment","audio"),("Pad","instrument"),("Details","audio")},
            _=>Array.Empty<(string,string)>()
        };
        if(label=="Cinematic Soundtrack")document.Set("tempo",84);else if(label=="Ambient Soundscape")document.Set("tempo",72);using var documents=new AudioDocumentOperations();foreach(var entry in tracks){var track=documents.add_track(document,entry.Name,entry.Kind);if(entry.Name is "Dialogue" or "Commentary" or "Host" or "Guest")track["effects"]=chain("Voice cleanup");else if(entry.Name is "Music" or "Theme" or "Pad" or "Pads")track["volume_db"]=-9.0;if(entry.Name=="Drums")track["instrument"]=new Settings{["id"]="drums"};else if(entry.Name=="Bass")track["instrument"]=new Settings{["id"]="bass"};else if(entry.Kind=="instrument")track["instrument"]=new Settings{["id"]=entry.Name is "Pads" or "Pad"?"pad":"piano"};}
        var sources=document.Get("tracks").AsGodotArray().Duplicate();var bus=documents.add_track(document,label is "Voice Editing" or "Podcast" or "YouTube Commentary"?"Voice bus":label is "Sound Effect Design" or "Cartoon Sound Design" or "Game Audio"?"Design bus":"Music bus","group");bus["effects"]=new GArray{effect("compressor",new Settings{["threshold"]=-18,["ratio"]=2}),effect("limiter",new Settings{["ceiling"]=-2})};foreach(var raw in sources){var track=raw.AsGodotDictionary();string name=track["name"].AsString();if(name=="Alternate Takes")track["mute"]=true;if(label is "Podcast" or "YouTube Commentary"&&name is "Theme" or "Music" or "Sound Effects")continue;track["output"]=bus["id"];track["group"]=bus["id"];}
        if(label is "Music Production" or "Cinematic Soundtrack" or "Ambient Soundscape" or "Sound Effect Design" or "Cartoon Sound Design"){var space=documents.add_track(document,"Space return","group");space["effects"]=new GArray{effect("reverb",new Settings{["size"]=label=="Ambient Soundscape"?.8:.5,["mix"]=1.0})};space["volume_db"]=-9;foreach(var raw in sources){var track=raw.AsGodotDictionary();if(track["name"].AsString() is not ("Bass" or "Drums" or "Dialogue" or "Foley" or "Transient"))track["sends"]=new GArray{new Settings{["target"]=space["id"],["volume_db"]=-15.0}};}}
        if(label=="Music Production"){var drums=documents.add_track(document,"Drum bus","group");drums["output"]=bus["id"];drums["effects"]=new GArray{effect("compressor",new Settings{["threshold"]=-16,["ratio"]=3})};sources[0].AsGodotDictionary()["output"]=drums["id"];sources[0].AsGodotDictionary()["group"]=drums["id"];}
        document.Get("master").AsGodotDictionary()["effects"]=new GArray{effect("highpass",new Settings{["frequency"]=25}),effect("limiter",new Settings{["ceiling"]=-1})};document.Set("workspace_state",new Settings{["bottom_open"]=true,["bottom_tab"]=label=="Music Production"?2:0});return document;
    }
    public Settings export_presets()=>new(){["YouTube Video"]=new Settings{["sample_rate"]=48000,["target_lufs"]=-14,["normalize"]=false},["Podcast / Voice"]=new Settings{["sample_rate"]=48000,["target_lufs"]=-16,["normalize"]=false},["Music"]=new Settings{["sample_rate"]=44100,["target_lufs"]=-14,["normalize"]=false},["Game SFX"]=new Settings{["sample_rate"]=48000,["target_lufs"]=-18,["normalize"]=false},["Animation Dialogue"]=new Settings{["sample_rate"]=48000,["target_lufs"]=-18,["normalize"]=false},["High Quality"]=new Settings{["sample_rate"]=48000,["bit_depth"]=24,["normalize"]=false}};
}
