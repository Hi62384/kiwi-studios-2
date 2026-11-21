using Godot;
using System;
using System.Collections.Generic;
using Array = Godot.Collections.Array;
using Settings = Godot.Collections.Dictionary;

public partial class CompositingEvaluator : RefCounted
{
    [Export] public string last_error { get; set; } = "";
    [Export] public int nodes_evaluated { get; set; }
    [Export] public int graph_cache_hits { get; set; }
    private readonly Dictionary<long, CompositeBuffer> _cache = new();
    private readonly Dictionary<long, Image> _textCache = new();
    private readonly HashSet<string> _evaluationStack = new();
    private readonly CompositePixelFilters _pixels = new();
    private readonly CompositingDocument _documents = new();
    private readonly CompositeGraph _graphs = new();
    private static string Text(Resource resource, string key) => resource.Get(key).AsString();
    private static double Number(Resource resource, string key) => resource.Get(key).AsDouble();
    private static Variant Value(Settings settings, string key, Variant fallback = default) => settings.TryGetValue(key, out var value) ? value : fallback;
    private static Settings Options(Resource resource) => resource.Get("settings").AsGodotDictionary();
    private static bool CacheEnabled(Resource document) => Value(document.Get("processing_settings").AsGodotDictionary(), "cache", true).AsBool();
    private static long Key(params Variant[] values) => GD.Hash(new Array(values));
    private static Vector2I Canvas(Resource document) => document.Get("canvas_size").AsVector2I();
    private static bool IsDocument(Resource document) => document is CompositingDocument
        || document.GetScript().As<Script>()?.ResourcePath == "res://Workspaces/CompositingWorkspace/compositing_document.gd";
    public void clear_cache() { _cache.Clear(); _textCache.Clear(); }
    private CompositeBuffer? Fail(string message) { last_error = message; return null; }

    private void Store(long key, CompositeBuffer value)
    {
        _cache[key] = value.duplicate_buffer();
        while (_cache.Count > 48) { using var iterator = _cache.Keys.GetEnumerator(); iterator.MoveNext(); _cache.Remove(iterator.Current); }
    }

    public CompositeBuffer? evaluate(Resource? document, double time, bool force = false)
    {
        last_error = ""; nodes_evaluated = 0; graph_cache_hits = 0;
        if (document == null || !IsDocument(document)) return Fail("Composition is missing or invalid.");
        string identity = document.ResourcePath.Length > 0 ? document.ResourcePath : Text(document, "document_id");
        if (!_evaluationStack.Add(identity)) return Fail("Linked composition cycle detected at '" + Text(document, "title") + "'.");
        try
        {
            if (document.Get("working_color_space").AsInt32() != 0) return Fail("The selected working color space is not supported by the float preview backend.");
            string[] errors = _documents.validate_resource(document);
            if (errors.Length > 0) return Fail(string.Join("; ", errors));
            if (!double.IsFinite(time) || time < 0 || time > Number(document, "duration")) return Fail("Requested frame lies outside the composition duration.");
            long key = Key(_documents.signature_resource(document), Math.Round(time * Number(document, "frame_rate"), 5), Canvas(document), document.Get("working_color_space"));
            if (!force && CacheEnabled(document) && _cache.TryGetValue(key, out var cached)) return cached.duplicate_buffer();
            CompositeBuffer output = Transparent(document, time); var seen = new HashSet<string>();
            foreach (Variant value in document.Get("layers").AsGodotArray())
            {
                var item = value.As<Resource>();
                if (item != null && Text(item, "parent_id").Length == 0) output = RenderLayer(document, item, output, time, seen);
            }
            if (last_error.Length > 0) return null;
            output.source_identity = key.ToString();
            if (CacheEnabled(document)) Store(key, output);
            return output;
        }
        finally { _evaluationStack.Remove(identity); }
    }

    private long GraphKey(Resource document, Resource graph, double time, string node) =>
        Key(_documents.signature_resource(document), Text(graph, "id"), node, Math.Round(time * Number(document, "frame_rate"), 5), Canvas(document));

