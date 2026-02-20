$ErrorActionPreference = 'Stop'
$url = 'https://github.com/wixtoolset/wix3/releases/download/wix3112rtm/wix311-binaries.zip'
$zip = 'C:\Users\Support\git\ObjcMarkdown\tools\wix311-binaries.zip'
$dest = 'C:\Users\Support\git\ObjcMarkdown\tools\wix'
New-Item -ItemType Directory -Force -Path (Split-Path $zip) | Out-Null
Invoke-WebRequest -Uri $url -OutFile $zip
Expand-Archive -Path $zip -DestinationPath $dest -Force
