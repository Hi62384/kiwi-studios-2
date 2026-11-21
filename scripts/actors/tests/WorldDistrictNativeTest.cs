using Godot;
using System;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class WorldDistrictNativeTest : Node
{
    public override void _Ready()
    {
        try
        {
            var operations=new WorldDistrictOperations();var polygon=new[]{new Vector2(-10,-10),new Vector2(10,-10),new Vector2(10,10),new Vector2(-10,10)};int checks=0;
            void Check(bool value,string text){if(!value)throw new Exception(text);checks++;GD.Print("PASS ",text);}
            var first=new Settings {["id"]="first",["category"]="Industrial",["polygon"]=polygon,["enabled"]=true,["density"]=1.0};var last=new Settings {["id"]="last",["category"]="Park/Green Space",["polygon"]=polygon,["enabled"]=true,["density"]=1.0};
            var settlement=new Settings {["id"]="town",["districts"]=new GArray {first,last},["block_overrides"]=new Settings()};var block=new Settings {["id"]="block",["polygon"]=polygon};
            var result=operations.rules(block,settlement);Check(result["district_id"].AsString()=="last"&&result["density"].AsDouble()==0&&!operations.accept(new Settings {["id"]="lot"},result),"Later park districts override previous districts and reserve open land");
            settlement["block_overrides"].AsGodotDictionary()["block"]=new Settings {["district_id"]="first",["density"]=.4};result=operations.rules(block,settlement);Check(result["district_id"].AsString()=="first"&&result["density"].AsDouble()==.4,"Explicit block assignments override district overlap priority");
            int accepted=0;for(int i=0;i<1000;i++){var plot=new Settings {["id"]=i.ToString()};bool choice=operations.accept(plot,result);if(choice)accepted++;if(choice!=operations.accept(plot,result))throw new Exception("Unstable density");}Check(accepted>300&&accepted<500,"Density decisions are stable by parcel identity and preserve their requested distribution");
            Check(operations.validate(settlement).Length==0,"Valid district assignment and override pass validation");first["height_min"]=8;first["height_max"]=1;Check(operations.validate(settlement).Length>0,"Inverted building height ranges are rejected");
            Check(!operations.simple(new[]{Vector2.Zero,Vector2.Right,Vector2.Zero,Vector2.Down}),"Repeated and intersecting polygon edges are rejected");
            var effective=operations.effective(settlement,new Settings {["id"]="other",["height_min"]=3});Check(effective["id"].AsString()=="town"&&!effective.ContainsKey("districts")&&!effective.ContainsKey("block_overrides")&&settlement.ContainsKey("districts"),"Effective settings retain settlement identity without mutating the authored source");
            GD.Print("NATIVE WORLD DISTRICTS: ",checks," checks");GetTree().Quit();
        }
        catch(Exception error){GD.PushError(error.ToString());GetTree().Quit(1);}
    }
}
