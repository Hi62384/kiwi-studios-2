using Godot;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class WorldSeedOperations : RefCounted
{
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private static long Hash(params Variant[] values)=>unchecked((uint)GD.Hash(new GArray(values)));
    public Resource apply(Resource source,long seed)
    {
        var next=source.Call("copy").As<Resource>();long previous=source.Get("seed").AsInt64();next.Set("seed",seed);var settlements=next.Get("settlements").AsGodotArray();for(int index=0;index<settlements.Count;index++){var settlement=settlements[index].AsGodotDictionary();bool recipe=settlement["id"].AsString().StartsWith("recipe:",System.StringComparison.Ordinal);long oldDefault=recipe?Hash(previous,index):Hash(previous,settlement["id"]),replacement=recipe?Hash(seed,index):Hash(seed,settlement["id"]);if(Get(settlement,"seed",oldDefault).AsInt64()==oldDefault)settlement["seed"]=replacement;foreach(var value in Get(settlement,"districts",new GArray()).AsGodotArray()){var district=value.AsGodotDictionary();if(Get(district,"seed",previous).AsInt64()==previous)district["seed"]=seed;}}
        var forests=next.Get("forests").AsGodotArray();for(int index=0;index<forests.Count;index++){var forest=forests[index].AsGodotDictionary();long oldDefault=previous+index*101;if(forest["seed"].AsInt64()!=oldDefault)continue;long replacement=seed+index*101;forest["seed"]=replacement;foreach(var value in Get(forest,"variants",new GArray()).AsGodotArray()){var variant=value.AsGodotDictionary();var settings=variant["settings"].AsGodotDictionary();if(Get(settings,"seed",0).AsInt64()==Hash(oldDefault,variant["layer"],variant["kind"]))settings["seed"]=Hash(replacement,variant["layer"],variant["kind"]);}}
        foreach(var value in next.Get("prop_rules").AsGodotArray()){var rule=value.AsGodotDictionary();if(Get(rule,"seed",previous).AsInt64()==previous)rule["seed"]=seed;}foreach(var value in next.Get("regions").AsGodotArray()){var region=value.AsGodotDictionary();if(Get(region,"seed",0).AsInt64()==Hash(previous,region["id"]))region["seed"]=Hash(seed,region["id"]);}return next;
    }
}
