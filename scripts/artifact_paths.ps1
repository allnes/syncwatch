# Shared by measurement/fixture launchers; compatible with Windows PowerShell 5.
function Get-SyncWatchPhysicalPath {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not ('SyncWatchArtifactNativePath' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;
public static class SyncWatchArtifactNativePath {
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  static extern SafeFileHandle CreateFile(string name, uint access, uint share,
    IntPtr security, uint creation, uint flags, IntPtr template);
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  static extern uint GetFinalPathNameByHandle(SafeFileHandle handle,
    StringBuilder path, uint length, uint flags);
  public static string Resolve(string path) {
    using (var handle = CreateFile(path, 0, 7, IntPtr.Zero, 3, 0x02000000, IntPtr.Zero)) {
      if (handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());
      var buffer = new StringBuilder(32768);
      var count = GetFinalPathNameByHandle(handle, buffer, (uint)buffer.Capacity, 0);
      if (count == 0 || count >= buffer.Capacity)
        throw new Win32Exception(Marshal.GetLastWin32Error());
      var result = buffer.ToString();
      if (result.StartsWith(@"\\?\UNC\")) return @"\\" + result.Substring(8);
      return result.StartsWith(@"\\?\") ? result.Substring(4) : result;
    }
  }
}
'@
  }
  $ancestor = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
  $ancestor = [IO.Path]::GetFullPath($ancestor)
  $suffix = [Collections.Generic.List[string]]::new()
  while (!(Test-Path -LiteralPath $ancestor)) {
    $suffix.Insert(0, [IO.Path]::GetFileName($ancestor))
    $parent = [IO.Path]::GetDirectoryName($ancestor)
    if (!$parent) { throw "No existing parent for artifact path: $Path" }
    $ancestor = $parent
  }
  $resolved = [SyncWatchArtifactNativePath]::Resolve($ancestor)
  foreach ($part in $suffix) { $resolved = Join-Path $resolved $part }
  return [IO.Path]::GetFullPath($resolved)
}

function Get-SyncWatchExternalArtifactPath {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot)
  )
  $resolved = Get-SyncWatchPhysicalPath $Path
  $root = (Get-SyncWatchPhysicalPath $RepositoryRoot).TrimEnd('\')
  if ($resolved.Equals($root, [StringComparison]::OrdinalIgnoreCase) -or
      $resolved.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "Artifacts must be outside the SyncWatch checkout: $Path"
  }
  return $resolved
}
