using Godot;
using System;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class EnvironmentAssetNativeTest : Node
{
    private int _checks;
    private void Check(bool value,string title) {if(!value) throw new Exception(title); _checks++; GD.Print("PASS ",title);}
    public override void _Ready()
    {
        try
        {
            using var assets=new EnvironmentAssetOperations(); using var stable=new EnvironmentDataHash();
            var first=new Settings {["b"]=new GArray {1,2},["a"]=.7}; var second=new Settings {["a"]=.7,["b"]=new GArray {1,2}};
            Check(stable.value(first)==stable.value(second),"Canonical data signatures ignore dictionary insertion order");
            second["b"]=new GArray {1,3}; Check(stable.value(first)!=stable.value(second),"Canonical data signatures detect nested edits");
            var gradient=new Gradient(); gradient.SetColor(0,Colors.Red); long before=stable.value(gradient); gradient.SetColor(0,Colors.Blue);
            Check(stable.value(gradient)!=before,"Canonical signatures track editable resource values");
            var image=Image.CreateEmpty(2,2,false,Image.Format.Rgba8); var texture=ImageTexture.CreateFromImage(image); var textureCopy=ImageTexture.CreateFromImage(image);
            Check(stable.value(texture)==stable.value(textureCopy),"Equivalent image texture dimensions preserve generated-data signatures");
            var cache=new Settings(); var revisions=new Settings(); var materials=new Settings();
            string path="user://asset_original.tres"; string dependency=ProjectSettings.GlobalizePath(path).Replace('\\','/').SimplifyPath();
            cache["user://dependent.tres"]=new Settings {["dependencies"]=new GArray {dependency}}; materials[1]=new StandardMaterial3D();
            assets.invalidate(path,cache,revisions,materials);
            Check(cache.Count==0 && materials.Count==0 && revisions[path].AsInt64()==1 && revisions["user://dependent.tres"].AsInt64()==1,"Asset invalidation removes dependents and updates source revisions");
            Check(assets.load_parts("user://does_not_exist.glb",cache,revisions)["error"].AsString().StartsWith("Missing model:"),"Missing model loads return actionable errors");
            var noise=new NoiseTexture2D {Noise=new FastNoiseLite {Frequency=.01f}};
            long stamp=assets.content_stamp(noise,new Settings(),0,revisions); ((FastNoiseLite)noise.Noise).Frequency=.04f;
            Check(assets.content_stamp(noise,new Settings(),0,revisions)!=stamp,"Asset signatures detect nested procedural texture changes");
            GD.Print("ENVIRONMENT NATIVE ASSETS: ",_checks," checks"); GetTree().Quit();
        }
        catch(Exception error) {GD.PushError(error.ToString()); GetTree().Quit(1);}
    }
}
