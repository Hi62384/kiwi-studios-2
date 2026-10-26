using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

// WASAPI shared-mode render loopback. No microphone access, installation or monitoring.
public static class KiwiLoopback {
    public static string Probe() {
        int initialized = CoInitializeEx(IntPtr.Zero, 0);
        Devices devices = null; Device device = null; Client client = null; IntPtr format = IntPtr.Zero;
        try {
            devices = (Devices)new Enumerator(); devices.GetDefaultAudioEndpoint(0, 0, out device);
            Guid iid = new Guid("1CB9AD4C-DBFA-4C32-B178-C2F568A703B2");
            object instance; device.Activate(ref iid, 23, IntPtr.Zero, out instance);
            client = (Client)instance; client.GetMixFormat(out format);
            return "Output device: " + Marshal.ReadInt32(format, 4) + " Hz, " + Marshal.ReadInt16(format, 2) + " channels (no capture started)";
        } finally {
            if (format != IntPtr.Zero) Marshal.FreeCoTaskMem(format);
            if (client != null) Marshal.ReleaseComObject(client);
            if (device != null) Marshal.ReleaseComObject(device);
            if (devices != null) Marshal.ReleaseComObject(devices);
            if (initialized >= 0) CoUninitialize();
        }
    }
    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    class Enumerator {}
    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface Devices {
        void EnumAudioEndpoints(int flow, uint state, out IntPtr list);
        void GetDefaultAudioEndpoint(int flow, int role, out Device device);
        void GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out Device device);
        void RegisterEndpointNotificationCallback(IntPtr callback);
        void UnregisterEndpointNotificationCallback(IntPtr callback);
    }
    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface Device {
        void Activate(ref Guid iid, uint context, IntPtr parameters, [MarshalAs(UnmanagedType.IUnknown)] out object result);
        void OpenPropertyStore(uint access, out IntPtr store);
        void GetId(out IntPtr id);
        void GetState(out uint state);
    }
    [ComImport, Guid("1CB9AD4C-DBFA-4C32-B178-C2F568A703B2"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface Client {
        void Initialize(int mode, uint flags, long duration, long periodicity, IntPtr format, IntPtr session);
        void GetBufferSize(out uint frames);
        void GetStreamLatency(out long latency);
        void GetCurrentPadding(out uint padding);
        void IsFormatSupported(int mode, IntPtr format, out IntPtr closest);
        void GetMixFormat(out IntPtr format);
        void GetDevicePeriod(out long normal, out long minimum);
        void Start();
        void Stop();
        void Reset();
        void SetEventHandle(IntPtr handle);
        void GetService(ref Guid iid, [MarshalAs(UnmanagedType.IUnknown)] out object service);
    }
    [ComImport, Guid("C8ADBD64-E71E-48A0-A4DE-185C395CD317"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface Capture {
        void GetBuffer(out IntPtr data, out uint frames, out uint flags, out ulong position, out ulong counter);
        void ReleaseBuffer(uint frames);
        void GetNextPacketSize(out uint frames);
    }
    [DllImport("ole32.dll")] static extern int CoInitializeEx(IntPtr reserved, uint mode);
    [DllImport("ole32.dll")] static extern void CoUninitialize();

    static float Sample(byte[] data, int offset, int bits, bool floating) {
        if (floating) return BitConverter.ToSingle(data, offset);
        if (bits == 16) return BitConverter.ToInt16(data, offset) / 32768f;
        if (bits == 32) return BitConverter.ToInt32(data, offset) / 2147483648f;
        if (bits == 24) { int n = data[offset] | (data[offset+1] << 8) | (data[offset+2] << 16); return (n << 8) / 2147483648f; }
        return (data[offset] - 128) / 128f;
    }
    static short PCM(float value) { return (short)Math.Max(-32768, Math.Min(32767, value * 32767f)); }
    static void Header(BinaryWriter writer, int rate, long size) {
        writer.Write(new byte[] {82,73,70,70}); writer.Write((uint)(size + 36));
        writer.Write(new byte[] {87,65,86,69,102,109,116,32}); writer.Write(16u);
        writer.Write((ushort)1); writer.Write((ushort)2); writer.Write(rate);
        writer.Write(rate * 4); writer.Write((ushort)4); writer.Write((ushort)16);
        writer.Write(new byte[] {100,97,116,97}); writer.Write((uint)size);
    }
    public static void Run(string output, string stop, string ready) {
        int initialized = CoInitializeEx(IntPtr.Zero, 0);
        Devices devices = null; Device device = null; Client client = null; Capture capture = null;
        IntPtr format = IntPtr.Zero;
        try {
            devices = (Devices)new Enumerator();
            devices.GetDefaultAudioEndpoint(0, 0, out device);
            Guid clientID = new Guid("1CB9AD4C-DBFA-4C32-B178-C2F568A703B2");
            object instance; device.Activate(ref clientID, 23, IntPtr.Zero, out instance);
            client = (Client)instance; client.GetMixFormat(out format);
            int tag = (ushort)Marshal.ReadInt16(format, 0);
            int channels = (ushort)Marshal.ReadInt16(format, 2);
            int rate = Marshal.ReadInt32(format, 4);
            int block = (ushort)Marshal.ReadInt16(format, 12);
            int bits = (ushort)Marshal.ReadInt16(format, 14);
            bool floating = tag == 3 || (tag == 65534 && Marshal.ReadInt32(format, 24) == 3);
            if (!(bits == 8 || bits == 16 || bits == 24 || bits == 32) || (floating && bits != 32))
                throw new NotSupportedException("Unsupported output-device audio format.");
            client.Initialize(0, 0x20000, 1000000, 0, format, IntPtr.Zero);
            Guid captureID = new Guid("C8ADBD64-E71E-48A0-A4DE-185C395CD317");
            object service; client.GetService(ref captureID, out service); capture = (Capture)service;
            using (FileStream file = new FileStream(output, FileMode.CreateNew, FileAccess.ReadWrite, FileShare.ReadWrite))
            using (BinaryWriter writer = new BinaryWriter(file)) {
                Header(writer, rate, 0);
                client.Start();
                double origin = System.Diagnostics.Stopwatch.GetTimestamp() / (double)System.Diagnostics.Stopwatch.Frequency;
                File.WriteAllText(ready, "READY:" + rate);
                var clock = System.Diagnostics.Stopwatch.StartNew();
                long written = 0;
                long checkpoint = 0;
                const long maxFrames = (2L * 1024 * 1024 * 1024 - 44) / 4;
                while (!File.Exists(stop)) {
                    uint packet; capture.GetNextPacketSize(out packet);
                    while (packet > 0) {
                        IntPtr pointer; uint frames, flags; ulong position, counter;
                        capture.GetBuffer(out pointer, out frames, out flags, out position, out counter);
                        try {
                            double timestamp = (flags & 4) == 0 ? counter / 10000000.0 - origin : clock.Elapsed.TotalSeconds - frames / (double)rate;
                            long packetStart = Math.Max(0, (long)(timestamp * rate));
                            if (packetStart + frames > maxFrames) throw new IOException("System take reached the 2 GiB capture limit; checkpointed audio was retained.");
                            while (written < packetStart) { writer.Write((short)0); writer.Write((short)0); written++; }
                            byte[] buffer = new byte[frames * block];
                            if ((flags & 2) == 0) Marshal.Copy(pointer, buffer, 0, buffer.Length);
                            for (int frame = 0; frame < frames; frame++) {
                                float left = 0, right = 0;
                                if ((flags & 2) == 0) {
                                    left = Sample(buffer, frame * block, bits, floating);
                                    right = channels > 1 ? Sample(buffer, frame * block + bits / 8, bits, floating) : left;
                                    // Include remaining surround channels at reduced gain.
                                    for (int channel = 2; channel < channels; channel++) {
                                        float extra = Sample(buffer, frame * block + channel * bits / 8, bits, floating) * 0.5f;
                                        if ((channel & 1) == 0) left += extra; else right += extra;
                                    }
                                }
                                writer.Write(PCM(left)); writer.Write(PCM(right)); written++;
                            }
                        } finally { capture.ReleaseBuffer(frames); }
                        capture.GetNextPacketSize(out packet);
                    }
                    // Some output devices stop issuing loopback packets during silence.
                    long silentTarget = Math.Max(0, (long)((clock.Elapsed.TotalSeconds - 0.1) * rate));
                    if (silentTarget > maxFrames) break;
                    while (written < silentTarget) { writer.Write((short)0); writer.Write((short)0); written++; }
                    if (clock.ElapsedMilliseconds >= checkpoint) {
                        long end = file.Position; file.Position = 0; Header(writer, rate, written * 4);
                        file.Position = end; checkpoint = clock.ElapsedMilliseconds + 1000;
                    }
                    writer.Flush();
                    Thread.Sleep(10);
                }
                client.Stop();
                long target = Math.Min(maxFrames, (long)(clock.Elapsed.TotalSeconds * rate));
                while (written < target) { writer.Write((short)0); writer.Write((short)0); written++; }
                file.Position = 0; Header(writer, rate, written * 4); writer.Flush();
            }
        } finally {
            if (capture != null) Marshal.ReleaseComObject(capture);
            if (client != null) Marshal.ReleaseComObject(client);
            if (device != null) Marshal.ReleaseComObject(device);
            if (devices != null) Marshal.ReleaseComObject(devices);
            if (format != IntPtr.Zero) Marshal.FreeCoTaskMem(format);
            if (initialized >= 0) CoUninitialize();
        }
    }
}
