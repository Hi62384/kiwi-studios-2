using Godot;
using System;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Collections.Generic;

public partial class ShaderCodeEditorOperations : RefCounted
{
    private static T Field<T>(Control owner, string name) where T : GodotObject => (T)owner.Get(name).AsGodotObject();
    private static CodeEdit Code(Control owner) => Field<CodeEdit>(owner, "code");
    private static void ClearFocus() => FocusableKeyInput.current_focused_instance = null;
    public string[] lines_without_comments(Control owner)
    {
        bool block = false;
        return Code(owner).Text.Split('\n').Select(raw =>
        {
            var clean = new StringBuilder();
            for (int i = 0; i < raw.Length; i++)
            {
                if (block) { int end = raw.IndexOf("*/", i, StringComparison.Ordinal); if (end < 0) break; block = false; i = end + 1; continue; }
                if (i + 1 < raw.Length && raw[i] == '/' && raw[i + 1] == '*') { block = true; i++; continue; }
                if (i + 1 < raw.Length && raw[i] == '/' && raw[i + 1] == '/') break;
                clean.Append(raw[i]);
            }
            return clean.ToString();
        }).ToArray();
    }
    private static readonly Regex ShaderType = new(@"(?m)^\s*shader_type\s+(spatial|canvas_item|particles|sky|fog)\s*;", RegexOptions.CultureInvariant);
    public void validate_syntax(Control owner)
    {
        var code = Code(owner);
        for (int i = 0; i < code.GetLineCount(); i++) code.SetLineBackgroundColor(i, Colors.Transparent);
        var errors = new List<(int Line, string Message)>();
        void Error(int line, string message) => errors.Add((line, message));
        string[] lines = lines_without_comments(owner);
        string source = string.Join('\n', lines);
        var shaderType = ShaderType.Match(source);
        if (!shaderType.Success) Error(0, "Missing or invalid shader_type declaration.");
        // Declarations may wrap over lines. Diagnose a missing terminator only
        // after reaching a block boundary or end of source.
        foreach (Match uniform in Regex.Matches(source, @"\buniform\b[^;{}]*(?=[;{}]|$)"))
        {
            int end = uniform.Index + uniform.Length;
            if (end >= source.Length || source[end] != ';') Error(source.AsSpan(0, uniform.Index).Count('\n'), "Uniform declaration needs a semicolon.");
        }
        var structs = new Regex(@"\bstruct\s+([A-Za-z_][A-Za-z0-9_]*)\s*\{");
        string typePattern = @"bool|int|uint|float|vec[234]|ivec[234]|uvec[234]|bvec[234]|mat[234]|sampler\w+";
        foreach (string name in structs.Matches(source).Select(m => m.Groups[1].Value).Distinct()) typePattern += "|" + name;
        var declaration = new Regex(@"(?:^|[,(;{}])\s*(?:uniform\s+|varying\s+|const\s+|in\s+|out\s+|inout\s+)?(?:lowp\s+|mediump\s+|highp\s+)?(?:" + typePattern + @")\s+([A-Za-z_][A-Za-z0-9_]*)");
        var multipleDeclaration = new Regex(@"(?:^|[;{}])\s*(?:const\s+)?(?:lowp\s+|mediump\s+|highp\s+)?(?:" + typePattern + @")\s+([^;{}]+);");
        var function = new Regex(@"^\s*(?:void|" + typePattern + @")\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(");
        var declarations = new Dictionary<string, int>();
        var scopes = new List<Dictionary<string, int>> { new() };
        var builtins = new HashSet<string>(("VERTEX NORMAL TANGENT BINORMAL POSITION UV UV2 COLOR POINT_SIZE MODEL_MATRIX MODELVIEW_MATRIX VIEW_MATRIX PROJECTION_MATRIX INV_VIEW_MATRIX INV_PROJECTION_MATRIX MODEL_NORMAL_MATRIX CAMERA_POSITION_WORLD NODE_POSITION_WORLD VIEW ALBEDO ALPHA ALPHA_SCISSOR_THRESHOLD METALLIC SPECULAR ROUGHNESS RIM RIM_TINT CLEARCOAT CLEARCOAT_GLOSS ANISOTROPY ANISOTROPY_FLOW SSS_STRENGTH SSS_TRANSMITTANCE_COLOR SSS_TRANSMITTANCE_DEPTH SSS_TRANSMITTANCE_BOOST BACKLIGHT AO AO_LIGHT_AFFECT EMISSION NORMAL_MAP NORMAL_MAP_DEPTH DEPTH TIME PI TAU E CLEARCOAT_ROUGHNESS DIFFUSE_LIGHT SPECULAR_LIGHT LIGHT LIGHT_COLOR ATTENUATION LIGHT_IS_DIRECTIONAL").Split(' '));
        string extra = shaderType.Groups[1].Value switch
        {
            "fog" => "DENSITY WORLD_POSITION OBJECT_POSITION UVW SIZE SDF",
            "particles" => "ACTIVE CUSTOM TRANSFORM VELOCITY MASS RESTART RESTART_POSITION RESTART_ROT_SCALE RESTART_VELOCITY RESTART_COLOR RESTART_CUSTOM DELTA LIFETIME NUMBER INDEX RANDOM_SEED EMISSION_TRANSFORM COLLIDED COLLISION_NORMAL COLLISION_DEPTH ATTRACTOR_FORCE",
            "sky" => "EYEDIR SKY_COORDS SCREEN_UV FOG RADIANCE HALF_RES_COLOR QUARTER_RES_COLOR",
            "canvas_item" => "TEXTURE TEXTURE_PIXEL_SIZE SCREEN_UV SCREEN_PIXEL_SIZE FRAGCOORD LIGHT SHADOW_MODULATE LIGHT_VERTEX SHADOW_VERTEX NORMAL_TEXTURE SPECULAR_SHININESS SPECULAR_SHININESS_TEXTURE",
            _ => ""
        };
        builtins.UnionWith(extra.Split(' ', StringSplitOptions.RemoveEmptyEntries));
        for (int line = 0; line < lines.Length; line++)
        {
            string text = lines[line];
            foreach (Match multiple in multipleDeclaration.Matches(text))
            {
                string body = multiple.Groups[1].Value; int depth = 0;
                for (int i = 0; i < body.Length; i++)
                {
                    if (body[i] is '(' or '[') depth++;
                    else if (body[i] is ')' or ']') depth--;
                    else if (body[i] == ',' && depth == 0)
                    {
                        var name = Regex.Match(body[(i + 1)..], @"^\s*([A-Za-z_][A-Za-z0-9_]*)");
                        if (name.Success) declarations[name.Groups[1].Value] = line;
                    }
                }
            }
            string trimmed = text.TrimStart(' ', '\t'); int leadingCloses = 0;
            while (leadingCloses < trimmed.Length && trimmed[leadingCloses] == '}') { if (scopes.Count > 1) scopes.RemoveAt(scopes.Count - 1); leadingCloses++; }
            var signature = function.Match(text); bool isSignature = signature.Success || structs.IsMatch(text);
            if (isSignature) scopes.Add(new());
            foreach (Match match in declaration.Matches(text))
            {
                string name = match.Groups[1].Value;
                if (signature.Success && name == signature.Groups[1].Value && match.Groups[1].Index == signature.Groups[1].Index) continue;
                var scope = scopes[^1];
                if (scope.TryGetValue(name, out int previous)) Error(line, $"'{name}' is already declared on line {previous + 1} in this scope.");
                else if (builtins.Contains(name)) Error(line, $"'{name}' conflicts with a built-in shader variable.");
                else { scope[name] = line; declarations[name] = line; }
            }
            int opens = text.Count(c => c == '{'), closes = text.Count(c => c == '}') - leadingCloses;
            if (isSignature && opens > 0) opens--;
            for (int i = 0; i < opens; i++) scopes.Add(new());
            for (int i = 0; i < closes && scopes.Count > 1; i++) scopes.RemoveAt(scopes.Count - 1);
        }
        var stack = new Stack<(char Character, int Line)>();
        var pairs = new Dictionary<char, char> { [')'] = '(', [']'] = '[', ['}'] = '{' };
        string previousSemantic = "";
        var nextSemantics = new string[lines.Length]; string following = "";
        for (int i = lines.Length - 1; i >= 0; i--) { nextSemantics[i] = following; if (lines[i].Trim() != "") following = lines[i].Trim(); }
        var group = new Regex(@"^group_uniforms(?:\s+[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)?)?\s*;");
        var singleToken = new Regex(@"^[A-Za-z_][A-Za-z0-9_]*\s*;?$");
        var twoTokens = new Regex(@"^[A-Za-z_][A-Za-z0-9_]*\s+[A-Za-z_][A-Za-z0-9_]*\s*;?$");
        var assignment = new Regex(@"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*(?:=|\+=|-=|\*=|/=)");
        for (int line = 0; line < lines.Length; line++)
        {
            foreach (char c in lines[line])
            {
                if (c is '(' or '[' or '{') stack.Push((c, line));
                else if (pairs.TryGetValue(c, out char opening))
                {
                    if (stack.Count == 0 || stack.Peek().Character != opening) Error(line, $"Unexpected closing '{c}'.");
                    else stack.Pop();
                }
            }
            string semantic = lines[line].Trim();
            bool uniformGroup = group.IsMatch(semantic);
            if (semantic.StartsWith("group_uniforms", StringComparison.Ordinal) && !uniformGroup) Error(line, "Invalid uniform group declaration. Use group_uniforms Group.Subgroup; or group_uniforms;");
            bool isReturn = Regex.IsMatch(semantic, @"^return(?:\s+.+)?;?$");
            bool previousContinues = new[] { "+", "-", "*", "/", "%", "=", "(", "[", ",", "?", ":", "&&", "||", "<", ">" }.Any(op => previousSemantic.EndsWith(op, StringComparison.Ordinal));
            string next = nextSemantics[line];
            bool nextContinues = new[] { "+", "-", "*", "/", "%", "&&", "||", "?", ":" }.Any(op => next.StartsWith(op, StringComparison.Ordinal));
            if (!uniformGroup && !previousContinues && !nextContinues && singleToken.IsMatch(semantic) && !new[] { "discard", "return", "else", "break", "continue" }.Contains(semantic.TrimEnd(';')))
                Error(line, $"Unexpected token '{semantic.TrimEnd(';')}'.");
            else if (twoTokens.IsMatch(semantic) && !uniformGroup && !isReturn && !new[] { "shader_type ", "render_mode ", "struct " }.Any(prefix => semantic.StartsWith(prefix, StringComparison.Ordinal)) && !declaration.IsMatch(semantic)) Error(line, "Unrecognized statement.");
            var assigned = assignment.Match(semantic);
            if (assigned.Success && !declarations.ContainsKey(assigned.Groups[1].Value) && !builtins.Contains(assigned.Groups[1].Value)) Error(line, $"Unknown variable '{assigned.Groups[1].Value}'.");
            if (semantic != "") previousSemantic = semantic;
        }
        foreach (var opening in stack.Reverse()) Error(opening.Line, $"Unclosed '{opening.Character}'.");
        var unique = errors.Distinct().OrderBy(e => e.Line).ToArray();
        foreach (var error in unique) code.SetLineBackgroundColor(Math.Clamp(error.Line, 0, Math.Max(code.GetLineCount() - 1, 0)), new Color(.42f, .08f, .08f, .48f));
        var diagnostics = Field<Label>(owner, "diagnostics");
        diagnostics.Visible = unique.Length != 0;
        diagnostics.Text = string.Join("  •  ", unique.Take(4).Select(e => $"Line {e.Line + 1}: {e.Message}"));
    }
}
