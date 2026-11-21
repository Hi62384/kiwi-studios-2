using Godot;
using System;
using Settings = Godot.Collections.Dictionary;

public partial class EnvironmentWeatherRuntime : RefCounted
{
    public void update(Node3D runtime, Settings state, Camera3D? camera)
    {
        var emitters = runtime.Get("weather_particles").AsGodotDictionary();
        if (camera == null || !GodotObject.IsInstanceValid(camera))
        { foreach (var pair in emitters) if (pair.Value.As<GpuParticles3D>() is GpuParticles3D particle && GodotObject.IsInstanceValid(particle)) particle.Emitting = false; return; }
        foreach (string kind in new[] { "rain", "snow" })
        {
            double amount = Math.Clamp(state.TryGetValue(kind, out var value) ? value.AsDouble() : 0, 0, 1); var particles = emitters.TryGetValue(kind, out var found) ? found.As<GpuParticles3D>() : null;
            if (amount <= .015) { if (particles != null && GodotObject.IsInstanceValid(particles)) { particles.Emitting = false; particles.Visible = false; } continue; }
            if (particles == null || !GodotObject.IsInstanceValid(particles)) { particles = make(kind); emitters[kind] = particles; runtime.AddChild(particles); }
            particles.GlobalPosition = camera.GlobalPosition; particles.Emitting = amount > .015; particles.AmountRatio = (float)amount; particles.Visible = amount > .015;
        }
    }
    public GpuParticles3D make(string kind)
    {
        bool rain = kind == "rain"; var particles = new GpuParticles3D { Name = "Climate " + kind.Capitalize(), Amount = rain ? 1800 : 900, Lifetime = rain ? 1.35 : 7.0, LocalCoords = false, VisibilityAabb = new Aabb(new Vector3(-35, -35, -35), new Vector3(70, 70, 70)) };
        var process = new ParticleProcessMaterial { EmissionShape = ParticleProcessMaterial.EmissionShapeEnum.Box, EmissionBoxExtents = new Vector3(24, 14, 24), Direction = Vector3.Down, Spread = rain ? 2 : 32 };
        if (rain)
        {
            process.Gravity = new Vector3(0, -34, 0); process.InitialVelocityMin = 18; process.InitialVelocityMax = 27; process.ParticleFlagAlignY = true;
            particles.DrawPass1 = new CapsuleMesh { Radius = .012f, Height = .18f, Material = new StandardMaterial3D { AlbedoColor = new Color(.58f, .74f, .92f, .58f), Transparency = BaseMaterial3D.TransparencyEnum.Alpha, Roughness = .2f } };
        }
        else
        {
            process.Gravity = new Vector3(0, -1.2f, 0); process.InitialVelocityMin = .35f; process.InitialVelocityMax = 1.4f; process.TurbulenceEnabled = true; process.TurbulenceNoiseScale = 1.8f; process.TurbulenceInfluenceMin = .15f; process.TurbulenceInfluenceMax = .55f;
            particles.DrawPass1 = new SphereMesh { Radius = .035f, Height = .07f, Material = new StandardMaterial3D { AlbedoColor = new Color(.88f, .94f, 1, .9f), Transparency = BaseMaterial3D.TransparencyEnum.Alpha, Roughness = .9f } };
        }
        particles.ProcessMaterial = process; return particles;
    }
    public void release(Node3D runtime)
    {
        var emitters = runtime.Get("weather_particles").AsGodotDictionary();
        foreach (var pair in emitters)
            if (pair.Value.As<GpuParticles3D>() is GpuParticles3D particles && GodotObject.IsInstanceValid(particles)) { particles.Emitting = false; particles.ProcessMaterial = null; particles.DrawPass1 = null; }
        emitters.Clear();
    }
}