    public CompositeBuffer? evaluate_graph(Resource? document, Resource? graph, double time, bool force = false)
    {
        last_error = "";
        if (document == null || graph == null) return Fail("Composition graph is missing.");
        long key = GraphKey(document, graph, time, Text(graph, "output_node"));
        if (!force && CacheEnabled(document) && _cache.TryGetValue(key, out var cached)) { graph_cache_hits++; return cached.duplicate_buffer(); }
        string[] errors = _graphs.compile_errors_resource(graph);
        if (errors.Length > 0) return Fail(string.Join("; ", errors));
        var result = EvalNode(document, graph, Text(graph, "output_node"), time, new(), new());
        if (result == null) { if (last_error.Length == 0) last_error = "Graph output did not produce an image."; return null; }
        if (CacheEnabled(document)) Store(key, result);
        return result;
    }

    public CompositeBuffer? evaluate_node_output(Resource? document, Resource? graph, string node_id, double time)
    {
        last_error = ""; nodes_evaluated = 0;
        if (document == null || graph == null || _graphs.node_resource(graph, node_id) == null) return Fail("The selected graph node is missing.");
        long key = GraphKey(document, graph, time, node_id);
        if (CacheEnabled(document) && _cache.TryGetValue(key, out var cached)) { graph_cache_hits++; return cached.duplicate_buffer(); }
        var result = EvalNode(document, graph, node_id, time, new(), new());
        if (result != null && CacheEnabled(document)) Store(key, result);
        if (result == null && last_error.Length == 0) last_error = "The selected node does not produce an image.";
        return result;
    }

    private CompositeBuffer? EvalNode(Resource document, Resource graph, string id, double time, Dictionary<string, CompositeBuffer> memo, HashSet<string> visiting)
    {
        if (memo.TryGetValue(id, out var cached)) return cached;
        if (!visiting.Add(id)) return Fail("Graph cycle detected.");
        try
        {
            var node = _graphs.node_resource(graph, id);
            if (node == null) return Fail("Graph contains a missing node.");
            nodes_evaluated++; Settings settings = Options(node); string kind = Text(node, "kind"); CompositeBuffer? result = null;
            CompositeBuffer? Input(string port)
            {
                foreach (Variant value in graph.Get("connections").AsGodotArray())
                {
                    var edge = value.As<Resource>();
                    if (edge != null && Text(edge, "to_node") == id && Text(edge, "to_port") == port)
                        return EvalNode(document, graph, Text(edge, "from_node"), time, memo, visiting);
                }
                return null;
            }
            switch (kind)
            {
                case "Image Source": result = ImageSource(Value(settings, "path", "").AsString(), time); break;
                case "Layer Source":
                    var layer = _documents.layer_resource(document, Value(settings, "layer_id", "").AsString());
                    if (layer == null) return Fail("Layer Source needs a valid layer reference.");
                    var copy = (Resource)layer.Duplicate(true); copy.Set("processing_graph_id", ""); result = LayerSource(document, copy, time); break;
                case "Solid Color": result = Solid(document, Value(settings, "color", Colors.White).AsColor(), time); break;
                case "Over": case "Merge":
                    var foreground = Input("foreground"); var background = Input("background");
                    if (foreground != null && background != null) result = Blend(background, foreground, kind == "Merge" ? Value(settings, "mode", 0).AsInt32() : 0, Value(settings, "opacity", 1d).AsDouble(), null);
                    break;
                case "Color Grade": if (Input("image") is { } grade) result = _grade(grade, settings); break;
                case "Alpha Extract":
                    if (Input("image") is { } alpha) result = Buffer(_pixels.alpha_extract(alpha.image!, Canvas(document).X, Canvas(document).Y), time, "alpha:" + alpha.source_identity, document);
                    break;
                case "Mask":
                    var masked = Input("image"); var matte = Input("mask");
                    if (masked != null && matte != null) { result = Process(masked, _pixels.apply_matte(masked.image!, matte.image!), "matte:" + masked.source_identity + ":" + matte.source_identity); result.frame_time = time; }
                    break;
                case "Blur": if (Input("image") is { } blur) result = _blur(blur, Value(settings, "radius", 2).AsInt32()); break;
                case "Chroma Key": if (Input("image") is { } chroma) result = _chroma_key(chroma, settings); break;
                case "Luma Key": if (Input("image") is { } luma) result = _luma_key(luma, settings); break;
                case "Depth Compare": return Fail("Depth Compare requires a typed depth input and is not available in the CPU preview backend yet.");
                case "Output": result = Input("image"); break;
            }
            if (result == null && last_error.Length == 0) last_error = $"Node '{kind}' is missing a required input or source.";
            if (result != null) memo[id] = result;
            return result;
        }
        finally { visiting.Remove(id); }
    }

