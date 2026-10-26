# Run in PowerShell from the extracted project folder.
$ErrorActionPreference = 'Stop'
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw 'Flutter SDK not found. Install Flutter and add its bin directory to PATH first.'
}
flutter doctor
flutter create --platforms=ios --project-name lyricflow --org com.example .
if ($LASTEXITCODE -ne 0) { throw 'flutter create failed' }
flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }
flutter analyze
if ($LASTEXITCODE -ne 0) { throw 'flutter analyze failed' }
flutter test
if ($LASTEXITCODE -ne 0) { throw 'flutter test failed' }
Write-Host 'Source setup and tests finished. Signed iOS builds require a macOS cloud runner.'
