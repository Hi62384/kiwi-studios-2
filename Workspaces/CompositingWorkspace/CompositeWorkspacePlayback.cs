using Godot;
using System;

public partial class CompositeWorkspacePlayback : RefCounted
{
    public void configure(Resource document, Timer timer, SpinBox spin, HSlider slider, double time)
    {
        double rate = document.Get("frame_rate").AsDouble(), duration = document.Get("duration").AsDouble();
        rate = double.IsFinite(rate) && rate > 0 ? rate : 24;
        duration = double.IsFinite(duration) && duration > 0 ? duration : 0;
        spin.MaxValue = duration; slider.MaxValue = duration; spin.Step = slider.Step = 1 / rate; timer.WaitTime = 1 / rate;
        seek(document, spin, slider, time);
    }

    public double seek(Resource document, SpinBox spin, HSlider slider, double time)
    {
        double duration = document.Get("duration").AsDouble();
        duration = double.IsFinite(duration) && duration > 0 ? duration : 0;
        double next = double.IsFinite(time) ? Math.Clamp(time, 0, duration) : 0;
        spin.SetValueNoSignal(next); slider.SetValueNoSignal(next); return next;
    }

    public double advance(Resource document, SpinBox spin, HSlider slider, double time)
    {
        double rate = document.Get("frame_rate").AsDouble(); rate = double.IsFinite(rate) && rate > 0 ? rate : 24;
        double next = time + 1 / rate;
        return seek(document, spin, slider, next > document.Get("duration").AsDouble() ? 0 : next);
    }

    public void toggle(Timer timer) { if (timer.IsStopped()) timer.Start(); else timer.Stop(); }
}
