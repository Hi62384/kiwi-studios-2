using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings = Godot.Collections.Dictionary;

public partial class RigWeighting : RefCounted
{
    public const int MaxVertices = 100000;
    public const int MaxPairs = 3000000;
    private readonly RigGeometry _geometry = new();
    private static Variant Value(Settings values, string key, Variant fallback) => values.TryGetValue(key, out var found) ? found : fallback;
    private static bool Cancelled(RefCounted? cancellation) => cancellation != null && cancellation.Call("is_cancelled").AsBool();
    internal sealed class BindingContext
    {
        public readonly string[] Ids;
        public readonly HashSet<string> Locked;
        public readonly int Count;
        public BindingContext(Resource binding) { Ids = binding.Get("bone_ids").AsStringArray(); Locked = new HashSet<string>(binding.Get("locked_bones").AsStringArray()); Count = binding.Get("influence_count").AsInt32(); }
    }
    public Settings normalized(Resource binding, Settings values, int fallback, double cutoff) => Normalize(new BindingContext(binding), values, fallback, cutoff);
    internal static Settings Normalize(BindingContext context, Settings values, int fallback, double cutoff)
    {
        string[] ids = context.Ids; var locked = context.Locked; int count = context.Count; var fixedValues = new Settings(); var free = new Dictionary<int, double>(); double reserved = 0;
        foreach (var pair in values)
        {
            int bone = pair.Key.AsInt32(); double amount = pair.Value.AsDouble();
            if (bone < 0 || bone >= ids.Length || !double.IsFinite(amount) || amount <= 0) continue;
            if (locked.Contains(ids[bone])) { fixedValues[bone] = amount; reserved += amount; }
            else if (amount > cutoff) free[bone] = amount;
        }
        if (reserved > 1.00001 || fixedValues.Count > count) return values.Duplicate();
        var ordered = free.OrderByDescending(pair => pair.Value).Take(Math.Max(0, count - fixedValues.Count)).ToArray(); double total = ordered.Sum(pair => pair.Value);
        if (total <= .0000001 && reserved < .99999)
        {
            if (ids.Length == 0) return fixedValues;
            int index = Math.Clamp(fallback, 0, ids.Length - 1);
            if (!locked.Contains(ids[index]) && fixedValues.Count < count) fixedValues[index] = 1 - reserved;
            else for (int i = 0; i < ids.Length; i++) if (!locked.Contains(ids[i]) && fixedValues.Count < count) { fixedValues[i] = 1 - reserved; break; }
        }
        else foreach (var pair in ordered) fixedValues[pair.Key] = pair.Value / total * Math.Max(0, 1 - reserved);
        return fixedValues;
    }