    private CompositeBuffer RenderLayer(Resource document, Resource original, CompositeBuffer backdrop, double time, HashSet<string> seen)
    {
        string id = Text(original, "id"); double end = Number(original, "end_time");
        if (!original.Get("visible").AsBool() || seen.Contains(id) || time < Number(original, "start_time") || end >= 0 && time >= end) return backdrop;
        int kind = original.Get("kind").AsInt32(); string solo = Text(document, "solo_layer_id");
        if (solo.Length > 0 && !SoloContains(document, id, solo) && !(kind == 9 && SoloContains(document, solo, id))) return backdrop;
        seen.Add(id); var layer = _animated_layer(document, original, time);
        if (kind == 8)
        {
            var adjusted = _grade(backdrop, Options(layer));
            return Process(backdrop, _pixels.mix_adjustment(backdrop.image!, adjusted.image!, (float)Number(layer, "opacity"), Mask(document, Text(layer, "mask_id"), time)), "adjustment:" + backdrop.source_identity);
        }
        CompositeBuffer? source;
        if (kind == 9)
        {
            source = Transparent(document, time); var local = new HashSet<string>(seen);
            foreach (Variant value in document.Get("layers").AsGodotArray())
            { var child = value.As<Resource>(); if (child != null && Text(child, "parent_id") == id) source = RenderLayer(document, child, source, time, local); }
        }
        else source = LayerSource(document, layer, time);
        if (source == null) return backdrop;
        var transformed = Transform(document, source, layer, time);
        return Blend(backdrop, transformed, layer.Get("blend_mode").AsInt32(), Number(layer, "opacity"), Mask(document, Text(layer, "mask_id"), time));
    }

    public Resource _animated_layer(Resource document, Resource source, double time)
    {
        var result = (Resource)source.Duplicate(true);
        foreach (string property in new[] { "position", "rotation", "scale", "opacity" })
            if (_documents.has_layer_track_resource(document, Text(source, "id"), property)) result.Set(property, _documents.sample_layer_value_resource(document, Text(source, "id"), property, time, source.Get(property)));
        return result;
    }
    private bool SoloContains(Resource document, string id, string solo)
    {
        var visited = new HashSet<string>(); var current = _documents.layer_resource(document, id);
        while (current != null && visited.Add(Text(current, "id")))
        { if (Text(current, "id") == solo) return true; current = _documents.layer_resource(document, Text(current, "parent_id")); }
        return false;
    }

