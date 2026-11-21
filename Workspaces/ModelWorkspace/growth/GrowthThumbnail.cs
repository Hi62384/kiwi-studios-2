using Godot;
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

public partial class GrowthMaterialOperations
{
    private readonly Dictionary<long, Texture2D> _thumbnails = new();
    private readonly SurfaceGrowthGeometry _geometry = new();
    private readonly SurfaceGrowthSettings _settings = new();
    private static string Number(double value) => value.ToString("0.00", CultureInfo.InvariantCulture);
    public Texture2D texture(Resource? style, Resource? material)
    {
        var colors = new GArray(); var gradient = material?.Get("gradient").As<Gradient>();
        if (material != null) colors = new GArray { material.Get("root_color"), material.Get("tip_color"), material.Get("mode"), material.Get("pattern"), material.Get("feather_pattern"), gradient != null ? new GArray { gradient.Colors, gradient.Offsets } : new GArray() };
        long key = Hash(new GArray { style != null ? style.Get("values") : new Settings(), style != null ? style.Get("title") : "", colors });
        if (_thumbnails.TryGetValue(key, out var cached)) return cached;
        var data = new KiwiSurfaceGrowthData();
        string title = style?.Get("title").AsString() ?? ""; int kind = title is "Down" or "Contour" or "Flight" or "Tail" or "Stylized feathers" ? 2 : 0;
        data.Set("settings", _settings.defaults(kind)); data.Set("growth_style", ObjectValue(style)); data.Set("source_points", new[] { Vector3.Zero, Vector3.Right, Vector3.Back });
        var stops = new StringBuilder();
        if (gradient != null)
            for (int i = gradient.GetPointCount() - 1; i >= 0; i--) stops.Append("<stop offset=\"").Append(Number(1 - gradient.GetOffset(i))).Append("\" stop-color=\"#").Append(gradient.GetColor(i).ToHtml(false)).Append("\"/>");
        else
        {
            Color tip = material?.Get("tip_color").AsColor() ?? new Color("c7f2e9"), rootColor = material?.Get("root_color").AsColor() ?? new Color("38bda2");
            stops.Append("<stop offset=\"0\" stop-color=\"#").Append(tip.ToHtml(false)).Append("\"/><stop offset=\"1\" stop-color=\"#").Append(rootColor.ToHtml(false)).Append("\"/>");
        }
        var svg = new StringBuilder("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"128\" height=\"128\"><defs><linearGradient id=\"g\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\">"); svg.Append(stops).Append("</linearGradient></defs><rect x=\"1\" y=\"1\" width=\"126\" height=\"126\" rx=\"16\" fill=\"#15212d\" stroke=\"#416071\"/>");
        for (int index = 0; index < (kind == 2 ? 4 : 8); index++)
        {
            var root = new Settings { ["id"] = index, ["triangle"] = new Vector3I(0, 1, 2), ["bary"] = new Vector3(.3f, .4f, .3f), ["normal"] = Vector3.Up, ["random"] = new Vector4(.5f, index / 8f, .4f, .5f), ["position"] = Vector3.Zero, ["density_rank"] = 0.0 };
            var points = _geometry.curve(data, root, -1); double length = 0, width = 0; foreach (Vector3 point in points) { length = Math.Max(length, point.Length()); width = Math.Max(width, Math.Abs(point.X)); }
            double scale = Math.Min(78 / Math.Max(.01, length), 15 / Math.Max(.001, width)), origin = 22 + index * (kind == 2 ? 24 : 11); var line = new StringBuilder();
            foreach (Vector3 point in points) line.Append(Number(origin + point.X * scale)).Append(',').Append(Number(108 - point.Y * scale)).Append(' ');
            if (kind == 2)
            {
                var polygon = new StringBuilder();
                foreach (int direction in new[] { -1, 1 }) for (int i = 0; i < points.Length; i++)
                {
                    int at = direction < 0 ? i : points.Length - 1 - i; double t = (double)at / Math.Max(1, points.Length - 1); Vector3 point = points[at];
                    polygon.Append(Number(origin + point.X * scale + direction * Math.Sin(Math.Pow(t, .65) * Math.PI) * 8)).Append(',').Append(Number(108 - point.Y * scale)).Append(' ');
                }
                svg.Append("<polygon points=\"").Append(polygon).Append("\" fill=\"url(#g)\"/>");
            }
            svg.Append("<polyline points=\"").Append(line).Append("\" fill=\"none\" stroke=\"").Append(kind == 2 ? "#e9d6b3" : "url(#g)").Append("\" stroke-width=\"").Append(kind == 2 ? "1.2" : "2.8").Append("\" stroke-linecap=\"round\"/>");
        }
        if (material != null) svg.Append("<circle cx=\"105\" cy=\"23\" r=\"10\" fill=\"#").Append(material.Get("root_color").AsColor().ToHtml(false)).Append("\" stroke=\"#e2eee9\"/>"); svg.Append("</svg>");
        using var image = new Image(); Error error = image.LoadSvgFromString(svg.ToString()); if (error != Error.Ok) throw new InvalidOperationException("Growth thumbnail SVG failed: " + error);
        var result = ImageTexture.CreateFromImage(image); if (_thumbnails.Count > 128) _thumbnails.Clear(); _thumbnails[key] = result; return result;
    }
}
