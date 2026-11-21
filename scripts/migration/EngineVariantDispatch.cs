using Godot;
using System;
using System.Collections.Generic;
using System.Threading;
using GArray = Godot.Collections.Array;

/// <summary>Engine-side calls that preserve raw Variant object/callable ownership.</summary>
internal static class EngineVariantDispatch
{
    [ThreadStatic] private static Dictionary<string, Stack<Expression>>? _expressions;
    [ThreadStatic] private static int _threadGeneration;
    private static int _generation = 1;
    private static readonly object RegistryLock = new();
    private static readonly List<Dictionary<string, Stack<Expression>>> Registry = new();
    private static Variant Execute(string code, string[] names, GArray inputs)
    {
        int generation = Volatile.Read(ref _generation);
        if (_expressions == null || _threadGeneration != generation)
        {
            _expressions = new Dictionary<string, Stack<Expression>>(StringComparer.Ordinal);
            _threadGeneration = generation;
            lock (RegistryLock) Registry.Add(_expressions);
        }
        var pools = _expressions;
        if (!pools.TryGetValue(code, out var pool)) pools[code] = pool = new Stack<Expression>();
        Expression expression;
        if (pool.Count > 0) expression = pool.Pop();
        else
        {
            expression = new Expression();
            if (expression.Parse(code, names) != Error.Ok)
            {
                string message = expression.GetErrorText(); expression.Dispose();
                throw new InvalidOperationException("Native Variant dispatch could not compile: " + message);
            }
        }
        try
        {
            var result = expression.Execute(inputs);
            if (expression.HasExecuteFailed()) GD.PushError("Native Variant dispatch failed: " + expression.GetErrorText());
            return result;
        }
        finally
        {
            if (generation == Volatile.Read(ref _generation)) pool.Push(expression);
            else expression.Dispose();
        }
    }
    // Called only after MigrationBootstrap has stopped and joined native jobs.
    internal static void ClearCaches()
    {
        lock (RegistryLock)
        {
            Interlocked.Increment(ref _generation);
            foreach (var cache in Registry)
            {
                foreach (var pool in cache.Values) while (pool.Count > 0) pool.Pop().Dispose();
                cache.Clear();
            }
            Registry.Clear(); _expressions = null;
        }
    }
    internal static bool CallableValid(Variant callback)
    {
        if (callback.VariantType != Variant.Type.Callable) return false;
        using var inputs = new GArray { callback };
        return Execute("callback.is_valid()", new[] { "callback" }, inputs).AsBool();
    }
    internal static Variant InvokeCallable(Variant callback, GArray arguments)
    {
        if (!CallableValid(callback)) return default;
        using var inputs = new GArray { callback, arguments };
        return Execute("callback.callv(arguments)", new[] { "callback", "arguments" }, inputs);
    }
    internal static Variant Weak(Variant value)
    {
        using var inputs = new GArray { value };
        return Execute("weakref(target_object)", new[] { "target_object" }, inputs);
    }
    internal static Variant BuiltinCall(Variant target, string method, GArray arguments)
    {
        // The method names are native implementation constants, never evaluated user code.
        foreach (char c in method)
            if (!(char.IsAsciiLetterOrDigit(c) || c == '_'))
                throw new ArgumentException("Invalid built-in method name.", nameof(method));
        using var inputs = new GArray { target, arguments };
        var names = new string[arguments.Count];
        for (int i = 0; i < names.Length; i++) names[i] = "arguments[" + i + "]";
        return Execute("target_value." + method + "(" + string.Join(",", names) + ")",
            new[] { "target_value", "arguments" }, inputs);
    }
    internal static Variant Call(Variant target, string method, GArray arguments)
    {
        using var inputs = new GArray { target, method, arguments };
        return Execute("target_object.callv(method_name, arguments)", new[] { "target_object", "method_name", "arguments" }, inputs);
    }
}
