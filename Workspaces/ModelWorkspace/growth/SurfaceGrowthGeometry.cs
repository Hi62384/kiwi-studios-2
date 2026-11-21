using Godot;
using System;
using Settings = Godot.Collections.Dictionary;

public partial class SurfaceGrowthGeometry : RefCounted
{
    private readonly SurfaceGrowthSettings _settings = new();
    private static Settings Dict(GodotObject data, string key) => data.Get(key).AsGodotDictionary();
    private static Variant Get(Settings values, Variant key, Variant fallback = default) => values.TryGetValue(key, out var value) ? value : fallback;
    public Transform3D point_frame(GodotObject data, Settings root, Vector3[] positions)
    {
        Vector3I ids = root["triangle"].AsVector3I(); Vector3 bary = root["bary"].AsVector3();
        Vector3 a = positions[ids.X], b = positions[ids.Y], c = positions[ids.Z];
        Vector3 normal = (c - a).Cross(b - a).Normalized();
        if (normal.IsZeroApprox()) normal = root["normal"].AsVector3();
        Vector3 tangent = (b - a).Normalized();
        return new Transform3D(new Basis(tangent, normal, tangent.Cross(normal).Normalized()), a * bary.X + b * bary.Y + c * bary.Z);
    }
    public Vector3[] posed_points(GodotObject data, Skeleton3D? skeleton)
    {
        var source = data.Get("source_points").AsVector3Array(); var skin = data.Get("source_skin").As<Skin>();
        var weights = data.Get("source_weights").AsGodotArray();
        if (skeleton == null || skin == null || weights.Count == 0) return source;
        var matrices = new Transform3D[skin.GetBindCount()];
        for (int i = 0; i < matrices.Length; i++)
        {
            int bone = skin.GetBindBone(i); StringName name = skin.GetBindName(i);
            if (!name.IsEmpty) bone = skeleton.FindBone(name);
            matrices[i] = bone >= 0 && bone < skeleton.GetBoneCount() ? skeleton.GetBoneGlobalPose(bone) * skin.GetBindPose(i) : Transform3D.Identity;
        }
        var result = new Vector3[source.Length];
        for (int i = 0; i < result.Length; i++)
        {
            double sum = 0; Vector3 point = Vector3.Zero;
            foreach (var pair in weights[i].AsGodotDictionary())
            {
                int bone = pair.Key.AsInt32(); if (bone < 0 || bone >= matrices.Length) continue;
                float weight = pair.Value.AsSingle(); point += matrices[bone] * source[i] * weight; sum += weight;
            }
            result[i] = sum > .00001 ? point / (float)sum : source[i];
        }
        return result;
    }
    public Settings style(GodotObject data, Settings root)
        => Style(data, root, _settings.root_settings(data, root));
    private Settings Style(GodotObject data, Settings root, Settings basis)
    {
        if (data.Get("effective_revision").AsInt64() != data.Get("revision").AsInt64())
        {
            var effective = Dict(data, "groom").Duplicate(true);
            void Merge(Settings changes)
            {
                foreach (var pair in changes)
                {
                    if (!effective.ContainsKey(pair.Key)) effective[pair.Key] = new Settings();
                    effective[pair.Key].AsGodotDictionary().Merge(pair.Value.AsGodotDictionary(), true);
                }
            }
            foreach (var row in data.Get("groom_layers").AsGodotArray())
            {
                var layer = row.AsGodotDictionary(); if (Get(layer, "enabled", true).AsBool()) Merge(layer["changes"].AsGodotDictionary());
            }
            Merge(Dict(data, "pending")); data.Set("effective", effective); data.Set("effective_revision", data.Get("revision"));
        }
        string id = root["id"].AsInt64().ToString(System.Globalization.CultureInfo.InvariantCulture);
        var result = data.Get("groom_enabled").AsBool() ? Get(Dict(data, "effective"), id, new Settings()).AsGodotDictionary().Duplicate(true) : new Settings();
        result.Merge(Get(Dict(data, "individual"), id, new Settings()).AsGodotDictionary(), true);
        result["length"] = Math.Max(0, Get(result, "length", Get(basis, "length", .5)).AsDouble());
        result["density"] = Math.Clamp(Get(result, "density", 1.0 / Get(basis, "candidate_multiplier", 2).AsDouble()).AsDouble(), 0, 1);
        return result;
    }
    public Vector3 motion_delta(GodotObject data, Settings root, double t)
    {
        string id = root["id"].AsInt64().ToString(System.Globalization.CultureInfo.InvariantCulture);
        var weights = Get(Dict(data, "motion_weights"), id, new Settings()).AsGodotDictionary(); var guides = Dict(data, "motion_guides");
        Vector3 result = Vector3.Zero; double total = 0;
        foreach (var pair in weights)
        {
            if (!guides.ContainsKey(pair.Key)) continue;
            var points = Get(guides[pair.Key].AsGodotDictionary(), "delta_points", Array.Empty<Vector3>()).AsVector3Array();
            if (points.Length < 2) continue;
            double weight = Math.Max(0, pair.Value.AsDouble()), at = Math.Clamp(t, 0, 1) * (points.Length - 1); int index = Math.Min((int)at, points.Length - 2);
            result += points[index].Lerp(points[index + 1], (float)(at - index)) * (float)weight; total += weight;
        }
        return result / (float)Math.Max(.00001, total);
    }
    public Vector3[] curve(GodotObject data, Settings root, int segments)
    {
        var basis = _settings.root_settings(data, root); var edit = style(data, root);
        return Curve(data, root, segments, basis, edit, data.Get("source_points").AsVector3Array());
    }
    private Vector3[] Curve(GodotObject data, Settings root, int segments, Settings basis, Settings edit, Vector3[] source)
    {
        float B(string key, double fallback) => (float)Get(basis, key, fallback).AsDouble();
        float E(string key, double fallback) => (float)Get(edit, key, fallback).AsDouble();
        int type = (int)B("type", 0), shape = (int)B("shape", 0), lod = data.Get("lod_detail").AsInt32();
        bool final = data.Get("render_final").AsBool();
        int count = new[] { 3, 6, 10, 16 }[Math.Clamp((int)B("quality", 1), 0, 3)];
        Vector4 random = root["random"].AsVector4();
        float length = E("length", .5) * (1 + (random.X * 2 - 1) * B("variation", .25));
        Vector3 direction = Get(edit, "direction", Vector3.Up).AsVector3();
        if (type == 2) length *= (int)B("feather_type", 1) == 0 ? .45f : (int)B("feather_type", 1) == 2 ? 1.5f : 1;
        if (type == 1 && random.W < B("guard_hairs", .12)) length *= 1.6f;
        if (segments > 0) count = segments; else if (final) count = 16; else if (lod > 0) count = Math.Max(2, count / (lod + 1));
        if (!edit.ContainsKey("direction"))
        {
            var frame = point_frame(data, root, source);
            Vector3 preferred = Get(basis, "direction", Vector3.Down).AsVector3(); int mode = (int)B("direction_mode", 0);
            if (mode == 0) direction = Vector3.Up;
            else
            {
                if (mode == 1) preferred = data.Get("source_to_rig").AsTransform3D().Basis.Inverse() * preferred;
                if (mode == 3) preferred -= frame.Basis.Y * preferred.Dot(frame.Basis.Y);
                direction = Vector3.Up.Lerp(frame.Basis.Inverse() * preferred, Math.Clamp(B("direction_blend", .4), 0, 1)).Normalized();
            }
        }
        direction = (direction + new Vector3(random.Y - .5f, 0, random.Z - .5f) * B("orientation_variation", .15)).Normalized();
        float curl = E("curl", B("curl", shape == 2 || shape == 3 ? 1 : 0)), frequency = E("frequency", B("frequency", 3)), bend = B("curvature", .15);
        Vector3 offset = Get(edit, "offset", Vector3.Zero).AsVector3(); float frizz = E("frizz", B("frizz", 0)), frizzFrequency = B("frizz_frequency", 8);
        if (segments <= 0 && (Math.Abs(curl) > .0001f || frizz > .0001f))
        {
            int quality = final ? 3 : Math.Clamp((int)B("quality", 1) - lod, 0, 3);
            count = Math.Max(count, Math.Min(new[] { 12, 32, 64, 96 }[quality], (int)Math.Ceiling(Math.Max(frequency, frizz > 0 ? frizzFrequency : 0) * new[] { 3, 6, 8, 12 }[quality])));
        }
        var result = new Vector3[count + 1];
        for (int i = 0; i <= count; i++)
        {
            float t = (float)i / count;
            Vector3 point = direction * length * t + new Vector3(0, -bend * length * t * t, 0) + offset * t * t;
            if (shape == 1) point.X += Mathf.Sin(t * Mathf.Pi) * length * bend;
            if (curl != 0) point += new Vector3(Mathf.Sin(t * Mathf.Tau * frequency), 0, shape == 3 ? 1 - Mathf.Cos(t * Mathf.Tau * frequency) : 0) * length * .12f * curl * t;
            if (frizz > 0)
            {
                float phase = random.Z * Mathf.Tau, wave = t * Mathf.Tau * frizzFrequency + phase;
                point += new Vector3(Mathf.Sin(wave) - Mathf.Sin(phase), 0, Mathf.Cos(wave * .83f) - Mathf.Cos(phase * .83f)) * length * frizz * .1f * t;
            }
            if (edit.ContainsKey("clump_target"))
            {
                float clumping = Mathf.SmoothStep(E("clump_start", 0), Math.Max(.001f + E("clump_start", 0), E("clump_end", 1)), t);
                clumping *= Math.Clamp(E("clump", 0) * (1 - E("clump_variation", 0) * random.Y), 0, 1);
                point = point.Lerp(edit["clump_target"].AsVector3() * t, clumping);
            }
            result[i] = point;
        }
        if (!Mathf.IsZeroApprox(curl) || frizz > 0)
            for (int i = 1; i < result.Length; i++) result[i] = result[i - 1] + (result[i] - result[i - 1]).Normalized() * length / count;
        var weights = Get(edit, "guide_weights", new Settings()).AsGodotDictionary().Duplicate();
        string single = Get(edit, "guide", "").AsString(); if (weights.Count == 0 && single.Length > 0) weights[single] = 1.0;
        var guides = Dict(data, "guides"); float total = 0, influence = 0; var blended = new Vector3[result.Length];
        foreach (var pair in weights)
        {
            if (!guides.ContainsKey(pair.Key)) continue;
            var guide = guides[pair.Key].AsGodotDictionary(); var points = guide["points"].AsVector3Array(); float weight = Math.Max(0, pair.Value.AsSingle());
            if (points.Length < 2 || weight <= 0) continue;
            total += weight; influence += weight * Math.Clamp(Get(guide, "influence", 1).AsSingle(), 0, 1);
            var rotation = Basis.FromEuler(Get(guide, "rotation", Vector3.Zero).AsVector3()); float scale = Math.Max(.001f, Get(guide, "length_scale", 1).AsSingle());
            for (int i = 0; i < result.Length; i++)
            {
                float at = (float)i / (result.Length - 1) * (points.Length - 1); int index = Math.Min((int)at, points.Length - 2);
                blended[i] += rotation * (points[index].Lerp(points[index + 1], at - index) - points[0]) * scale * weight;
            }
        }
        if (total > 0) for (int i = 1; i < result.Length; i++) result[i] = result[i].Lerp(blended[i] / total, influence / total);
        var trimmed = Get(edit, "trim_curve", Array.Empty<Vector3>()).AsVector3Array();
        if (trimmed.Length > 1)
        {
            float factor = E("length", .5) / Math.Max(.00001f, E("trim_length", E("length", .5)));
            for (int i = 0; i < trimmed.Length; i++) trimmed[i] *= factor;
            result = resample_curve(trimmed, count + 1);
        }
        if (!data.Get("gpu_motion").AsBool() && Dict(data, "motion_guides").Count > 0)
            for (int i = 1; i < result.Length; i++) result[i] += motion_delta(data, root, (double)i / (result.Length - 1)) * data.Get("motion_influence").AsSingle();
        return result;
    }
    public Vector3[] resample_curve(Vector3[] points, int count)
    {
        if (count <= 0) return Array.Empty<Vector3>();
        var result = new Vector3[count]; if (points.Length == 0) return result;
        if (points.Length == 1) { Array.Fill(result, points[0]); return result; }
        var distances = new float[points.Length]; float length = 0;
        for (int i = 1; i < points.Length; i++) { length += points[i].DistanceTo(points[i - 1]); distances[i] = length; }
        int segment = 0;
        for (int i = 0; i < count; i++)
        {
            float target = length * i / Math.Max(1, count - 1);
            while (segment < points.Length - 2 && distances[segment + 1] < target) segment++;
            result[i] = points[segment].Lerp(points[segment + 1], Math.Clamp((target - distances[segment]) / Math.Max(.000001f, distances[segment + 1] - distances[segment]), 0, 1));
        }
        return result;
    }
    public int cut_plane(GodotObject data, Plane plane)
    {
        _settings.prepare_regions(data); var source = data.Get("source_points").AsVector3Array(); int changed = 0;
        foreach (var row in data.Get("roots").AsGodotArray())
        {
            var root = row.AsGodotDictionary(); var basis = ResolvedSettings(data, root); var edit = Style(data, root, basis);
            if (Get(edit, "locked", false).AsBool()) continue;
            var frame = point_frame(data, root, source); var points = Curve(data, root, -1, basis, edit, source);
            var clipped = new System.Collections.Generic.List<Vector3> { Vector3.Zero }; float length = 0;
            for (int i = 1; i < points.Length; i++)
            {
                Vector3? hit = plane.IntersectsSegment(frame * points[i - 1], frame * points[i]);
                if (hit.HasValue)
                {
                    Vector3 point = frame.AffineInverse() * hit.Value; length += clipped[^1].DistanceTo(point); clipped.Add(point);
                    string id = root["id"].AsInt64().ToString(System.Globalization.CultureInfo.InvariantCulture); var individual = Dict(data, "individual");
                    if (!individual.ContainsKey(id)) individual[id] = new Settings();
                    individual[id].AsGodotDictionary().Merge(new Settings { ["trim_curve"] = clipped.ToArray(), ["trim_length"] = length, ["length"] = length }, true); changed++; break;
                }
                length += points[i - 1].DistanceTo(points[i]); clipped.Add(points[i]);
            }
        }
        data.Set("revision", data.Get("revision").AsInt64() + 1); return changed;
    }
}
