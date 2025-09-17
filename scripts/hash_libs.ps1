Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead('pulled_app.apk')
$entries = $zip.Entries | Where-Object { $_.FullName -like 'lib/*/liblc3.so' }
foreach ($e in $entries) {
  $stream = $e.Open()
  $sha = [System.Security.Cryptography.SHA256]::Create()
  $hash = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','').ToLower()
  Write-Output ($e.FullName + ' ' + $e.Length + ' ' + $hash)
  $stream.Close()
}
$zip.Dispose()

# local jniLibs
$localPaths = @('android/app/src/main/jniLibs/arm64-v8a/liblc3.so','android/app/src/main/jniLibs/armeabi-v7a/liblc3.so')
foreach ($p in $localPaths) {
  if (Test-Path $p) {
    $bytes = [IO.File]::ReadAllBytes($p)
    $h = [BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)).Replace('-','').ToLower()
    Write-Output ($p + ' ' + ([IO.File]::GetLength((Get-Item $p))) + ' ' + $h)
  } else {
    Write-Output ($p + ' MISSING')
  }
}

# cxx obj outputs (best-effort glob)
$glob = Get-ChildItem -Path build -Recurse -Filter liblc3.so -ErrorAction SilentlyContinue | Select-Object -First 10
foreach ($f in $glob) {
  $bytes = [IO.File]::ReadAllBytes($f.FullName)
  $h = [BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)).Replace('-','').ToLower()
  Write-Output ($f.FullName + ' ' + $f.Length + ' ' + $h)
}
