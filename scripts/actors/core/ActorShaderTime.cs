using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class ActorShaderTime : RefCounted
{
    public static Settings prepare(string source) => new ActorShaderTimeOperations().prepare(source);
    public static bool _identifier_start(string character) => new ActorShaderTimeOperations().identifier_start(character);
    public static bool _identifier_part(string character) => new ActorShaderTimeOperations().identifier_part(character);
}
