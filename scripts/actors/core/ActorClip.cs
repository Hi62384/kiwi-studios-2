using Godot;
using System;

[GlobalClass]
public partial class ActorClip : Resource
{
    [Export] public string id { get; set; } = "";
    [Export] public string actor_id { get; set; } = "";
    [Export] public double start_time { get; set; }
    [Export] public double duration { get; set; } = 5.0;
    [Export] public double source_offset { get; set; }
    [Export] public double playback_speed { get; set; } = 1.0;
    [Export] public int layer { get; set; }

    // Explicit arities preserve GDScript calls: C# optional arguments are not
    // included in Godot's generated method metadata.
    public static ActorClip create(Resource actor) => create(actor, 0.0, 5.0);
    public static ActorClip create(Resource actor, double start) => create(actor, start, 5.0);
    public static ActorClip create(Resource actor, double start, double length) => new()
    {
        id = new ActorDataOperations().new_id(), actor_id = actor.Get("id").AsString(),
        start_time = start, duration = Math.Max(length, 0.0)
    };
    public bool contains_time(double timeline_time) => timeline_time >= start_time && timeline_time < start_time + duration;
    public double local_time(double timeline_time) => source_offset + (timeline_time - start_time) * playback_speed;
}
