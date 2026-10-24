Write-Host "=========================================="
Write-Host " NIRIKSHAK AI - Mobile Run Watchdog"
Write-Host "=========================================="
Write-Host "This script keeps the ADB reverse port alive"
Write-Host "and automatically restarts Flutter if it crashes."
Write-Host ""

$FlutterDir = "$PSScriptRoot\mobile"

while ($true) {
    Write-Host "[+] Setting up ADB reverse port mapping..."
    adb reverse tcp:8080 tcp:8080

    Write-Host "[+] Starting Flutter App..."
    Set-Location $FlutterDir
    flutter run

    Write-Host "[!] Flutter run exited or lost connection. Restarting in 3 seconds..."
    Start-Sleep -Seconds 3
}