    private CompositeBuffer? LayerSource(Resource document, Resource layer, double time)
    {
        string path = Text(layer, "source_path"), name = Text(layer, "name"), graphId = Text(layer, "processing_graph_id");
        if (graphId.Length > 0)
        {
            foreach (Variant value in document.Get("graphs").AsGodotArray())
            { var graph = value.As<Resource>(); if (graph != null && Text(graph, "id") == graphId) return evaluate_graph(document, graph, time); }
            return Fail(name + " references a missing processing graph.");
        }
        int kind = layer.Get("kind").AsInt32(); Settings settings = Options(layer);
        if (kind == 1) return Solid(document, layer.Get("color").AsColor(), time);
        if (kind == 6)
        {
            var shape = _pixels.shape(Value(settings, "size", new Vector2I(256, 256)).AsVector2I(), Value(settings, "shape", "rectangle").AsString(), layer.Get("color").AsColor(), Value(settings, "points", System.Array.Empty<Vector2>()).AsVector2Array());
            return Buffer(_pixels.normalize(shape, true, false), time, "shape:" + Text(layer, "id"), document);
        }
        if (kind == 5) return TextSource(document, layer, time);
        if (kind == 2)
        {
            double sourceTime = source_time_for_layer(layer, time);
            var texture = GD.Load<CSharpScript>("res://scripts/actors/core/ActorVideo.cs").Call("frame", path, sourceTime, true).As<Texture2D>();
            if (texture == null) return Fail("Waiting for the requested video frame: " + path);
            var frame = texture.GetImage();
            if (frame == null || frame.IsEmpty()) return Fail("The requested video frame could not be read.");
            return Buffer(_pixels.normalize(frame, true, false), time, path + "@" + sourceTime);
        }
        var sourceTexture = layer.Get("source_image").As<Texture2D>();
        if (kind == 0 || kind is 3 or 4 or 7 && (sourceTexture != null || path.Length > 0))
        {
            Image? image = sourceTexture?.GetImage();
            if (image == null && path.Length > 0) image = Image.LoadFromFile(ProjectSettings.GlobalizePath(path));
            if (image == null || image.IsEmpty()) return Fail(kind == 0 ? "Image source is missing or unreadable: " + path : name + " render or mask source is missing.");
            bool srgb = kind == 0 || !Value(settings, "scene_linear", false).AsBool();
            bool premultiplied = kind != 0 && Value(settings, "premultiplied", false).AsBool();
            return Buffer(_pixels.normalize(image, srgb, premultiplied), time, path.Length > 0 ? path : sourceTexture?.ResourcePath ?? "");
        }
        if (kind is 3 or 4) return Fail(name + " needs a baked render-pass source. Live scene rendering is not yet available.");
        if (kind == 10)
        {
            if (path.Length == 0 || !ResourceLoader.Exists(path)) return Fail(name + " references a missing composition resource.");
            var linked = ResourceLoader.Load<Resource>(path);
            if (linked == null || !IsDocument(linked)) return Fail(name + " could not load its linked composition.");
            double linkedTime = source_time_for_layer(layer, time);
            if (linkedTime > Number(linked, "duration")) return Fail(name + " maps to a time outside its linked composition.");
            return evaluate(linked, linkedTime);
        }
        return Fail(name + " does not produce an image in the current preview backend.");
    }

    public double source_time_for_layer(Resource layer, double time) => Number(layer, "source_time_offset") + Math.Max(0, time - Number(layer, "start_time")) * Number(layer, "playback_speed");
    private CompositeBuffer? ImageSource(string path, double time)
    {
        if (path.Length == 0) return Fail("Image Source node needs a file path.");
        var image = Image.LoadFromFile(ProjectSettings.GlobalizePath(path));
        if (image == null || image.IsEmpty()) return Fail("Image Source node cannot read: " + path);
        return Buffer(_pixels.normalize(image, true, false), time, path);
    }
    private static CompositeBuffer Buffer(Image image, double time, string identity = "", Resource? document = null) => new()
    { image = image, frame_time = time, source_identity = identity, pixel_aspect_ratio = document == null ? 1 : (float)Number(document, "pixel_aspect_ratio") };
    private CompositeBuffer Solid(Resource document, Color color, double time)
    {
        Vector2I size = Canvas(document); var image = Image.CreateEmpty(size.X, size.Y, false, Image.Format.Rgbaf); image.Fill(color.SrgbToLinear());
        return Buffer(image, time, "", document);
    }
    private CompositeBuffer Transparent(Resource document, double time) { var result = Solid(document, Colors.Transparent, time); result.source_identity = "transparent"; return result; }
    private CompositeBuffer Transform(Resource document, CompositeBuffer source, Resource layer, double time) =>
        Buffer(_pixels.transform(source.image!, Canvas(document), layer.Get("position").AsVector2(), (float)Number(layer, "rotation"), layer.Get("scale").AsVector2(), layer.Get("anchor").AsVector2(), source.color_space == "srgb"), time, "transparent", document);
    private Image? Mask(Resource document, string id, double time)
    {
        if (id.Length == 0) return null;
        var layer = _documents.layer_resource(document, id);
        if (layer == null) { last_error = "A layer references a missing mask."; return null; }
        var source = LayerSource(document, layer, time); if (source == null) return null;
        var transformed = Transform(document, source, layer, time);
        return Math.Abs(Number(layer, "opacity") - 1) > .00001 ? _pixels.opacity(transformed.image!, (float)Number(layer, "opacity")) : transformed.image;
    }
    private CompositeBuffer Blend(CompositeBuffer backdrop, CompositeBuffer source, int mode, double opacity, Image? mask)
    {
        var result = Process(backdrop, _pixels.blend(backdrop.image!, source.image!, mode, (float)opacity, mask, source.color_space == "srgb"), "merge:" + backdrop.source_identity + ":" + source.source_identity);
        result.frame_time = source.frame_time; return result;
    }
    private static CompositeBuffer Process(CompositeBuffer source, Image image, string? identity = null)
    { var result = source.duplicate_buffer(); result.image = image; if (identity != null) result.source_identity = identity; return result; }
    public CompositeBuffer _grade(CompositeBuffer source, Settings settings) => Process(source, _pixels.grade(source.image!, settings));
    public CompositeBuffer _chroma_key(CompositeBuffer source, Settings settings) => Process(source, _pixels.chroma_key(source.image!, settings), "chroma:" + source.source_identity);
    public CompositeBuffer _luma_key(CompositeBuffer source, Settings settings) => Process(source, _pixels.luma_key(source.image!, settings), "luma_key:" + source.source_identity);
    public CompositeBuffer _blur(CompositeBuffer source, int radius) => Process(source, _pixels.blur(source.image!, radius));
    public float _curve_sample(Array points, float value) => _pixels.curve_sample(points, value);
    public float _mask_coverage(Color color) => Math.Clamp(color.A * (color.R * .2126f + color.G * .7152f + color.B * .0722f), 0, 1);