    public Settings prepare_region(Resource document, Resource armature, int selectedBone, Settings region, double amount)
    {
        var before = new Settings(); var after = new Settings(); var bones = armature.Get("bones").AsGodotArray();
        if (selectedBone < 0 || selectedBone >= bones.Count) return new Settings { ["before"] = before, ["after"] = after };
        string selectedId = bones[selectedBone].AsGodotDictionary()["id"].AsString(), rigId = armature.Get("id").AsString();
        var cache = new Dictionary<(string, int), (BindingContext context, int bone, int[] ids, float[] weights)>();
        foreach (var pair in region)
        {
            var entry = pair.Value.AsGodotDictionary(); string id = entry["id"].AsString(); int surface = entry["surface"].AsInt32(), vertex = entry["vertex"].AsInt32();
            if (!cache.TryGetValue((id,surface), out var data))
            {
                var item = document.Call("component",id).As<Resource>(); if (item == null || item.Get("skeleton_id").AsString() != rigId) continue;
                var binding = item.Get("binding").As<Resource>(); if (binding == null) continue;
                var indices = binding.Get("indices").AsGodotArray(); var weights = binding.Get("weights").AsGodotArray();
                if (surface < 0 || surface >= indices.Count || surface >= weights.Count) continue;
                var context = new BindingContext(binding);
                data = (context,Array.IndexOf(context.Ids,selectedId),indices[surface].AsInt32Array(),weights[surface].AsFloat32Array()); cache[(id,surface)] = data;
            }
            if (data.bone < 0 || data.context.Count <= 0 || vertex < 0 || ((long)vertex+1)*data.context.Count > Math.Min(data.ids.Length,data.weights.Length)) continue;
            var old = ReadVertex(data.ids,data.weights,data.context.Count,vertex); var next = Correct(data.context,old.Duplicate(),data.bone,"Replace",amount,new Settings());
            if (GD.VarToStr(old) == GD.VarToStr(next)) continue;
            before[pair.Key] = new Settings { ["id"] = id,["surface"] = surface,["vertex"] = vertex,["values"] = old };
            after[pair.Key] = new Settings { ["id"] = id,["surface"] = surface,["vertex"] = vertex,["values"] = next };
        }
        return new Settings { ["before"] = before,["after"] = after };
    }
    public void paint_region(Resource item,Settings data,int bone,Transform3D transform,Vector3 hit,Vector3 rayOrigin,double best,double radius,double strength,double target,string mode,bool subtract,bool paintHidden,bool selectedOnly,Settings region,Settings before,Settings after,Settings touched)
    {
        var binding=item.Get("binding").As<Resource>();var context=new BindingContext(binding); if(bone<0||bone>=context.Ids.Length||radius<=0) return;
        string id=item.Get("id").AsString();var surfaces=data["points"].AsGodotArray();var handler=new RigBindingWeights();
        Settings? graph=mode=="Smooth"?handler.topology(binding):null;
        var indices=binding.Get("indices").AsGodotArray();var weights=binding.Get("weights").AsGodotArray();
        var allIds=indices.Select(value=>value.AsInt32Array()).ToArray();var allWeights=weights.Select(value=>value.AsFloat32Array()).ToArray();
        for(int surface=0;surface<surfaces.Count;surface++)
        {
            var points=surfaces[surface].AsVector3Array();var changes=new Settings();
            int[] welded=graph==null?Array.Empty<int>():graph["surfaces"].AsGodotArray()[surface].AsInt32Array();
            for(int vertex=0;vertex<points.Length;vertex++)
            {
                Vector3 position=transform*points[vertex];double distance=position.DistanceTo(hit);
                if(distance>radius||(!paintHidden&&position.DistanceTo(rayOrigin)>best+radius*.15)) continue;
                string key=id+":"+surface+":"+vertex; if(selectedOnly&&!region.ContainsKey(key)) continue;
                var old=ReadVertex(allIds[surface],allWeights[surface],context.Count,vertex);
                double t=Math.Clamp(1-distance/radius,0,1),amount=strength*t*t*(3-2*t);
                if(mode=="Replace") {double current=old.TryGetValue(bone,out var found)?found.AsDouble():0;amount=current+(target-current)*amount;}
                var average=new Settings();
                if(graph!=null)
                {
                    foreach(int other in graph["neighbors"].AsGodotArray()[welded[vertex]].AsInt32Array())
                    {
                        var representative=graph["representatives"].AsGodotDictionary()[other].AsVector2I();
                        foreach(var pair in ReadVertex(allIds[representative.X],allWeights[representative.X],context.Count,representative.Y))
                            average[pair.Key]=(average.TryGetValue(pair.Key,out var previous)?previous.AsDouble():0)+pair.Value.AsDouble();
                    }
                    average=Normalize(context,average,0,0);
                }
                var next=Correct(context,old.Duplicate(),bone,subtract?"Subtract":mode,amount,average);
                if(GD.VarToStr(old)==GD.VarToStr(next)) continue;
                if(!before.ContainsKey(key)) before[key]=new Settings{["id"]=id,["surface"]=surface,["vertex"]=vertex,["values"]=old};
                changes[vertex]=next;after[key]=new Settings{["id"]=id,["surface"]=surface,["vertex"]=vertex,["values"]=next};touched[id]=true;
            }
            if(changes.Count>0)
            {
                handler.assign_vertices(binding,surface,changes);
                allIds[surface]=binding.Get("indices").AsGodotArray()[surface].AsInt32Array();
                allWeights[surface]=binding.Get("weights").AsGodotArray()[surface].AsFloat32Array();
            }
        }
    }
    public Settings corrected(Resource binding, int surface, int vertex, int bone, string mode, double amount, Settings neighbors)
        => Correct(new BindingContext(binding), binding.Call("vertex", surface, vertex).AsGodotDictionary(), bone, mode, amount, neighbors);
    private static Settings Correct(BindingContext context, Settings values, int bone, string mode, double amount, Settings neighbors)
    {
        string[] ids = context.Ids; var locked = context.Locked;
        if (bone < 0 || bone >= ids.Length || locked.Contains(ids[bone])) return values;
        double old = values.TryGetValue(bone, out var current) ? current.AsDouble() : 0, next = old;
        switch (mode)
        {
            case "Add": next = Math.Min(1, old + amount); break;
            case "Subtract": next = Math.Max(0, old - amount); break;
            case "Replace": next = Math.Clamp(amount, 0, 1); break;
            case "Clear": next = 0; break;
            case "Smooth":
                var blended = values.Duplicate();
                foreach (var pair in neighbors) { double original = values.TryGetValue(pair.Key, out var found) ? found.AsDouble() : 0; blended[pair.Key] = original + (pair.Value.AsDouble() - original) * amount; }
                return Normalize(context, blended, bone, 0);
        }
        double fixedTotal = 0, remainder = 0;
        foreach (var pair in values)
        {
            int index = pair.Key.AsInt32(); if (index == bone) continue;
            if (locked.Contains(ids[index])) fixedTotal += pair.Value.AsDouble(); else remainder += pair.Value.AsDouble();
        }
        next = Math.Min(next, 1 - fixedTotal); values[bone] = next;
        foreach (Variant key in values.Keys.ToArray())
        {
            int index = key.AsInt32(); if (index == bone || locked.Contains(ids[index])) continue;
            values[key] = remainder > 0 ? values[key].AsDouble() / remainder * Math.Max(0, 1 - fixedTotal - next) : 0;
        }
        if (remainder <= .000001 && fixedTotal + next < .99999)
            for (int index = 0; index < ids.Length; index++) if (index != bone && !locked.Contains(ids[index])) { values[index] = 1 - fixedTotal - next; break; }
        return Normalize(context, values, bone, 0);
    }
    private static Dictionary<int, double> Normalize(Dictionary<int, double> scores, int influences)
    {
        var ordered = scores.Where(pair => double.IsFinite(pair.Value) && pair.Value > 0).OrderByDescending(pair => pair.Value).Take(influences).ToArray();
        double sum = ordered.Sum(pair => pair.Value); var result = new Dictionary<int, double>();
        if (sum <= .0000001) { result[0] = 1; return result; }
        foreach (var pair in ordered) result[pair.Key] = pair.Value / sum;
        return result;
    }
    internal static Settings ReadVertex(int[] ids, float[] weights, int count, int vertex)
    {
        var result = new Settings();
        for (int k = 0; k < count; k++) { int offset = vertex * count + k; if (weights[offset] > 0) result[ids[offset]] = (result.TryGetValue(ids[offset], out var previous) ? previous.AsDouble() : 0) + weights[offset]; }
        return result;
    }
    public Settings prepare_cleanup(Resource armature, Godot.Collections.Array targets, int selectedBone, int axis, double offset, string kind)
    {
        var before = new Settings(); var after = new Settings(); var bones = armature.Get("bones").AsGodotArray();
        Settings Result() => new() { ["before"] = before, ["after"] = after };
        if (selectedBone < 0 || selectedBone >= bones.Count) return Result();
        var snapshots = new List<(Resource item, BindingContext context, Transform3D transform, List<(Vector3[] points, int[] ids, float[] weights)> surfaces)>();
        foreach (Variant target in targets)
        {
            var item = target.As<Resource>(); var binding = item.Get("binding").As<Resource>();
            if (binding == null || binding.Get("rigid_bone_id").AsString().Length > 0) continue;
            var context = new BindingContext(binding); var source = binding.Get("source_mesh").As<Mesh>(); var indices = binding.Get("indices").AsGodotArray(); var weights = binding.Get("weights").AsGodotArray();
            var surfaces = new List<(Vector3[], int[], float[])>();
            for (int surface = 0; surface < indices.Count; surface++) surfaces.Add((source.SurfaceGetArrays(surface)[(int)Mesh.ArrayType.Vertex].AsVector3Array(), indices[surface].AsInt32Array(), weights[surface].AsFloat32Array()));
            snapshots.Add((item, context, binding.Get("mesh_to_rig").AsTransform3D(), surfaces));
        }
        Vector3I Key(Vector3 point) => new(Mathf.RoundToInt((double)point.X * 10000), Mathf.RoundToInt((double)point.Y * 10000), Mathf.RoundToInt((double)point.Z * 10000));
        var mirrorLookup = new Dictionary<Vector3I, Dictionary<string, double>>(); double side = -1;
        if (kind == "Mirror weights")
        {
            using var math = new RigMath(); var rest = math.globals(bones, false); side = Math.Sign(rest[selectedBone].Origin[axis] - offset);
            if (side == 0) side = Math.Sign(math.tail(bones[selectedBone].AsGodotDictionary(), rest[selectedBone])[axis] - offset); if (side == 0) side = -1;
            var mirrorIds = new Dictionary<string, string>();
            foreach (Variant value in bones) { var bone = value.AsGodotDictionary(); string id = bone["id"].AsString(), mirrored = bone["mirror_id"].AsString(); mirrorIds[id] = mirrored.Length > 0 ? mirrored : id; }
            foreach (var snapshot in snapshots) foreach (var surface in snapshot.surfaces)
                for (int vertex = 0; vertex < surface.points.Length; vertex++)
                {
                    var values = new Dictionary<string, double>(); var weights = ReadVertex(surface.ids, surface.weights, snapshot.context.Count, vertex);
                    foreach (var pair in weights) { string id = snapshot.context.Ids[pair.Key.AsInt32()]; values[mirrorIds.GetValueOrDefault(id, id)] = pair.Value.AsDouble(); }
                    mirrorLookup[Key(snapshot.transform * surface.points[vertex])] = values;
                }
        }
        string selectedId = bones[selectedBone].AsGodotDictionary()["id"].AsString(); var emptyNeighbors = new Settings();
        foreach (var snapshot in snapshots)
        {
            int selected = System.Array.IndexOf(snapshot.context.Ids, selectedId);
            for (int surfaceIndex = 0; surfaceIndex < snapshot.surfaces.Count; surfaceIndex++)
            {
                var surface = snapshot.surfaces[surfaceIndex];
                for (int vertex = 0; vertex < surface.points.Length; vertex++)
                {
                    var old = ReadVertex(surface.ids, surface.weights, snapshot.context.Count, vertex); var next = Normalize(snapshot.context, old, 0, kind == "Fix Weights" ? .00001 : 0);
                    if (kind == "Clear influence") next = Correct(snapshot.context, old.Duplicate(), selected, "Clear", 1, emptyNeighbors);
                    else if (kind == "Mirror weights")
                    {
                        Vector3 point = snapshot.transform * surface.points[vertex]; if ((point[axis] - offset) * side >= -.0001) continue;
                        point[axis] = (float)(2 * offset - point[axis]); if (!mirrorLookup.TryGetValue(Key(point), out var mirrored)) continue;
                        var values = new Settings(); foreach (var pair in mirrored) { int bone = System.Array.IndexOf(snapshot.context.Ids, pair.Key); if (bone >= 0) values[bone] = pair.Value; }
                        foreach (var pair in old) if (snapshot.context.Locked.Contains(snapshot.context.Ids[pair.Key.AsInt32()])) values[pair.Key] = pair.Value;
                        next = Normalize(snapshot.context, values, 0, 0);
                    }
                    bool same = old.Count == next.Count && old.All(pair => next.TryGetValue(pair.Key, out var value) && pair.Value.Equals(value)); if (same) continue;
                    string id = snapshot.item.Get("id").AsString(), key = id + ":" + surfaceIndex + ":" + vertex;
                    before[key] = new Settings { ["id"] = id, ["surface"] = surfaceIndex, ["vertex"] = vertex, ["values"] = old };
                    after[key] = new Settings { ["id"] = id, ["surface"] = surfaceIndex, ["vertex"] = vertex, ["values"] = next };
                }
            }
        }
        return Result();
    }

