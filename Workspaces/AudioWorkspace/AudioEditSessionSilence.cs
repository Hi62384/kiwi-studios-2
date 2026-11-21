using Godot;
using System;
using GArray = Godot.Collections.Array;
using Settings = Godot.Collections.Dictionary;

public partial class AudioEditSessionOperations
{
    private static Settings SilenceError(string error) => new Settings { ["error"] = error };
    private static Variant Setting(Settings values, string key, Variant fallback = default) => values.TryGetValue(new StringName(key), out var value) ? value : fallback;
    public string silence_source_identity(GodotObject? actor)
    {
        if (actor == null) return "";
        var value = Setting(actor.Get("values").AsGodotDictionary(), "audio");
        string id = actor.Get("id").AsString();
        if (value.VariantType == Variant.Type.Object && value.AsGodotObject() is AudioStream stream) return id + ":" + stream.GetInstanceId();
        if (value.VariantType != Variant.Type.String || value.AsString().Length == 0) return "";
        string path = value.AsString();
        using var file = Godot.FileAccess.Open(path, Godot.FileAccess.ModeFlags.Read);
        return file == null ? "" : id + ":" + path + ":" + Godot.FileAccess.GetModifiedTime(path) + ":" + file.GetLength();
    }
    public GArray silence_geometry(GodotObject clip, GodotObject actor)
    {
        var result = new GArray();
        foreach (string key in new[] { "id", "actor_id", "start_time", "duration", "source_offset", "playback_speed", "layer" }) result.Add(clip.Get(key));
        foreach (string key in new[] { "id", "type_id", "display_name", "parent_id", "section_id", "show_timeline_children", "link_timeline_children", "schema_version" }) result.Add(actor.Get(key));
        return result;
    }
    public bool silence_plan_current(RefCounted plan, RefCounted owner)
    {
        if (plan.Get("_closed").AsBool() || plan.Get("_revision").AsInt64() != owner.Get("revision").AsInt64() || owner.Get("_before").VariantType != Variant.Type.Nil) return false;
        using var ownerReference = plan.Get("_owner").As<WeakRef>().GetRef();
        using var documentReference = plan.Get("_document").As<WeakRef>().GetRef();
        var document = Document(owner);
        if (ownerReference.AsGodotObject() != owner || documentReference.AsGodotObject() != document) return false;
        string id = plan.Get("_clip_id").AsString();
        var clip = document.Call("clip_for_id", id).AsGodotObject(); var actor = document.Call("actor_for_clip", id).AsGodotObject();
        return clip != null && actor != null && plan.Get("_geometry").AsGodotArray().RecursiveEqual(silence_geometry(clip, actor)) && plan.Get("_values").AsGodotDictionary().RecursiveEqual(actor.Get("values").AsGodotDictionary()) && plan.Get("_identity").AsString() == silence_source_identity(actor);
    }
    public string silence_reason(RefCounted owner, string id)
    {
        var document = Document(owner);
        var clip = document.Call("clip_for_id", id).AsGodotObject(); var actor = document.Call("actor_for_clip", id).AsGodotObject();
        if (clip == null || actor == null) return "The selected clip no longer exists.";
        var track = document.Call("track_for_clip", id).AsGodotDictionary();
        if (!can_edit(owner, id) || track.ContainsKey("frozen_track") || track.ContainsKey("frozen_source")) return "The selected clip is locked or frozen.";
        string reason = GD.Load<GDScript>("res://Workspaces/AudioWorkspace/audio_region_edit.gd").Call("unsupported_reason", clip, actor, "cut").AsString();
        if (reason.Length > 0) return reason;
        foreach (var raw in document.Get("takes").AsGodotArray()) if (Setting(raw.AsGodotDictionary(), "clip_id", "").AsString() == id) return "This clip belongs to a recording take. Duplicate it to an ordinary audio clip before silence cleanup so take controls remain intact.";
        foreach (var raw in document.Get("tracks").AsGodotArray())
        {
            var lane = raw.AsGodotDictionary(); var target = Setting(lane, "automation_target", new Settings()).AsGodotDictionary();
            if (Setting(target, "owner_kind", "").AsString() == "clip" && Setting(target, "owner_id", "").AsString() == id) return "Remove this clip's automation-lane binding before silence cleanup; a lane cannot target several resulting pieces.";
        }
        return "";
    }
    public Settings create_silence_plan(RefCounted owner, string id, GArray silences, double sourceDuration, double keep, string identity)
    {
        if (owner.Get("_before").VariantType != Variant.Type.Nil) return SilenceError("Finish the current adjustment before reviewing silence cleanup.");
        string reason = silence_reason(owner, id); if (reason.Length > 0) return SilenceError(reason);
        if (!double.IsFinite(sourceDuration) || sourceDuration <= 0 || sourceDuration > 86400.001 || !double.IsFinite(keep) || keep < 0 || keep > 10) return SilenceError("Invalid silence settings. Supported PCM sources are limited to 24 hours; other formats use the short-source decoder.");
        if (silences.Count > 2048) return SilenceError("More than 2048 quiet regions were detected. Increase the minimum pause duration and analyze again.");
        var document = Document(owner); var clip = document.Call("clip_for_id", id).AsGodotObject(); var actor = document.Call("actor_for_clip", id).AsGodotObject();
        if (identity.Length == 0 || identity != silence_source_identity(actor)) return SilenceError("The analyzed source changed or is missing. Analyze it again.");
        double offset = clip.Get("source_offset").AsDouble(), speed = clip.Get("playback_speed").AsDouble(), end = offset + clip.Get("duration").AsDouble() * speed;
        if (end > sourceDuration + .0001) return SilenceError("The clip extends beyond the analyzed source. Trim or render it before silence cleanup.");
        var plan = owner.Call("_new_silence_plan").As<RefCounted>();
        plan.Set("_owner", Variant.From(GodotObject.WeakRef(owner))); plan.Set("_document", Variant.From(GodotObject.WeakRef(document))); plan.Set("_revision", owner.Get("revision"));
        plan.Set("_clip_id", id); plan.Set("_identity", identity); plan.Set("_source_duration", sourceDuration);
        var geometry = silence_geometry(clip, actor); geometry.MakeReadOnly(); plan.Set("_geometry", geometry);
        plan.Set("_values", actor.Get("values").AsGodotDictionary().Duplicate(true));
        var regions = plan.Get("_regions").AsGodotArray(); var cuts = plan.Get("_cuts").AsGodotArray(); double previous = -1;
        foreach (var raw in silences)
        {
            if (raw.VariantType != Variant.Type.Dictionary) return SilenceError("Invalid quiet-region data. Analyze again.");
            var region = raw.AsGodotDictionary(); var firstRaw = Setting(region, "start"); var lastRaw = Setting(region, "end");
            if (firstRaw.VariantType is not Variant.Type.Float and not Variant.Type.Int || lastRaw.VariantType is not Variant.Type.Float and not Variant.Type.Int) return SilenceError("Invalid quiet-region data. Analyze again.");
            double first = firstRaw.AsDouble(), last = lastRaw.AsDouble();
            if (!double.IsFinite(first) || !double.IsFinite(last) || first < 0 || first < previous || last <= first || last > sourceDuration + .0001) return SilenceError("Quiet regions overlap or have invalid boundaries. Analyze again.");
            previous = last; double a = Math.Max(first, offset), b = Math.Min(last, end); if (b <= a) continue;
            double retained = Math.Min(keep * speed, b - a);
            var quiet = new Settings { ["start"] = a, ["end"] = b }; quiet.MakeReadOnly(); regions.Add(quiet);
            var cut = new Settings { ["start"] = a + retained * .5, ["end"] = b - retained * .5 }; cut.MakeReadOnly(); cuts.Add(cut);
        }
        regions.MakeReadOnly(); cuts.MakeReadOnly(); return new Settings { ["error"] = "", ["plan"] = plan };
    }
    public Settings preview_silence_plan(RefCounted owner, RefCounted? plan, GArray remove, string scope)
    {
        if (plan == null || !silence_plan_current(plan, owner)) return SilenceError("This cleanup plan is stale or cancelled. Analyze and review again.");
        string id = plan.Get("_clip_id").AsString(), reason = silence_reason(owner, id);
        if (reason.Length > 0) return SilenceError(reason);
        if (scope is not "clip" and not "track_following") return SilenceError("Choose an explicit cleanup scope.");
        var document = Document(owner); var clip = document.Call("clip_for_id", id).AsGodotObject(); var actor = document.Call("actor_for_clip", id).AsGodotObject();
        var chosen = new System.Collections.Generic.HashSet<int>(); var planCuts = plan.Get("_cuts").AsGodotArray(); var cuts = new GArray();
        foreach (var index in remove)
        {
            if (index.VariantType != Variant.Type.Int || index.AsInt64() < 0 || index.AsInt64() >= planCuts.Count || !chosen.Add(index.AsInt32())) return SilenceError("Invalid or duplicate review choice.");
        }
        for (int i = 0; i < planCuts.Count; ++i)
        {
            var cut = planCuts[i].AsGodotDictionary(); if (chosen.Contains(i) && cut["end"].AsDouble() - cut["start"].AsDouble() > .000001) cuts.Add(cut);
        }
        var ranges = new GArray(); double offset = clip.Get("source_offset").AsDouble(), cursor = offset, speed = clip.Get("playback_speed").AsDouble(), duration = clip.Get("duration").AsDouble(), end = offset + duration * speed, removed = 0;
        var values = actor.Get("values").AsGodotDictionary(); double fadeIn = Setting(values, "fade_in", 0.0).AsDouble(), fadeOut = Setting(values, "fade_out", 0.0).AsDouble();
        if (!double.IsFinite(fadeIn) || !double.IsFinite(fadeOut) || fadeIn < 0 || fadeOut < 0) return SilenceError("Invalid clip fades.");
        foreach (var raw in cuts)
        {
            var cut = raw.AsGodotDictionary(); double start = cut["start"].AsDouble(), last = cut["end"].AsDouble();
            if ((fadeIn > 0 && start < offset + fadeIn * speed - .000001) || (fadeOut > 0 && last > end - fadeOut * speed + .000001)) return SilenceError("A chosen removal intersects an existing clip fade. Keep that region or render the fade first.");
            if (start > cursor + .000001) ranges.Add(new Settings { ["start"] = cursor, ["end"] = start });
            cursor = last; removed += (last - start) / speed;
        }
        if (cursor < end - .000001) ranges.Add(new Settings { ["start"] = cursor, ["end"] = end });
        if (ranges.Count == 0) return SilenceError("The entire clip would be removed. Keep at least one region, retain a pause, or delete the clip manually.");
        var moved = new Godot.Collections.Array<string>(); double startTime = clip.Get("start_time").AsDouble(), oldEnd = startTime + duration;
        string trackId = Setting(values, "track_id", "").AsString();
        if (scope == "track_following" && removed > 0) foreach (var raw in document.Get("clips").AsGodotArray())
        {
            var other = raw.AsGodotObject(); string otherId = other.Get("id").AsString();
            var track = document.Call("track_for_clip", otherId).AsGodotDictionary();
            if (otherId == id || Setting(track, "id", "").AsString() != trackId) continue;
            double otherStart = other.Get("start_time").AsDouble();
            if (otherStart < oldEnd - .000001 && otherStart + other.Get("duration").AsDouble() > startTime + .000001) return SilenceError("Another clip overlaps this clip on the same track. Use selected-clip-only scope or resolve the overlap first.");
            if (otherStart >= oldEnd - .000001)
            {
                if (!can_edit(owner, otherId) || track.ContainsKey("frozen_track") || track.ContainsKey("frozen_source")) return SilenceError("A following clip is locked or frozen. No clips were changed.");
                moved.Add(otherId);
            }
        }
        return new Settings { ["error"] = "", ["ranges"] = ranges, ["cuts"] = cuts, ["removed"] = removed, ["remaining"] = duration - removed, ["moved_ids"] = moved, ["scope"] = scope };
    }
    public Settings apply_silence_plan(RefCounted owner, RefCounted plan, GArray remove, string scope)
    {
        var review = preview_silence_plan(owner, plan, remove, scope);
        if (review["error"].AsString().Length > 0) return review;
        double removed = review["removed"].AsDouble();
        if (removed <= .000001) return new Settings { ["error"] = "", ["changed"] = false, ["removed"] = 0.0 };
        var document = Document(owner); string id = plan.Get("_clip_id").AsString();
        var clip = document.Call("clip_for_id", id).AsGodotObject(); var actor = document.Call("actor_for_clip", id).AsGodotObject();
        var clips = document.Get("clips").AsGodotArray(); var actors = document.Get("actors").AsGodotArray();
        int index = clips.IndexOf(clip); double at = clip.Get("start_time").AsDouble(), offset = clip.Get("source_offset").AsDouble(), speed = clip.Get("playback_speed").AsDouble(), end = offset + clip.Get("duration").AsDouble() * speed;
        var parts = new GArray(); var values = actor.Get("values").AsGodotDictionary(); var regionEdit = GD.Load<GDScript>("res://Workspaces/AudioWorkspace/audio_region_edit.gd");
        foreach (var raw in review["ranges"].AsGodotArray())
        {
            var interval = raw.AsGodotDictionary(); double first = interval["start"].AsDouble(), last = interval["end"].AsDouble();
            var part = regionEdit.Call("_piece", actor, clip, at, first, (last - first) / speed).AsGodotDictionary();
            var partActor = part["actor"].AsGodotObject(); var partClip = part["clip"].AsGodotObject();
            if (parts.Count == 0) { partActor.Set("id", actor.Get("id")); partClip.Set("id", clip.Get("id")); partClip.Set("actor_id", actor.Get("id")); }
            var partValues = partActor.Get("values").AsGodotDictionary(); double duration = partClip.Get("duration").AsDouble();
            partValues[new StringName("fade_in")] = Math.Abs(first - offset) < .000001 ? Setting(values, "fade_in", 0.0).AsDouble() : Math.Min(.003, duration * .1);
            partValues[new StringName("fade_out")] = Math.Abs(last - end) < .000001 ? Setting(values, "fade_out", 0.0).AsDouble() : Math.Min(.005, duration * .1);
            parts.Add(part); at += duration;
        }
        plan.Set("_closed", true);
        begin(owner, "Reviewed silence cleanup");
        clips.RemoveAt(index); actors.RemoveAt(index); var selected = owner.Get("selected_ids").AsGodotArray(); selected.Clear();
        for (int i = 0; i < parts.Count; ++i) { var part = parts[i].AsGodotDictionary(); clips.Insert(index + i, part["clip"]); actors.Insert(index + i, part["actor"]); selected.Add(part["clip"].AsGodotObject().Get("id")); }
        foreach (var moved in review["moved_ids"].AsGodotArray()) { var other = document.Call("clip_for_id", moved).AsGodotObject(); other.Set("start_time", other.Get("start_time").AsDouble() - removed); }
        commit(owner); owner.EmitSignal("selection_changed");
        return new Settings { ["error"] = "", ["changed"] = true, ["removed"] = removed, ["clip_ids"] = selected.Duplicate(), ["moved_ids"] = review["moved_ids"] };
    }
    public Settings silence_boundary(RefCounted owner, RefCounted plan, GArray remove, int region)
    {
        var review = preview_silence_plan(owner, plan, remove, "clip");
        if (review["error"].AsString().Length > 0) return review;
        var cuts = plan.Get("_cuts").AsGodotArray();
        if (region < 0 || region >= cuts.Count || !remove.Contains(region)) return SilenceError("Select a region marked Remove to audition its proposed boundary.");
        var cut = cuts[region].AsGodotDictionary(); double start = cut["start"].AsDouble(), end = cut["end"].AsDouble();
        if (end - start <= .000001) return SilenceError("This region removes no time with the retained-pause setting.");
        var document = Document(owner); var clip = document.Call("clip_for_id", plan.Get("_clip_id")).AsGodotObject(); double speed = clip.Get("playback_speed").AsDouble();
        var left = new Settings { ["start"] = 0.0, ["end"] = 0.0 }; var right = new Settings { ["start"] = 0.0, ["end"] = 0.0 }; double fadeOut = 0, fadeIn = 0;
        foreach (var raw in review["ranges"].AsGodotArray())
        {
            var interval = raw.AsGodotDictionary(); double a = interval["start"].AsDouble(), b = interval["end"].AsDouble();
            if (Math.Abs(b - start) < .000001) { left = new Settings { ["start"] = Math.Max(a, b - .35 * speed), ["end"] = b }; fadeOut = Math.Min(.005, (b - a) / speed * .1); }
            if (Math.Abs(a - end) < .000001) { right = new Settings { ["start"] = a, ["end"] = Math.Min(b, a + .35 * speed) }; fadeIn = Math.Min(.003, (b - a) / speed * .1); }
        }
        if (left["end"].AsDouble() <= left["start"].AsDouble() && right["end"].AsDouble() <= right["start"].AsDouble()) return SilenceError("This boundary joins another removal. Audition an outside boundary instead.");
        var values = document.Call("actor_for_clip", plan.Get("_clip_id")).AsGodotObject().Get("values").AsGodotDictionary();
        return new Settings { ["error"] = "", ["left"] = left, ["right"] = right, ["speed"] = speed, ["fade_in"] = fadeIn, ["fade_out"] = fadeOut, ["source"] = Setting(values, "audio"), ["fade_curve"] = Setting(values, "fade_curve", "linear") };
    }
}
