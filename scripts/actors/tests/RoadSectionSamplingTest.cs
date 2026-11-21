using Godot;
using System;
using Settings=Godot.Collections.Dictionary;

public partial class RoadSectionSamplingTest : Node
{
    public override void _Ready()
    {
        try
        {
            var points=new[]{new Vector3(0,.2f,48),new Vector3(8,.15f,48),new Vector3(16.01161f,.109772f,48),new Vector3(16,.105489f,48)};
            var clean=RoadSectionOperations.StableSectionSamples(points);if(clean[0]!=points[0]||clean[^1]!=points[^1]||clean.Length!=3)throw new Exception("Junction sample cleanup changed exact endpoints or retained the folded tail.");
            var section=new RoadSectionOperations();var output=section.build(points,section.defaults("Residential Street"),new Settings());var meshes=new ModelMeshOperations();int count=0;
            foreach(string role in new[]{"surface","shoulders","sidewalks","curbs","markings"})if(output.TryGetValue(role,out var value)){var errors=meshes.validate(value.As<Resource>(),true);if(errors.Length>0)throw new Exception(role+": "+string.Join(", ",errors));count++;}
            if(count<4)throw new Exception("Road detail geometry missing.");GD.Print("PASS Snapped junction overshoot preserves endpoints and produces valid solid road details");GetTree().Quit();
        }
        catch(Exception error){GD.PushError(error.ToString());GetTree().Quit(1);}
    }
}