    public Resource? compute(Mesh source, Godot.Collections.Array bones, Transform3D transform, string method, int count, int iterations, RefCounted? cancellation)
    {
        for (int surface = 0; surface < source.GetSurfaceCount(); surface++) if (source.Call("surface_get_primitive_type", surface).AsInt32() != (int)Mesh.PrimitiveType.Triangles) return null;
        var result = new KiwiRigBinding(); int influences = count == 8 ? 8 : 4;
        result.Set("source_mesh", source); result.Set("mesh_to_rig", transform); result.Set("influence_count", influences);
        var boneData = bones.Select(value => value.AsGodotDictionary()).ToArray();
        result.Set("bone_ids", boneData.Select(bone => bone["id"].AsString()).ToArray());
        if (bones.Count == 0) return result;
        bool[] deform = boneData.Select(bone => Value(Value(bone, "metadata", new Settings()).AsGodotDictionary(), "deform", true).AsBool()).ToArray();
        if (!deform.Any(value => value)) return null;
        var shape = _geometry.geometry(source, transform); Vector3[] points = shape["points"].AsVector3Array();
        var mappings = shape["surfaces"].AsGodotArray(); var adjacent = shape["neighbors"].AsGodotArray().Select(value => value.AsInt32Array()).ToArray();
        int[] islands = shape["islands"].AsInt32Array(); int groupCount = shape["groups"].AsGodotArray().Count; double edge = shape["edge"].AsDouble();
        var rest = new Transform3D[bones.Count]; var ready = new bool[bones.Count]; var visiting = new bool[bones.Count];
        Transform3D Global(int index)
        {
            if (ready[index]) return rest[index]; if (visiting[index]) return Transform3D.Identity;
            visiting[index] = true; int parent = boneData[index]["parent"].AsInt32(); var local = boneData[index]["rest"].AsTransform3D();
            rest[index] = parent >= 0 && parent < bones.Count ? Global(parent) * local : local;
            ready[index] = true; visiting[index] = false; return rest[index];
        }
        for (int i = 0; i < bones.Count; i++) Global(i);
        Vector3[] tails = rest.Select((pose, index) => pose * new Vector3(0, (float)Math.Max(.001, Value(boneData[index], "length", .25).AsDouble()), 0)).ToArray();
        var distances = new double[points.Length][]; var islandDistance = new double[groupCount][];
        for (int i = 0; i < groupCount; i++) { islandDistance[i] = new double[bones.Count]; System.Array.Fill(islandDistance[i], double.PositiveInfinity); }
        for (int vertex = 0; vertex < points.Length; vertex++)
        {
            if (vertex % 256 == 0 && Cancelled(cancellation)) return null;
            distances[vertex] = new double[bones.Count];
            for (int bone = 0; bone < bones.Count; bone++)
            {
                if (!deform[bone]) continue;
                Vector3 nearest = Geometry3D.GetClosestPointToSegment(points[vertex], rest[bone].Origin, tails[bone]);
                double distance = points[vertex].DistanceTo(nearest);
                distances[vertex][bone] = distance; islandDistance[islands[vertex]][bone] = Math.Min(islandDistance[islands[vertex]][bone], distance);
            }
        }
        var closestIsland = new double[bones.Count]; System.Array.Fill(closestIsland, double.PositiveInfinity);
        foreach (var group in islandDistance) for (int bone = 0; bone < bones.Count; bone++) closestIsland[bone] = Math.Min(closestIsland[bone], group[bone]);
        var weights = new Dictionary<int, double>[points.Length];
        for (int vertex = 0; vertex < points.Length; vertex++)
        {
            if (vertex % 256 == 0 && Cancelled(cancellation)) return null;
            var scores = new Dictionary<int, double>(); double peak = 0;
            for (int bone = 0; bone < bones.Count; bone++)
            {
                if (!deform[bone]) continue;
                double distance = distances[vertex][bone], radius = Math.Max(.0001, Value(boneData[bone], "radius", .25).AsDouble());
                if (method == "Smooth" && groupCount > 1 && islandDistance[islands[vertex]][bone] > closestIsland[bone] + Math.Max(.0001, Math.Min(edge * .1, radius * .1))) continue;
                double score = method == "Envelope" ? Math.Exp(-Math.Pow(distance / radius, 2) * 2) : 1 / Math.Pow(distance + Math.Max(.0001, edge * .5), 3);
                scores[bone] = score; peak = Math.Max(peak, score);
            }
            if (peak <= 1e-30)
            {
                int best = 0; double nearest = double.PositiveInfinity;
                for (int bone = 0; bone < bones.Count; bone++) if (deform[bone] && distances[vertex][bone] < nearest) { nearest = distances[vertex][bone]; best = bone; }
                scores.Clear(); scores[best] = 1;
            }
            else foreach (int bone in scores.Keys.ToArray()) scores[bone] /= peak;
            weights[vertex] = Normalize(scores, influences);
        }
        if (method == "Smooth")
        {
            var anchors = weights.Select(value => new Dictionary<int, double>(value)).ToArray();
            for (int step = 0; step < Math.Clamp(iterations, 0, 24); step++)
            {
                if (Cancelled(cancellation)) return null; var next = new Dictionary<int, double>[points.Length];
                for (int vertex = 0; vertex < points.Length; vertex++)
                {
                    var sum = new Dictionary<int, double>(); foreach (var pair in anchors[vertex]) sum[pair.Key] = pair.Value * .35;
                    foreach (int other in adjacent[vertex]) foreach (var pair in weights[other]) sum[pair.Key] = sum.GetValueOrDefault(pair.Key) + pair.Value * .65 / Math.Max(1, adjacent[vertex].Length);
                    next[vertex] = Normalize(sum, influences);
                }
                weights = next;
            }
        }
        var indexSurfaces = new Godot.Collections.Array<int[]>(); var weightSurfaces = new Godot.Collections.Array<float[]>();
        foreach (Variant mappingValue in mappings)
        {
            int[] mapping = mappingValue.AsInt32Array(); var ids = new int[mapping.Length * influences]; var amounts = new float[ids.Length];
            for (int vertex = 0; vertex < mapping.Length; vertex++)
            {
                var ordered = weights[mapping[vertex]].OrderByDescending(pair => pair.Value).Take(influences).ToArray();
                for (int k = 0; k < ordered.Length; k++) { ids[vertex * influences + k] = ordered[k].Key; amounts[vertex * influences + k] = (float)ordered[k].Value; }
            }
            indexSurfaces.Add(ids); weightSurfaces.Add(amounts);
        }
        if (Cancelled(cancellation)) return null;
        result.Set("indices", indexSurfaces); result.Set("weights", weightSurfaces); return result;
    }
}
