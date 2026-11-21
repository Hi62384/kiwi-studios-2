using Godot;
using System;
using GArray = Godot.Collections.Array;
using Settings = Godot.Collections.Dictionary;

public partial class AudioAutomationRecordingOperations : RefCounted
{
    private readonly AudioAutomationLaneOperations _lanes = new();
    private static Variant Get(Settings d, string key, Variant fallback = default) => d.TryGetValue(key, out var value) ? value : fallback;
    private static string Mode(RefCounted o) => o.Get("mode").AsString();
    private static RefCounted? Session(RefCounted o) => o.Get("session").As<RefCounted>();
    private static GodotObject? Playback(RefCounted o) => o.Get("playback").AsGodotObject();
    private static Settings Target(RefCounted o) => o.Get("target").AsGodotDictionary();
    private static Settings Segment(RefCounted o) => o.Get("_segment").AsGodotDictionary();
    private static GArray Segments(RefCounted o) => o.Get("_segments").AsGodotArray();
    private static bool Playing(RefCounted o) => Playback(o)?.Get("playing").AsBool() ?? false;
    public void bind(RefCounted o, RefCounted session, GodotObject transport) { discard(o, "Read: choose a target and a mode to record."); o.Set("session", session); o.Set("playback", transport); o.Set("target", new Settings { ["owner_kind"] = "master", ["owner_id"] = "", ["effect_id"] = "", ["parameter"] = "volume_db" }); o.Set("lane_id", ""); o.Set("control_value", read_value(o, transport.Get("position").AsDouble())); }
    public Settings info(RefCounted o) { var session = Session(o); return session == null ? new Settings() : _lanes.resolve(session.Get("document").AsGodotObject(), Target(o)); }
    public bool editable(RefCounted o)
    {
        var resolved = info(o); if (resolved.Count == 0 || resolved["locked"].AsBool()) return false; string lane = o.Get("lane_id").AsString();
        if (lane.Length > 0) { var document = Session(o)!.Get("document").AsGodotObject(); if (!_lanes.editable(document, lane)) return false; var binding = Get(document.Call("track_for_id", lane).AsGodotDictionary(), "automation_target", new Settings()).AsGodotDictionary(); if (_lanes.key(binding) != _lanes.key(Target(o))) return false; } return true;
    }
    public bool matches(RefCounted o, Settings candidate) => _lanes.key(candidate) == _lanes.key(Target(o));
    public void choose(RefCounted o, Settings candidate, string sourceLane) { finish(o, "Target changed"); o.Set("target", candidate.Duplicate(true)); o.Set("lane_id", sourceLane); o.Set("control_value", read_value(o, Playback(o)?.Get("position").AsDouble() ?? 0)); announce(o, "Read: " + Get(info(o), "label", "Target unavailable").AsString() + ". Choose Write, Touch or Latch to arm this parameter."); }
    public void set_mode(RefCounted o, string mode)
    {
        if (mode is not "Read" and not "Write" and not "Touch" and not "Latch") return; finish(o, "Mode changed"); if (mode != "Read" && !editable(o)) { announce(o, "Read: unlock the owner and linked lane before recording automation."); return; } o.Set("mode", mode);
        if (mode == "Read") announce(o, "Read: existing curves play; no automation is recorded."); else { announce(o, mode + " armed for " + Get(info(o), "label", "parameter").AsString() + ". Returns to Read after the pass."); if (Playing(o)) transport_changed(o, true, Playback(o)!.Get("position").AsDouble()); }
    }
    public double read_value(RefCounted o, double seconds) { var resolved = info(o); return resolved.Count == 0 ? o.Get("control_value").AsDouble() : _lanes.value(_lanes.points(resolved), Math.Max(0, seconds - resolved["offset"].AsDouble()), resolved["fallback"].AsDouble()); }
    public double display_value(RefCounted o, double seconds) => Mode(o) != "Read" && (o.Get("touching").AsBool() || Segment(o).Count > 0 || !Playing(o)) ? o.Get("control_value").AsDouble() : read_value(o, seconds);
    public void transport_changed(RefCounted o, bool playing, double seconds) { if (!playing) { if (o.Get("active").AsBool()) finish(o, "Transport stopped"); return; } if (Mode(o) != "Read" && !o.Get("active").AsBool() && (Mode(o) == "Write" || o.Get("touching").AsBool() || o.Get("_latched").AsBool())) if (begin_pass(o, seconds)) start_segment(o, seconds); }
    public void touch(RefCounted o, double seconds)
    {
        if (Mode(o) == "Read" || !editable(o)) return; if (Playing(o) && (Mode(o) == "Touch" || (Mode(o) == "Latch" && !o.Get("_latched").AsBool()))) o.Set("control_value", read_value(o, seconds)); o.Set("touching", true); if (Mode(o) == "Latch") o.Set("_latched", true); if (!Playing(o)) return; if (!o.Get("active").AsBool() && !begin_pass(o, seconds)) return; if (Segment(o).Count == 0) start_segment(o, seconds);
    }
    private static string Format(double value) => value.ToString("F3", System.Globalization.CultureInfo.InvariantCulture);
    public void change(RefCounted o, double value, double seconds)
    {
        if (Mode(o) == "Read" || !double.IsFinite(value) || !editable(o)) return; var resolved = info(o); if (Playing(o) && (!o.Get("touching").AsBool() || !o.Get("active").AsBool())) touch(o, seconds); if (Mode(o) == "Read") return;
        o.Set("control_value", Math.Clamp(value, resolved["minimum"].AsDouble(), resolved["maximum"].AsDouble())); if (!Playing(o)) { announce(o, Mode(o) + " armed: start value " + Format(o.Get("control_value").AsDouble()) + ". Press Play to record."); return; } if (o.Get("active").AsBool() && Segment(o).Count > 0) { sample(o, seconds, false); monitor_value(o); }
    }
    public void release(RefCounted o, double seconds) { o.Set("touching", false); if (!o.Get("active").AsBool()) return; if (Mode(o) == "Touch") { end_segment(o, seconds); restore_monitor(o); announce(o, "Touch: released to the original curve; the pending pass saves on Stop."); } else if (Mode(o) == "Latch") announce(o, "Latch: holding " + Format(o.Get("control_value").AsDouble()) + " until Stop."); }
    private static bool DocumentCurrent(RefCounted o) { var session = Session(o); return session != null && session.Get("document").AsGodotObject() == o.Get("_document").AsGodotObject() && session.Get("revision").AsInt64() == o.Get("_revision").AsInt64(); }
    public void tick(RefCounted o, double seconds, bool playing)
    {
        if (!o.Get("active").AsBool()) { if (playing && Mode(o) == "Write") transport_changed(o, true, seconds); return; }
        if (!DocumentCurrent(o) || !editable(o)) { discard(o, "Read: pending automation cancelled because the document, target or lock changed."); return; }
        if (!playing) { finish(o, "Transport stopped"); return; } if (seconds + .0001 < o.Get("_last_position").AsDouble()) { finish(o, "Loop wrap or backward seek ended the pass"); return; } if (seconds - o.Get("_started_at").AsDouble() >= 3600) { finish(o, "One-hour pass limit reached"); return; }
        o.Set("_last_position", seconds); if (Segment(o).Count == 0 && (Mode(o) == "Write" || o.Get("touching").AsBool() || o.Get("_latched").AsBool())) start_segment(o, seconds); if (Segment(o).Count > 0) { sample(o, seconds, false); if (o.Get("active").AsBool()) monitor_value(o); }
    }
    public void document_changed(RefCounted o) { if (o.Get("committing").AsBool()) return; if (o.Get("active").AsBool()) discard(o, "Read: another edit cancelled the pending automation pass; that edit was preserved."); else if (Mode(o) != "Read" && !editable(o)) discard(o, "Read: automation target is locked or unavailable."); }
    public bool has_pending(RefCounted o) => o.Get("active").AsBool() && Segments(o).Count > 0;
    private static void Reset(RefCounted o) { o.Set("active", false); o.Set("touching", false); o.Set("_latched", false); o.Set("mode", "Read"); }
    private static void Clear(RefCounted o) { Segments(o).Clear(); o.Set("_segment", new Settings()); o.Set("_document", default(Variant)); o.Set("_original", new GArray()); }
    public bool finish(RefCounted o, string reason)
    {
        if (!o.Get("active").AsBool()) { bool armed = Mode(o) != "Read"; Reset(o); restore_monitor(o); if (armed) announce(o, "Read: " + reason + ". No automation changes to save."); return false; }
        var session = Session(o)!; if (!DocumentCurrent(o) || !editable(o) || session.Get("_before").VariantType != Variant.Type.Nil) { discard(o, "Read: pending automation cancelled because another edit or lock changed its target."); return false; }
        end_segment(o, o.Get("_last_position").AsDouble()); var original = o.Get("_original").AsGodotArray(); var result = original.Duplicate(true); foreach (var raw in Segments(o)) result = splice(o, result, raw.AsGodotDictionary()); string label = Get(info(o), "label", "parameter").AsString(), recordedMode = Mode(o); bool changed = Segments(o).Count > 0 && !result.RecursiveEqual(original);
        restore_monitor(o); Reset(o); Clear(o); if (result.Count > 10000) { announce(o, "Read: pass was not saved because it would exceed 10,000 points. Simplify this curve first."); return false; }
        if (changed)
        {
            var resolved = info(o); o.Set("committing", true);
            try { using var edits = new AudioEditSessionOperations(); edits.begin(session, "Record " + recordedMode + " automation: " + label); var owner = resolved["owner"].AsGodotDictionary(); var curves = Get(owner, "automation", new Settings()).AsGodotDictionary(); curves[resolved["parameter"].AsString()] = result; owner["automation"] = curves; edits.commit(session); }
            finally { o.Set("committing", false); }
            announce(o, "Read: " + reason + ". Saved " + label + " as one undo action; replay to hear the committed curve.");
        }
        else announce(o, "Read: " + reason + ". No automation changes to save."); return changed;
    }
    public void discard(RefCounted o, string reason) { Reset(o); restore_monitor(o); Clear(o); announce(o, reason); }
    public void announce(RefCounted o, string message) { o.Set("message", message); o.EmitSignal("status_changed", message); }
    public bool begin_pass(RefCounted o, double seconds)
    {
        var session = Session(o)!; if (!editable(o) || session.Get("_before").VariantType != Variant.Type.Nil) { discard(o, "Read: finish the current edit and unlock the target before recording automation."); return false; }
        var resolved = info(o); var original = _lanes.points(resolved).Duplicate(true); var ordered = new System.Collections.Generic.List<Variant>(); foreach (var point in original) ordered.Add(point); ordered.Sort((a,b)=>a.AsGodotDictionary()["time"].AsDouble().CompareTo(b.AsGodotDictionary()["time"].AsDouble())); original.Clear(); foreach(var point in ordered)original.Add(point); o.Set("_original", original);
        if (original.Count > 10000 - 32 - 4) { discard(o, "Read: this curve is too dense to record safely. Simplify it before another pass."); return false; }
        o.Set("_document", session.Get("document")); o.Set("_revision", session.Get("revision")); o.Set("_fallback", resolved["fallback"]); o.Set("_tolerance", Math.Max(.00001, (resolved["maximum"].AsDouble() - resolved["minimum"].AsDouble()) * .0005)); Segments(o).Clear(); o.Set("_segment", new Settings()); o.Set("_last_position", seconds); o.Set("_started_at", seconds); o.Set("active", true);
        var playback = Playback(o)!; var target = Target(o); bool live = !playback.Get("exact_preview_active").AsBool() && !playback.Get("exact_pending").AsBool() && !playback.Get("exact_required").AsBool() && Get(target, "effect_id", "").AsString().Length == 0 && Get(target, "owner_kind", "").AsString() is "track" or "master"; o.Set("_live_monitor", live);
        announce(o, Mode(o) + " recording " + resolved["label"].AsString() + ". " + (live ? "Native mixer monitoring is live." : "Capture only: the current rendered/clip/effect audio stays unchanged until replay.")); return true;
    }
    public void start_segment(RefCounted o, double seconds)
    {
        var resolved = info(o); double local = seconds - resolved["offset"].AsDouble(); if (local < 0) return; if (local > resolved["duration"].AsDouble()) { finish(o, "Target range ended"); return; }
        var segments = Segments(o); if (segments.Count >= 64) { finish(o, "64-gesture limit reached"); return; } if (point_count(o) + 2 > Math.Min(2048, 10000 - o.Get("_original").AsGodotArray().Count - (segments.Count + 1) * 34)) { finish(o, "Safe curve point budget reached"); return; }
        var segment = new Settings { ["points"] = new GArray { new Settings { ["time"] = local, ["value"] = o.Get("control_value"), ["curve"] = "linear" } } }; o.Set("_segment", segment); segments.Add(segment); o.Set("_last_position", seconds); monitor_value(o);
    }
    public void sample(RefCounted o, double seconds, bool force)
    {
        var segment = Segment(o); if (segment.Count == 0) return; var resolved = info(o); double local = seconds - resolved["offset"].AsDouble(); if (local < 0) return; local = Math.Min(local, resolved["duration"].AsDouble()); var points = segment["points"].AsGodotArray(); var last = points[points.Count - 1].AsGodotDictionary(); double lastTime = last["time"].AsDouble(); if (local < lastTime) return;
        bool ended = seconds - resolved["offset"].AsDouble() >= resolved["duration"].AsDouble(); if (!force && !ended && local - lastTime < 1.0 / 30) return; var point = new Settings { ["time"] = local, ["value"] = o.Get("control_value"), ["curve"] = "linear" }; if (Math.Abs(local - lastTime) <= .0000001) { points[points.Count - 1] = point; return; }
        if (points.Count >= 2) { var previous = points[points.Count - 2].AsGodotDictionary(); double fraction = (lastTime - previous["time"].AsDouble()) / Math.Max(.000001, local - previous["time"].AsDouble()), expected = Mathf.Lerp(previous["value"].AsDouble(), o.Get("control_value").AsDouble(), fraction); if (Math.Abs(expected - last["value"].AsDouble()) <= o.Get("_tolerance").AsDouble()) points[points.Count - 1] = point; else points.Add(point); } else points.Add(point);
        if (!force) { int limit = Math.Min(2048, 10000 - o.Get("_original").AsGodotArray().Count - Segments(o).Count * 34); if (point_count(o) >= limit - 1) finish(o, "Safe curve point budget reached"); else if (ended) finish(o, "Target range ended"); }
    }
    public int point_count(RefCounted o) { int count = 0; foreach (var raw in Segments(o)) count += raw.AsGodotDictionary()["points"].AsGodotArray().Count; return count; }
    public void end_segment(RefCounted o, double seconds) { if (Segment(o).Count == 0) return; sample(o, seconds, true); o.Set("_segment", new Settings()); }
    public void monitor_value(RefCounted o)
    {
        if (!o.Get("_live_monitor").AsBool() || !o.Get("active").AsBool() || Segment(o).Count == 0) return; if (o.Get("_monitor").AsGodotObject() == null) o.Set("_monitor", o.Get("_document").AsGodotObject().Call("snapshot")); var monitor = o.Get("_monitor").AsGodotObject(); var resolved = _lanes.resolve(monitor, Target(o)); if (resolved.Count == 0) return;
        var owner = resolved["owner"].AsGodotDictionary(); var curves = Get(owner, "automation", new Settings()).AsGodotDictionary(); curves[resolved["parameter"].AsString()] = new GArray { new Settings { ["time"] = 0.0, ["value"] = o.Get("control_value"), ["curve"] = "hold" } }; owner["automation"] = curves; var playback = Playback(o)!; playback.Set("document", monitor); playback.Call("synchronize");
    }
    public void restore_monitor(RefCounted o)
    {
        var previous = o.Get("_monitor").AsGodotObject(); o.Set("_monitor", default(Variant)); var playback = Playback(o); if (playback == null) return; var session = Session(o); bool invalidated = o.Get("_document").AsGodotObject() != null && session != null && !DocumentCurrent(o);
        if (invalidated) { playback.Set("document", session!.Get("document")); playback.Call("stop", false); } else if (previous != null && playback.Get("document").AsGodotObject() == previous) { playback.Set("document", session != null ? session.Get("document") : o.Get("_document")); playback.Call("synchronize"); }
    }
    public Settings original_point(RefCounted o, GArray original, double seconds, string curve) => new Settings { ["time"] = seconds, ["value"] = _lanes.value(original, seconds, o.Get("_fallback").AsDouble()), ["curve"] = curve };
    public string curve_at(GArray points, double seconds) { if (points.Count == 0 || seconds < points[0].AsGodotDictionary()["time"].AsDouble()) return "hold"; for (int i = 1; i < points.Count; ++i) if (seconds < points[i].AsGodotDictionary()["time"].AsDouble()) return Get(points[i - 1].AsGodotDictionary(), "curve", "linear").AsString(); return "hold"; }
    public GArray splice(RefCounted o, GArray original, Settings segment)
    {
        var captured = segment["points"].AsGodotArray(); if (captured.Count == 0) return original; double start = captured[0].AsGodotDictionary()["time"].AsDouble(), end = captured[captured.Count - 1].AsGodotDictionary()["time"].AsDouble(), left = Math.Max(0, start - .0001), right = end + .0001; var result = new GArray();
        foreach (var raw in original) { var point = raw.AsGodotDictionary(); if (point["time"].AsDouble() < left) result.Add(point.Duplicate(true)); }
        if (start > 0) { if (result.Count > 0 && Get(result[result.Count - 1].AsGodotDictionary(), "curve", "linear").AsString() == "smooth") { var previous = result[result.Count - 1].AsGodotDictionary(); double time = previous["time"].AsDouble(); previous["curve"] = "linear"; for (int i = 1; i < 16; ++i) result.Add(original_point(o, original, Mathf.Lerp(time, left, i / 16.0), "linear")); } result.Add(original_point(o, original, left, "hold")); }
        foreach (var raw in captured.Duplicate(true)) result.Add(raw); result[result.Count - 1].AsGodotDictionary()["curve"] = "hold"; string curve = curve_at(original, right); result.Add(original_point(o, original, right, curve == "smooth" ? "linear" : curve)); double next = -1;
        foreach (var raw in original) { var point = raw.AsGodotDictionary(); if (point["time"].AsDouble() > right) { next = point["time"].AsDouble(); break; } }
        if (curve == "smooth" && next > right) for (int i = 1; i < 16; ++i) result.Add(original_point(o, original, Mathf.Lerp(right, next, i / 16.0), "linear")); foreach (var raw in original) { var point = raw.AsGodotDictionary(); if (point["time"].AsDouble() > right) result.Add(point.Duplicate(true)); } return result;
    }
}
