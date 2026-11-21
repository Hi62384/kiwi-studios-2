using Godot;
using System;
using GArray = Godot.Collections.Array;
using Settings = Godot.Collections.Dictionary;

public partial class AudioStepControlOperations : RefCounted
{
    private static readonly double[] Divisions = { 1, .5, 1.0 / 3, .25, 1.0 / 6, .125, 1.0 / 12 };
    private static readonly string[] Labels = { "1/4", "1/8", "1/8 triplet", "1/16", "1/16 triplet", "1/32", "1/32 triplet" };
    private static Variant Get(Settings d, string key, Variant fallback = default) => d.TryGetValue(key, out var value) ? value : fallback;
    public Settings default_settings() => new Settings { ["steps"] = 16, ["division"] = .25, ["swing"] = 0.0, ["accent_variation"] = 0.0, ["seed"] = 1, ["lanes"] = new Settings() };
    public GArray render_copy(GArray notes, Settings settings, Settings instrument)
    {
        var result = notes.Duplicate(true); if (settings.Count == 0) return result;
        double step = Math.Clamp(Get(settings, "division", .25).AsDouble(), 1.0 / 12, 1), amount = Math.Clamp(Get(settings, "swing", 0.0).AsDouble(), -.45, .45), variation = Math.Clamp(Get(settings, "accent_variation", 0.0).AsDouble(), 0, 1);
        var lanes = Get(settings, "lanes", new Settings()).AsGodotDictionary(); bool hasSolo = false;
        foreach (var raw in lanes.Values) if (raw.VariantType == Variant.Type.Dictionary && Get(raw.AsGodotDictionary(), "solo", false).AsBool()) hasSolo = true;
        long seed = Get(settings, "seed", Get(instrument, "seed", 1)).AsInt64();
        for (int i = 0; i < result.Count; ++i)
        {
            var note = result[i].AsGodotDictionary(); var lane = Get(lanes, ((int)Get(note, "pitch", 60).AsDouble()).ToString(System.Globalization.CultureInfo.InvariantCulture), new Settings()).AsGodotDictionary();
            if (Get(lane, "mute", false).AsBool() || (hasSolo && !Get(lane, "solo", false).AsBool())) note["mute"] = true;
            double start = Get(note, "start", 0).AsDouble(); long cell = (long)Math.Round(start / step, MidpointRounding.AwayFromZero);
            if (cell % 2 == 1) note["start"] = Math.Max(0, start + amount * step);
            if (variation > 0)
            {
                using var rng = new RandomNumberGenerator(); string id = note.TryGetValue("id", out var identifier) ? identifier.AsString() : i.ToString(System.Globalization.CultureInfo.InvariantCulture);
                rng.Seed = unchecked((ulong)(seed ^ (long)unchecked((uint)GD.Hash(id))));
                note["velocity"] = Math.Clamp(Get(note, "velocity", .8).AsDouble() * (1 + rng.RandfRange(-.5f, .5f) * variation), 0, 1);
            }
        }
        return result;
    }
    private static SpinBox Spin(Node parent, string label, double low, double high, double step, Action<double> changed)
    {
        parent.AddChild(new Label { Text = label }); var spin = new SpinBox { Name = label.Replace(" ", ""), MinValue = low, MaxValue = high, Step = step, CustomMinimumSize = new Vector2(70, 0) }; parent.AddChild(spin); spin.ValueChanged += v => changed(v); return spin;
    }
    public void setup(Control owner, RefCounted session, Control canvas)
    {
        owner.Set("session", session); owner.Set("canvas", canvas);
        if (owner.Get("step_count").AsGodotObject() == null)
        {
            var row = new HFlowContainer(); owner.AddChild(row);
            owner.Set("step_count", Spin(row, "Steps", 1, 256, 1, v => set_setting(owner, "steps", (int)v, true)));
            row.AddChild(new Label { Text = "Division" }); var division = new OptionButton { Name = "Division" }; row.AddChild(division); owner.Set("division", division);
            foreach (string label in Labels) division.AddItem(label); division.ItemSelected += i => set_setting(owner, "division", Divisions[(int)i], true);
            owner.Set("swing", Spin(row, "Swing %", -45, 45, 1, v => set_setting(owner, "swing", v / 100, false)));
            owner.Set("accent_variation", Spin(row, "Accent variation %", 0, 100, 1, v => set_setting(owner, "accent_variation", v / 100, false)));
            owner.Set("seed_input", Spin(row, "Seed", 0, int.MaxValue, 1, v => set_setting(owner, "seed", (long)v, false)));
            var lanes = new HFlowContainer(); owner.AddChild(lanes);
            var script = GD.Load<GDScript>("res://Workspaces/AudioWorkspace/audio_pattern_canvas.gd");
            var constants = script.GetScriptConstantMap(); var drums = constants["DRUMS"].AsGodotArray(); var names = constants["DRUM_NAMES"].AsGodotArray(); var controls = owner.Get("lane_controls").AsGodotDictionary();
            for (int i = 0; i < drums.Count; ++i)
            {
                int pitch = drums[i].AsInt32(); var lane = new HBoxContainer(); lanes.AddChild(lane); string name = names[i].AsString(); lane.AddChild(new Label { Text = name });
                var mute = new CheckBox { Text = "M", TooltipText = "Mute " + name }; var solo = new CheckBox { Text = "S", TooltipText = "Solo " + name }; lane.AddChild(mute); lane.AddChild(solo);
                mute.Toggled += v => set_lane(owner, pitch, "mute", v); solo.Toggled += v => set_lane(owner, pitch, "solo", v);
                controls[pitch.ToString(System.Globalization.CultureInfo.InvariantCulture)] = new Settings { ["mute"] = mute, ["solo"] = solo };
            }
        }
        sync_selection(owner);
    }
    public void sync_selection(Control owner)
    {
        if (owner.Get("step_count").AsGodotObject() == null) return;
        owner.Set("_syncing", true);
        var session = owner.Get("session").As<RefCounted>(); var actor = session?.Call("primary_actor").AsGodotObject(); var clip = session?.Call("primary_clip").AsGodotObject();
        using var edits = new AudioEditSessionOperations();
        bool editable = actor != null && edits.is_note_source(actor) && clip != null && session != null && edits.can_edit(session, clip.Get("id").AsString());
        var settings = default_settings(); if (actor != null) settings.Merge(Get(actor.Get("values").AsGodotDictionary(), "step_settings", new Settings()).AsGodotDictionary(), true);
        foreach (string key in new[] { "step_count", "swing", "accent_variation", "seed_input" }) owner.Get(key).As<SpinBox>().Editable = editable;
        var division = owner.Get("division").As<OptionButton>(); division.Disabled = !editable;
        owner.Get("step_count").As<SpinBox>().SetValueNoSignal(settings["steps"].AsDouble()); owner.Get("swing").As<SpinBox>().SetValueNoSignal(settings["swing"].AsDouble() * 100); owner.Get("accent_variation").As<SpinBox>().SetValueNoSignal(settings["accent_variation"].AsDouble() * 100); owner.Get("seed_input").As<SpinBox>().SetValueNoSignal(settings["seed"].AsDouble());
        int index = 0; for (int i = 0; i < Divisions.Length; ++i) if (Mathf.IsEqualApprox(settings["division"].AsDouble(), Divisions[i])) { index = i; break; }
        division.Select(index); owner.Get("canvas").AsGodotObject()?.Set("snap_beat", settings["division"]);
        var controls = owner.Get("lane_controls").AsGodotDictionary(); var lanes = settings["lanes"].AsGodotDictionary();
        foreach (var pitch in controls.Keys)
        {
            var lane = lanes.TryGetValue(pitch, out var raw) ? raw.AsGodotDictionary() : new Settings();
            foreach (string key in new[] { "mute", "solo" }) { var control = controls[pitch].AsGodotDictionary()[key].As<CheckBox>(); control.Disabled = !editable; control.SetPressedNoSignal(Get(lane, key, false).AsBool()); }
        }
        owner.Set("_syncing", false);
    }
    public void set_setting(Control owner, string key, Variant value, bool resize)
    {
        Edit(owner, "Edit step " + key.Replace("_", " "), (settings, values) => { settings[key] = value; if (resize) values[new StringName("pattern_beats")] = settings["steps"].AsDouble() * settings["division"].AsDouble(); }, true);
    }
    public void set_lane(Control owner, int pitch, string key, bool value)
    {
        Edit(owner, "Edit step lane " + key, (settings, _) => { var lanes = settings["lanes"].AsGodotDictionary().Duplicate(true); string id = pitch.ToString(System.Globalization.CultureInfo.InvariantCulture); var lane = Get(lanes, id, new Settings()).AsGodotDictionary().Duplicate(true); lane[key] = value; lanes[id] = lane; settings["lanes"] = lanes; }, false);
    }
    private void Edit(Control owner, string label, Action<Settings, Settings> change, bool sync)
    {
        if (owner.Get("_syncing").AsBool()) return; var session = owner.Get("session").As<RefCounted>(); if (session == null) return;
        using var edits = new AudioEditSessionOperations(); var actor = edits.primary(session, true).AsGodotObject(); var clip = edits.primary(session, false).AsGodotObject();
        if (actor == null || clip == null || !edits.is_note_source(actor) || !edits.can_edit(session, clip.Get("id").AsString())) return;
        bool nested = session.Get("_before").VariantType != Variant.Type.Nil; edits.begin(session, label);
        var values = actor.Get("values").AsGodotDictionary(); var settings = default_settings(); settings.Merge(Get(values, "step_settings", new Settings()).AsGodotDictionary(), true); change(settings, values); values[new StringName("step_settings")] = settings; values[new StringName("notes_dirty")] = true;
        if (!nested) edits.commit(session); if (sync) sync_selection(owner); owner.EmitSignal("changed");
    }
}
