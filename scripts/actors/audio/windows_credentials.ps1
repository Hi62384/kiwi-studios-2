$ErrorActionPreference = 'Stop'
try {
    [Console]::InputEncoding = New-Object System.Text.UTF8Encoding($false)
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class KiwiAudioCredentials {
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    private struct Credential {
        public uint Flags, Type;
        public string TargetName, Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public uint CredentialBlobSize;
        public IntPtr CredentialBlob;
        public uint Persist, AttributeCount;
        public IntPtr Attributes;
        public string TargetAlias, UserName;
    }
    [DllImport("advapi32.dll", EntryPoint="CredWriteW", CharSet=CharSet.Unicode, SetLastError=true)]
    private static extern bool Write(ref Credential credential, uint flags);
    [DllImport("advapi32.dll", EntryPoint="CredReadW", CharSet=CharSet.Unicode, SetLastError=true)]
    private static extern bool Read(string target, uint type, uint flags, out IntPtr credential);
    [DllImport("advapi32.dll", EntryPoint="CredDeleteW", CharSet=CharSet.Unicode, SetLastError=true)]
    private static extern bool Delete(string target, uint type, uint flags);
    [DllImport("advapi32.dll")] private static extern void CredFree(IntPtr pointer);
    private static string Target(string id) {
        if (String.IsNullOrEmpty(id) || id.Length>64) throw new ArgumentException();
        foreach (char c in id) if (!(c>='a' && c<='z') && !(c>='0' && c<='9') && c!='_' && c!='-') throw new ArgumentException();
        return "KiwiStudios2/AudioProviders/"+id;
    }
    public static bool Store(string id, string secret) {
        byte[] bytes=Encoding.Unicode.GetBytes(secret);
        if(bytes.Length==0 || bytes.Length>2400) throw new ArgumentException();
        IntPtr blob=Marshal.AllocCoTaskMem(bytes.Length);
        try {
            Marshal.Copy(bytes,0,blob,bytes.Length);
            var value=new Credential {Type=1,TargetName=Target(id),CredentialBlobSize=(uint)bytes.Length,CredentialBlob=blob,Persist=2,UserName="Kiwi Studios 2"};
            return Write(ref value,0);
        } finally {
            for(int i=0;i<bytes.Length;i++)Marshal.WriteByte(blob,i,0);
            Marshal.FreeCoTaskMem(blob);Array.Clear(bytes,0,bytes.Length);
        }
    }
    public static string Load(string id) {
        IntPtr pointer;
        if(!Read(Target(id),1,0,out pointer)) return "";
        try {
            var value=(Credential)Marshal.PtrToStructure(pointer,typeof(Credential));
            if(value.CredentialBlobSize>2400 || value.CredentialBlobSize%2!=0) return "";
            return Marshal.PtrToStringUni(value.CredentialBlob,(int)value.CredentialBlobSize/2);
        } finally {CredFree(pointer);}
    }
    public static bool Remove(string id) {
        return Delete(Target(id),1,0) || Marshal.GetLastWin32Error()==1168;
    }
}
'@ | Out-Null
    $request = [Console]::ReadLine() | ConvertFrom-Json
    switch ($request.action) {
        'write' { $result = @{success=[KiwiAudioCredentials]::Store([string]$request.id,[string]$request.secret)} }
        'read' { $result = @{success=$true;secret=[KiwiAudioCredentials]::Load([string]$request.id)} }
        'delete' { $result = @{success=[KiwiAudioCredentials]::Remove([string]$request.id)} }
        default { throw 'Invalid operation' }
    }
    if (-not $result.success) { $result.error = 'Windows Credential Manager rejected this operation.' }
    $request.secret = ''
    [Console]::WriteLine(($result | ConvertTo-Json -Compress))
} catch {
    [Console]::WriteLine('{"success":false,"error":"Credential operation failed; no secrets were logged."}')
    exit 1
}