    private CompositeBuffer? TextSource(Resource document, Resource layer, double time)
    {
        Settings settings = Options(layer); Vector2I size = Value(settings, "size", new Vector2I(640, 180)).AsVector2I();
        size.X = Math.Clamp(size.X, 1, 4096); size.Y = Math.Clamp(size.Y, 1, 2048);
        string text = Value(settings, "text", "Text").AsString(), path = Value(settings, "font_path", "").AsString(), id = Text(layer, "id");
        int fontSize = Math.Clamp(Value(settings, "font_size", 72).AsInt32(), 1, 512); Color color = layer.Get("color").AsColor();
        long key = Key(id, text, fontSize, path, color, size);
        if (_textCache.TryGetValue(key, out var cached)) return Buffer((Image)cached.Duplicate(), time, "text:" + id + ":" + text, document);
        Image? image;
        if (DisplayServer.GetName() == "headless") image = CompositeBitmapFont.Render(size, text, fontSize, color);
        else
        {
            Font? font = ThemeDB.FallbackFont;
            if (path.Length > 0 && ResourceLoader.Exists(path) && ResourceLoader.Load(path) is Font loadedFont) font = loadedFont;
            if (font == null) return Fail(Text(layer, "name") + " cannot find a usable font.");
            if (Engine.GetMainLoop() is not SceneTree tree) return Fail("Text rendering needs an active scene tree.");
            var viewport = new SubViewport { Size = size, TransparentBg = true, GuiDisableInput = true, RenderTargetUpdateMode = SubViewport.UpdateMode.Once };
            tree.Root.AddChild(viewport);
            try
            {
                var canvas = new Control { Size = size }; viewport.AddChild(canvas);
                using var line = new TextLine(); line.AddString(text, font, fontSize);
                line.Draw(canvas.GetCanvasItem(), new Vector2(2, 2), color);
                RenderingServer.ForceDraw(true, 0); image = viewport.GetTexture().GetImage();
            }
            finally { viewport.Free(); }
        }
        if (image == null || image.IsEmpty()) return Fail(Text(layer, "name") + " text could not be rasterized.");
        var normalized = _pixels.normalize(image, true, false); _textCache[key] = (Image)normalized.Duplicate();
        while (_textCache.Count > 32) { using var iterator = _textCache.Keys.GetEnumerator(); iterator.MoveNext(); _textCache.Remove(iterator.Current); }
        return Buffer(normalized, time, "text:" + id + ":" + text, document);
    }
}
