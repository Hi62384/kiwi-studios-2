using Godot;
using GArray = Godot.Collections.Array;

public partial class AudioEditSessionOperations : RefCounted
{
    private static GodotObject Document(RefCounted owner) => owner.Get("document").AsGodotObject();
    public void begin(RefCounted owner, string label)
    {
        if (owner.Get("_before").VariantType != Variant.Type.Nil) return;
        owner.Set("_before", Document(owner).Call("snapshot"));
        owner.Set("_pending_preview", false);
        owner.Set("_label", label);
    }
    public void preview(RefCounted owner)
    {
        if (owner.Get("_before").VariantType != Variant.Type.Nil) owner.Set("_pending_preview", true);
        owner.Set("revision", owner.Get("revision").AsInt64() + 1);
        owner.EmitSignal("changed");
    }
    public void cancel(RefCounted owner)
    {
        var previous = owner.Get("_before");
        if (previous.VariantType == Variant.Type.Nil) return;
        owner.Set("_before", default(Variant));
        restore(owner, previous.AsGodotObject());
    }
    public void restore(RefCounted owner, GodotObject value)
    {
        var document = value.Call("snapshot").AsGodotObject();
        owner.Set("document", document);
        var ids = owner.Get("selected_ids").AsGodotArray();
        for (int i = ids.Count - 1; i >= 0; --i)
            if (document.Call("clip_for_id", ids[i]).VariantType == Variant.Type.Nil) ids.RemoveAt(i);
        string track = owner.Get("selected_track").AsString();
        if (track.Length > 0 && document.Call("track_for_id", track).AsGodotDictionary().Count == 0)
        {
            var tracks = document.Get("tracks").AsGodotArray();
            owner.Set("selected_track", tracks.Count > 0 ? tracks[0].AsGodotDictionary()["id"].AsString() : "");
        }
        owner.Set("dirty", true);
        owner.Set("revision", owner.Get("revision").AsInt64() + 1);
        owner.EmitSignal("changed");
        owner.EmitSignal("selection_changed");
    }
    public void undo(RefCounted owner)
    {
        var history = owner.Get("history").As<UndoRedo>();
        if (owner.Get("_before").VariantType != Variant.Type.Nil)
        {
            if (owner.Get("_pending_preview").AsBool()) { owner.Call("commit"); history.Undo(); }
            else cancel(owner);
            return;
        }
        if (history.HasUndo()) history.Undo();
    }
    public void redo(RefCounted owner)
    {
        if (owner.Get("_before").VariantType != Variant.Type.Nil) { cancel(owner); return; }
        var history = owner.Get("history").As<UndoRedo>();
        if (history.HasRedo()) history.Redo();
    }
    public void select(RefCounted owner, string id, bool additive)
    {
        var ids = owner.Get("selected_ids").AsGodotArray();
        if (!additive) ids.Clear();
        var document = Document(owner);
        if (document.Call("clip_for_id", id).VariantType != Variant.Type.Nil)
        {
            if (additive && ids.Contains(id)) ids.Remove(id); else ids.Add(id);
            var track = document.Call("track_for_clip", id).AsGodotDictionary();
            owner.Set("selected_track", track.TryGetValue("id", out var found) ? found.AsString() : "");
        }
        owner.EmitSignal("selection_changed");
    }
    public void select_all(RefCounted owner)
    {
        var ids = owner.Get("selected_ids").AsGodotArray();
        ids.Clear();
        foreach (var clip in Document(owner).Get("clips").AsGodotArray()) ids.Add(clip.AsGodotObject().Get("id"));
        owner.EmitSignal("selection_changed");
    }
    public Variant primary(RefCounted owner, bool actor)
    {
        var ids = owner.Get("selected_ids").AsGodotArray();
        return ids.Count == 0 ? default : Document(owner).Call(actor ? "actor_for_clip" : "clip_for_id", ids[ids.Count - 1]);
    }
    public bool can_edit(RefCounted owner, string id)
    {
        var track = Document(owner).Call("track_for_clip", id).AsGodotDictionary();
        return track.Count > 0 && !(track.TryGetValue("locked", out var locked) && locked.AsBool());
    }
    public bool edit_clip(RefCounted owner, string id, Godot.Collections.Dictionary changes)
    {
        if (!can_edit(owner, id)) return false;
        var document = Document(owner);
        var clip = document.Call("clip_for_id", id).AsGodotObject();
        if (clip == null) return false;
        var actor = document.Call("actor_for_clip", id).AsGodotObject();
        var values = actor.Get("values").AsGodotDictionary();
        double Read(string key) => changes.TryGetValue(key, out var changed) ? changed.AsDouble() : clip.Get(key).AsDouble();
        double start = Read("start_time"), duration = Read("duration"), offset = Read("source_offset"), speed = Read("playback_speed");
        if (!double.IsFinite(start) || !double.IsFinite(duration) || !double.IsFinite(offset) || !double.IsFinite(speed)) return false;
        if (start < 0 || duration < 1.0 / 192000 || offset < 0 || speed < .05 || speed > 16) return false;
        double length = values.TryGetValue(new StringName("source_duration"), out var source) ? source.AsDouble() : 0;
        bool loop = values.TryGetValue(new StringName("loop"), out var looping) && looping.AsBool();
        if (!loop && length > 0 && offset + duration * speed > length + .0001) return false;
        string? trackId = null;
        if (changes.TryGetValue("track_id", out var targetId))
        {
            trackId = targetId.AsString();
            var target = document.Call("track_for_id", trackId).AsGodotDictionary();
            if (target.Count == 0 || (target.TryGetValue("locked", out var locked) && locked.AsBool()) || (target.TryGetValue("kind", out var kind) && kind.AsString() == "automation")) return false;
        }
        clip.Set("start_time", start);
        clip.Set("duration", duration);
        clip.Set("source_offset", offset);
        clip.Set("playback_speed", speed);
        if (trackId != null) values[new StringName("track_id")] = trackId;
        return true;
    }
    public void set_clip_value(RefCounted owner, StringName key, Variant value)
    {
        bool nested = owner.Get("_before").VariantType != Variant.Type.Nil;
        begin(owner, "Change " + key.ToString().Capitalize());
        foreach (var id in owner.Get("selected_ids").AsGodotArray())
            if (can_edit(owner, id.AsString())) Document(owner).Call("actor_for_clip", id).AsGodotObject().Get("values").AsGodotDictionary()[key] = value;
        if (!nested) owner.Call("commit");
    }
    public void crossfade_selected(RefCounted owner, double seconds)
    {
        bool nested = owner.Get("_before").VariantType != Variant.Type.Nil;
        begin(owner, "Crossfade clips");
        var document = Document(owner);
        foreach (var id in owner.Get("selected_ids").AsGodotArray())
        {
            if (!can_edit(owner, id.AsString())) continue;
            var clip = document.Call("clip_for_id", id).AsGodotObject();
            var values = document.Call("actor_for_clip", id).AsGodotObject().Get("values").AsGodotDictionary();
            double fade = System.Math.Min(seconds, clip.Get("duration").AsDouble() * .5);
            values[new StringName("fade_in")] = fade;
            values[new StringName("fade_out")] = fade;
            values[new StringName("fade_curve")] = "equal_power";
        }
        if (!nested) owner.Call("commit");
    }
    public void move_selected(RefCounted owner, double delta, int trackDelta)
    {
        var document = Document(owner);
        var ids = owner.Get("selected_ids").AsGodotArray();
        double earliest = double.PositiveInfinity;
        foreach (var id in ids) if (can_edit(owner, id.AsString())) earliest = System.Math.Min(earliest, document.Call("clip_for_id", id).AsGodotObject().Get("start_time").AsDouble());
        if (double.IsFinite(earliest)) delta = System.Math.Max(delta, -earliest);
        var tracks = document.Get("tracks").AsGodotArray();
        foreach (var id in ids)
        {
            if (!can_edit(owner, id.AsString())) continue;
            var clip = document.Call("clip_for_id", id).AsGodotObject();
            var track = document.Call("track_for_clip", id);
            int index = tracks.IndexOf(track);
            edit_clip(owner, id.AsString(), new Godot.Collections.Dictionary {
                ["start_time"] = System.Math.Max(0, clip.Get("start_time").AsDouble() + delta),
                ["track_id"] = tracks[System.Math.Clamp(index + trackDelta, 0, tracks.Count - 1)].AsGodotDictionary()["id"] });
        }
    }
    public bool set_track_value(RefCounted owner, string id, string key, Variant value)
    {
        var document = Document(owner);
        var track = document.Call("track_for_id", id).AsGodotDictionary();
        if (track.Count == 0 || (track.TryGetValue("locked", out var locked) && locked.AsBool())) return false;
        bool Automation(string target) { var t = document.Call("track_for_id", target).AsGodotDictionary(); return t.TryGetValue("kind", out var kind) && kind.AsString() == "automation"; }
        if (Automation(id) && key is "mute" or "solo" or "volume_db" or "pan" or "output" or "sends") return false;
        if (key == "output" && Automation(value.AsString())) return false;
        if (key == "sends" && value.VariantType == Variant.Type.Array)
            foreach (var raw in value.AsGodotArray())
                if (raw.VariantType == Variant.Type.Dictionary && raw.AsGodotDictionary().TryGetValue("target", out var target) && Automation(target.AsString())) return false;
        bool nested = owner.Get("_before").VariantType != Variant.Type.Nil;
        begin(owner, "Change track " + key);
        var previous = track.TryGetValue(key, out var old) ? old : default;
        track[key] = value;
        if (document.Call("validate").AsStringArray().Length > 0)
        {
            track[key] = previous;
            if (!nested) owner.Set("_before", default(Variant));
            return false;
        }
        if (!nested) owner.Call("commit");
        return true;
    }
    public string set_conductor(RefCounted owner, double bpm, Vector2I signature, GArray tempos, GArray meters)
    {
        if (owner.Get("_before").VariantType != Variant.Type.Nil) return "Finish the current edit before changing the conductor.";
        using var conductor = new AudioConductorOperations();
        string problem = conductor.validate(bpm, signature, tempos, meters);
        if (problem.Length > 0) return problem;
        var document = Document(owner);
        if (bpm == document.Get("tempo").AsDouble() && signature == document.Get("time_signature").AsVector2I() && tempos.RecursiveEqual(document.Get("tempo_points").AsGodotArray()) && meters.RecursiveEqual(document.Get("meter_points").AsGodotArray())) return "";
        var tempoCopy = tempos.Duplicate(true);
        var meterCopy = meters.Duplicate(true);
        begin(owner, "Edit project conductor");
        if (document.Get("note_base_tempo").AsDouble() == 0) document.Set("note_base_tempo", document.Get("tempo"));
        if (document.Get("note_base_meter").AsVector2I() == Vector2I.Zero) document.Set("note_base_meter", document.Get("time_signature"));
        document.Set("tempo", bpm);
        document.Set("time_signature", signature);
        var targetTempos = document.Get("tempo_points").AsGodotArray();
        targetTempos.Clear();
        foreach (var point in tempoCopy) targetTempos.Add(point);
        var targetMeters = document.Get("meter_points").AsGodotArray();
        targetMeters.Clear();
        foreach (var point in meterCopy) targetMeters.Add(point);
        owner.Call("commit");
        return "";
    }
    public void add_automation(Godot.Collections.Dictionary owner, string parameter, double at, double value)
    {
        var curves = owner.TryGetValue("automation", out var existing) ? existing.AsGodotDictionary() : new Godot.Collections.Dictionary();
        var points = curves.TryGetValue(parameter, out var curve) ? curve.AsGodotArray() : new GArray();
        points.Add(new Godot.Collections.Dictionary { ["time"] = System.Math.Max(0, at), ["value"] = value, ["curve"] = "linear" });
        var ordered = new System.Collections.Generic.List<Variant>();
        foreach (var point in points) ordered.Add(point);
        ordered.Sort((a, b) => a.AsGodotDictionary()["time"].AsDouble().CompareTo(b.AsGodotDictionary()["time"].AsDouble()));
        points.Clear();
        foreach (var point in ordered) points.Add(point);
        curves[parameter] = points;
        owner["automation"] = curves;
    }
    public void open(RefCounted owner, GodotObject document)
    {
        owner.Set("_before", default(Variant));
        owner.Set("_label", "");
        owner.Set("_pending_preview", false);
        owner.Set("document", document);
        var tracks = document.Get("tracks").AsGodotArray();
        if (tracks.Count == 0) document.Call("add_track");
        owner.Get("history").As<UndoRedo>().ClearHistory();
        owner.Get("_history_footprints").AsGodotArray().Clear();
        owner.Get("_history_actions").AsGodotArray().Clear();
        owner.Set("history_pruned_actions", 0);
        var ids = owner.Get("selected_ids").AsGodotArray();
        ids.Clear();
        var state = document.Get("workspace_state").AsGodotDictionary();
        string fallback = tracks[0].AsGodotDictionary()["id"].AsString();
        string track = state.TryGetValue("selected_track", out var savedTrack) ? savedTrack.AsString() : fallback;
        if (track.Length > 0 && document.Call("track_for_id", track).AsGodotDictionary().Count == 0) track = fallback;
        owner.Set("selected_track", track);
        if (state.TryGetValue("selected_ids", out var savedIds))
            foreach (var id in savedIds.AsGodotArray())
                if (document.Call("clip_for_id", id.AsString()).VariantType != Variant.Type.Nil) ids.Add(id.AsString());
        owner.Set("revision", owner.Get("revision").AsInt64() + 1);
        owner.Set("dirty", false);
        owner.EmitSignal("changed");
    }
    public GArray shifted_curve(GArray points, double offset, double fallback)
    {
        var output = new GArray();
        if (points.Count == 0) return output;
        var ordered = new System.Collections.Generic.List<Godot.Collections.Dictionary>();
        foreach (var raw in points.Duplicate(true)) ordered.Add(raw.AsGodotDictionary());
        ordered.Sort((a, b) => a["time"].AsDouble().CompareTo(b["time"].AsDouble()));
        var active = ordered[0];
        Godot.Collections.Dictionary? following = null;
        foreach (var point in ordered)
        {
            if (point["time"].AsDouble() <= offset) active = point;
            else { following = point; break; }
        }
        var sorted = new GArray();
        foreach (var point in ordered) sorted.Add(point);
        using var effects = new AudioEffectsOperations();
        string curve = active.TryGetValue("curve", out var currentCurve) ? currentCurve.AsString() : "linear";
        var initial = new Godot.Collections.Dictionary { ["time"] = 0.0, ["value"] = effects.automation_value(sorted, offset, fallback), ["curve"] = curve };
        output.Add(initial);
        if (curve == "smooth" && following != null && offset > active["time"].AsDouble())
        {
            initial["curve"] = "linear";
            for (int i = 1; i < 16; ++i)
            {
                double time = Mathf.Lerp(offset, following["time"].AsDouble(), i / 16.0);
                output.Add(new Godot.Collections.Dictionary { ["time"] = time - offset, ["value"] = effects.automation_value(sorted, time, fallback), ["curve"] = "linear" });
            }
        }
        foreach (var point in ordered)
            if (point["time"].AsDouble() > offset)
            {
                var copy = point.Duplicate(true);
                copy["time"] = point["time"].AsDouble() - offset;
                output.Add(copy);
            }
        return output;
    }
    public void shift_owner_automation(Godot.Collections.Dictionary owner, double offset)
    {
        var automation = owner.TryGetValue("automation", out var curves) ? curves.AsGodotDictionary() : new Godot.Collections.Dictionary();
        var parameters = owner.TryGetValue("parameters", out var raw) ? raw.AsGodotDictionary() : owner;
        foreach (var key in automation.Keys)
            automation[key] = shifted_curve(automation[key].AsGodotArray(), offset, parameters.TryGetValue(key, out var fallback) ? fallback.AsDouble() : 0);
        owner["automation"] = automation;
        if (owner.TryGetValue("effects", out var effects)) foreach (var effect in effects.AsGodotArray()) shift_owner_automation(effect.AsGodotDictionary(), offset);
    }
    public void add_track(RefCounted owner, string kind, string label)
    {
        bool nested = owner.Get("_before").VariantType != Variant.Type.Nil;
        begin(owner, "Add track");
        var track = Document(owner).Call("add_track", label.Length > 0 ? label : kind.Capitalize(), kind).AsGodotDictionary();
        owner.Set("selected_track", track["id"]);
        if (!nested) owner.Call("commit");
    }
    public void delete_track(RefCounted owner, string id)
    {
        var document = Document(owner);
        var track = document.Call("track_for_id", id).AsGodotDictionary();
        if (track.Count == 0 || (track.TryGetValue("locked", out var locked) && locked.AsBool())) return;
        bool nested = owner.Get("_before").VariantType != Variant.Type.Nil;
        begin(owner, "Delete track");
        var clips = document.Get("clips").AsGodotArray();
        var actors = document.Get("actors").AsGodotArray();
        for (int i = clips.Count - 1; i >= 0; --i)
        {
            var values = actors[i].AsGodotObject().Get("values").AsGodotDictionary();
            if (values.TryGetValue(new StringName("track_id"), out var actorTrack) && actorTrack.AsString() == id) { clips.RemoveAt(i); actors.RemoveAt(i); }
        }
        var tracks = document.Get("tracks").AsGodotArray();
        for (int i = tracks.Count - 1; i >= 0; --i)
            if (tracks[i].AsGodotDictionary()["id"].AsString() == id) { tracks.RemoveAt(i); break; }
        foreach (var raw in tracks)
        {
            var other = raw.AsGodotDictionary();
            if (other.TryGetValue("output", out var output) && output.AsString() == id) other["output"] = "";
            var sends = other.TryGetValue("sends", out var existing) ? existing.AsGodotArray().Duplicate() : new GArray();
            for (int i = sends.Count - 1; i >= 0; --i)
                if (sends[i].AsGodotDictionary().TryGetValue("target", out var target) && target.AsString() == id) sends.RemoveAt(i);
            other["sends"] = sends;
        }
        if (tracks.Count == 0) document.Call("add_track");
        owner.Set("selected_track", tracks[0].AsGodotDictionary()["id"]);
        if (!nested) owner.Call("commit");
    }
    public Variant insert_source(RefCounted owner, Variant value, double at, string trackId, string label)
    {
        var document = Document(owner);
        string target = trackId.Length > 0 ? trackId : owner.Get("selected_track").AsString();
        var track = document.Call("track_for_id", target).AsGodotDictionary();
        if (track.Count == 0 || (track.TryGetValue("locked", out var locked) && locked.AsBool()) || (track.TryGetValue("kind", out var kind) && kind.AsString() == "automation")) return default;
        bool nested = owner.Get("_before").VariantType != Variant.Type.Nil;
        begin(owner, "Import audio");
        var result = document.Call("insert_source", value, target, at, label);
        if (result.VariantType == Variant.Type.Nil)
        {
            if (!nested) owner.Set("_before", default(Variant));
            return default;
        }
        var ids = owner.Get("selected_ids").AsGodotArray();
        ids.Clear(); ids.Add(result.AsGodotObject().Get("id"));
        owner.Set("selected_track", target);
        if (!nested) owner.Call("commit");
        owner.EmitSignal("selection_changed");
        return result;
    }
    public void delete_selected(RefCounted owner, bool ripple)
    {
        var ids = owner.Get("selected_ids").AsGodotArray();
        if (ids.Count == 0) return;
        bool nested = owner.Get("_before").VariantType != Variant.Type.Nil;
        begin(owner, ripple ? "Ripple delete clips" : "Delete clips");
        var document = Document(owner);
        var removed = new System.Collections.Generic.List<(string Track, double Start, double Duration)>();
        foreach (var id in ids)
        {
            var clip = document.Call("clip_for_id", id).AsGodotObject();
            if (clip != null && can_edit(owner, id.AsString()))
                removed.Add((document.Call("track_for_clip", id).AsGodotDictionary()["id"].AsString(), clip.Get("start_time").AsDouble(), clip.Get("duration").AsDouble()));
        }
        removed.Sort((a, b) => b.Start.CompareTo(a.Start));
        var clips = document.Get("clips").AsGodotArray();
        var actors = document.Get("actors").AsGodotArray();
        for (int i = clips.Count - 1; i >= 0; --i)
        {
            var id = clips[i].AsGodotObject().Get("id");
            if (ids.Contains(id) && can_edit(owner, id.AsString())) { clips.RemoveAt(i); actors.RemoveAt(i); }
        }
        if (ripple) foreach (var region in removed) foreach (var raw in clips)
        {
            var clip = raw.AsGodotObject();
            var track = document.Call("track_for_clip", clip.Get("id")).AsGodotDictionary();
            if (track.TryGetValue("id", out var id) && id.AsString() == region.Track && clip.Get("start_time").AsDouble() >= region.Start + region.Duration - .000001)
                clip.Set("start_time", System.Math.Max(0, clip.Get("start_time").AsDouble() - region.Duration));
        }
        ids.Clear();
        if (!nested) owner.Call("commit");
        owner.EmitSignal("selection_changed");
    }
    private static GodotObject NewActor() => new ActorData();
    private static string NewId() { using var crypto = new Crypto(); return System.Convert.ToHexString(crypto.GenerateRandomBytes(16)).ToLowerInvariant(); }
    public void copy(RefCounted owner)
    {
        var clipboard = owner.Get("_clipboard").AsGodotArray();
        clipboard.Clear();
        var document = Document(owner);
        foreach (var id in owner.Get("selected_ids").AsGodotArray())
        {
            var clip = document.Call("clip_for_id", id).As<Resource>();
            if (clip == null) continue;
            var actor = document.Call("actor_for_clip", id).AsGodotObject();
            var copied = NewActor();
            foreach (string key in new[] { "id", "type_id", "display_name" }) copied.Set(key, actor.Get(key));
            copied.Set("values", actor.Get("values").AsGodotDictionary().Duplicate(true));
            clipboard.Add(new Godot.Collections.Dictionary { ["clip"] = clip.Duplicate(false), ["actor"] = copied });
        }
    }
    public void paste(RefCounted owner, double at, string targetTrack)
    {
        var clipboard = owner.Get("_clipboard").AsGodotArray();
        if (clipboard.Count == 0) return;
        bool nested = owner.Get("_before").VariantType != Variant.Type.Nil;
        begin(owner, "Paste clips");
        double first = double.PositiveInfinity;
        foreach (var raw in clipboard) first = System.Math.Min(first, raw.AsGodotDictionary()["clip"].AsGodotObject().Get("start_time").AsDouble());
        var ids = owner.Get("selected_ids").AsGodotArray(); ids.Clear();
        var document = Document(owner);
        foreach (var raw in clipboard)
        {
            var entry = raw.AsGodotDictionary();
            var source = entry["actor"].AsGodotObject();
            var values = source.Get("values").AsGodotDictionary();
            string target = targetTrack.Length > 0 ? targetTrack : values.TryGetValue(new StringName("track_id"), out var sourceTrack) ? sourceTrack.AsString() : "";
            var destination = document.Call("track_for_id", target).AsGodotDictionary();
            if (destination.Count == 0 || (destination.TryGetValue("locked", out var locked) && locked.AsBool()) || (destination.TryGetValue("kind", out var kind) && kind.AsString() == "automation")) continue;
            var actor = NewActor();
            actor.Set("id", NewId()); actor.Set("type_id", new StringName("audio"));
            actor.Set("display_name", source.Get("display_name").AsString() + " copy");
            var copiedValues = values.Duplicate(true);
            if (targetTrack.Length > 0) copiedValues[new StringName("track_id")] = targetTrack;
            actor.Set("values", copiedValues);
            var clip = entry["clip"].As<Resource>().Duplicate(false);
            clip.Set("id", NewId()); clip.Set("actor_id", actor.Get("id"));
            clip.Set("start_time", System.Math.Max(0, at + clip.Get("start_time").AsDouble() - first));
            document.Get("actors").AsGodotArray().Add(actor);
            document.Get("clips").AsGodotArray().Add(clip);
            ids.Add(clip.Get("id"));
        }
        if (!nested) owner.Call("commit");
        owner.EmitSignal("selection_changed");
    }
    public void duplicate_selected(RefCounted owner)
    {
        var ids = owner.Get("selected_ids").AsGodotArray();
        if (ids.Count == 0) return;
        double end = 0;
        foreach (var id in ids)
        {
            var clip = Document(owner).Call("clip_for_id", id).AsGodotObject();
            if (clip != null) end = System.Math.Max(end, clip.Get("start_time").AsDouble() + clip.Get("duration").AsDouble());
        }
        copy(owner); paste(owner, end, "");
    }
    public void split_selected(RefCounted owner, double at)
    {
        bool nested = owner.Get("_before").VariantType != Variant.Type.Nil;
        begin(owner, "Split clips");
        var added = new GArray();
        var document = Document(owner);
        var ids = owner.Get("selected_ids").AsGodotArray();
        foreach (var id in ids)
        {
            if (!can_edit(owner, id.AsString())) continue;
            var clip = document.Call("clip_for_id", id).As<Resource>();
            if (clip == null) continue;
            double start = clip.Get("start_time").AsDouble(), duration = clip.Get("duration").AsDouble();
            if (at <= start + .00001 || at >= start + duration - .00001) continue;
            var actor = document.Call("actor_for_clip", id).AsGodotObject();
            var values = actor.Get("values").AsGodotDictionary();
            var newActor = NewActor();
            newActor.Set("id", NewId()); newActor.Set("type_id", new StringName("audio"));
            newActor.Set("display_name", actor.Get("display_name"));
            var newValues = values.Duplicate(true); newActor.Set("values", newValues);
            var right = clip.Duplicate(false);
            right.Set("id", NewId()); right.Set("actor_id", newActor.Get("id"));
            right.Set("start_time", at); right.Set("duration", start + duration - at);
            double speed = clip.Get("playback_speed").AsDouble();
            if (values.TryGetValue(new StringName("reverse"), out var reverse) && reverse.AsBool())
                clip.Set("source_offset", clip.Get("source_offset").AsDouble() + right.Get("duration").AsDouble() * speed);
            else right.Set("source_offset", right.Get("source_offset").AsDouble() + (at - start) * speed);
            shift_owner_automation(newValues, at - start);
            clip.Set("duration", at - start);
            values[new StringName("fade_out")] = System.Math.Min(.005, (at - start) * .1);
            newValues[new StringName("fade_in")] = System.Math.Min(.005, right.Get("duration").AsDouble() * .1);
            document.Get("actors").AsGodotArray().Add(newActor);
            document.Get("clips").AsGodotArray().Add(right);
            added.Add(right.Get("id"));
        }
        foreach (var id in added) ids.Add(id);
        if (!nested) owner.Call("commit");
    }
    public double note_source_tempo(GodotObject actor, GodotObject document)
    {
        var values = actor.Get("values").AsGodotDictionary();
        return values.TryGetValue(new StringName("source_bpm"), out var bpm) ? bpm.AsDouble() : document.Call("note_tempo").AsDouble();
    }
    public Vector2I note_source_meter(GodotObject actor, GodotObject document)
    {
        var fallback = document.Call("note_meter").AsVector2I();
        var values = actor.Get("values").AsGodotDictionary();
        if (!values.TryGetValue(new StringName("source_meter"), out var raw)) return fallback;
        var signature = raw.AsGodotArray();
        return new Vector2I(signature[0].AsInt32(), signature[1].AsInt32());
    }
    public bool is_note_source(GodotObject actor)
    {
        var values = actor.Get("values").AsGodotDictionary();
        return values.ContainsKey(new StringName("pattern_beats")) || values.ContainsKey(new StringName("instrument")) || (values.TryGetValue(new StringName("notes"), out var notes) && notes.AsGodotArray().Count > 0);
    }
    public void apply_note_render(GodotObject clip, GodotObject actor, AudioStreamWav stream, string signature)
    {
        var values = actor.Get("values").AsGodotDictionary();
        double Read(string key, double fallback) => values.TryGetValue(new StringName(key), out var raw) ? raw.AsDouble() : fallback;
        double scale = Read("notes_source_scale", 1);
        double oldLength = Read("source_duration", 0) * scale;
        double offset = clip.Get("source_offset").AsDouble() * scale;
        double speed = clip.Get("playback_speed").AsDouble();
        bool fullSource = offset < .00001 && System.Math.Abs(clip.Get("duration").AsDouble() * speed - oldLength) < .001;
        double length = stream.GetLength(), frame = 1.0 / stream.MixRate;
        bool loop = values.TryGetValue(new StringName("loop"), out var looping) && looping.AsBool();
        double newOffset = loop ? System.Math.Max(0, offset) : System.Math.Clamp(offset, 0, System.Math.Max(0, length - frame));
        clip.Set("source_offset", newOffset);
        if (fullSource) clip.Set("duration", length / speed);
        else if (!loop) clip.Set("duration", System.Math.Min(clip.Get("duration").AsDouble(), System.Math.Max(frame, length - newOffset) / speed));
        values[new StringName("audio")] = stream;
        values[new StringName("source_duration")] = length;
        values[new StringName("notes_dirty")] = false;
        values[new StringName("rendered_signature")] = signature;
        values.Remove(new StringName("notes_source_scale"));
    }
    public string replace_rendered_clips(RefCounted owner, GArray selection, string trackId, AudioStream? stream)
    {
        if (owner.Get("_before").VariantType != Variant.Type.Nil) return "Finish the current adjustment before replacing rendered clips.";
        if (selection.Count == 0) return "The rendered clip selection is empty. No clips were changed.";
        var document = Document(owner);
        var target = document.Call("track_for_id", trackId).AsGodotDictionary();
        if (target.Count == 0 || (target.TryGetValue("locked", out var locked) && locked.AsBool()) || (target.TryGetValue("kind", out var kind) && kind.AsString() == "automation")) return "The replacement track is locked or unavailable. No clips were changed.";
        double first = double.PositiveInfinity;
        var ids = new System.Collections.Generic.HashSet<string>();
        foreach (var raw in selection)
        {
            string id = raw.AsString();
            var clip = document.Call("clip_for_id", id).AsGodotObject();
            if (clip == null || !can_edit(owner, id) || document.Call("track_for_clip", id).AsGodotDictionary()["id"].AsString() != trackId) return "The rendered clips no longer share the intended unlocked track. No clips were changed.";
            first = System.Math.Min(first, clip.Get("start_time").AsDouble()); ids.Add(id);
        }
        if (stream == null || !double.IsFinite(stream.GetLength()) || stream.GetLength() <= 0) return "The rendered replacement has no playable audio. No clips were changed.";
        begin(owner, "Render clips in place");
        var replacement = document.Call("insert_source", stream, trackId, first, "Rendered selection").AsGodotObject();
        if (replacement == null) { cancel(owner); return "The rendered audio could not be inserted. Original clips were preserved."; }
        var values = document.Call("actor_for_clip", replacement.Get("id")).AsGodotObject().Get("values").AsGodotDictionary();
        values[new StringName("fade_in")] = 0.0; values[new StringName("fade_out")] = 0.0;
        var clips = document.Get("clips").AsGodotArray(); var actors = document.Get("actors").AsGodotArray();
        for (int i = clips.Count - 1; i >= 0; --i) if (ids.Contains(clips[i].AsGodotObject().Get("id").AsString())) { clips.RemoveAt(i); actors.RemoveAt(i); }
        var selected = owner.Get("selected_ids").AsGodotArray(); selected.Clear(); selected.Add(replacement.Get("id"));
        owner.Set("selected_track", trackId); commit(owner); owner.EmitSignal("selection_changed");
        return "";
    }
    public void copy_effects(RefCounted owner, GArray effects) => owner.Set("_effect_clipboard", effects.Duplicate(true));
    public GArray pasted_effects(RefCounted owner) => owner.Get("_effect_clipboard").AsGodotArray().Duplicate(true);
    public bool gesture_valid(RefCounted gesture, RefCounted? current)
    {
        var owner = gesture.Get("owner").As<RefCounted>();
        var before = gesture.Get("before").AsGodotObject();
        return owner != null && current == owner && Document(current) == gesture.Get("document").AsGodotObject() && before != null && current.Get("_before").AsGodotObject() == before;
    }
    public void gesture_clear(RefCounted gesture)
    {
        gesture.Set("owner", default(Variant)); gesture.Set("document", default(Variant)); gesture.Set("before", default(Variant));
    }
    public void gesture_begin(RefCounted gesture, RefCounted current, string label)
    {
        gesture_clear(gesture);
        if (current.Get("_before").VariantType != Variant.Type.Nil) commit(current);
        begin(current, label);
        gesture.Set("owner", current); gesture.Set("document", current.Get("document")); gesture.Set("before", current.Get("_before"));
    }
    public void gesture_finish(RefCounted gesture, RefCounted? current, bool keep)
    {
        var target = gesture.Get("owner").As<RefCounted>(); bool owns = gesture_valid(gesture, current);
        gesture_clear(gesture);
        if (owns && target != null) { if (keep) commit(target); else cancel(target); }
    }
}
