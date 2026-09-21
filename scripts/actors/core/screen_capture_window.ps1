param([long]$WindowHandle, [string]$TabName, [switch]$ListTabs)
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
if ($ListTabs) {
    $captureTabs = @()
    $tabCondition = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::TabItem)
    foreach ($browserProcess in (Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and $_.ProcessName -match '^(chrome|msedge|firefox|brave|opera|vivaldi)$' })) {
        try {
            $browserElement = [System.Windows.Automation.AutomationElement]::FromHandle($browserProcess.MainWindowHandle)
            $browserTabs = $browserElement.FindAll([System.Windows.Automation.TreeScope]::Descendants, $tabCondition)
            foreach ($browserTab in $browserTabs) {
                $captureTabs += @{label=$browserTab.Current.Name; tab_name=$browserTab.Current.Name; input='hwnd=' + $browserProcess.MainWindowHandle.ToInt64(); category='Browser tabs'}
            }
        } catch { }
    }
    ConvertTo-Json -InputObject $captureTabs -Compress
    exit
}
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class CaptureWindow {
	[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out Rect rect);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd, int cmd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hwnd);
}
'@
$captureHandle = [IntPtr]$WindowHandle
[void][CaptureWindow]::SetProcessDPIAware()
if ([CaptureWindow]::IsIconic($captureHandle)) { [void][CaptureWindow]::ShowWindow($captureHandle, 9) }
[void][CaptureWindow]::SetForegroundWindow($captureHandle)
if ($TabName) {
    try {
        $browserElement = [System.Windows.Automation.AutomationElement]::FromHandle($captureHandle)
        $tabCondition = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::TabItem)
        foreach ($browserTab in $browserElement.FindAll([System.Windows.Automation.TreeScope]::Descendants, $tabCondition)) {
            if ($browserTab.Current.Name -eq $TabName) {
                $tabPattern = $browserTab.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
                $tabPattern.Select()
                break
            }
        }
    } catch { exit 1 }
}
$captureRect = New-Object CaptureWindow+Rect
if ([CaptureWindow]::GetWindowRect($captureHandle, [ref]$captureRect)) {
    @{x=$captureRect.Left; y=$captureRect.Top; width=$captureRect.Right-$captureRect.Left; height=$captureRect.Bottom-$captureRect.Top} | ConvertTo-Json -Compress
}
