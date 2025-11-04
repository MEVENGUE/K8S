# Scanner le sous-réseau 10.72.164.0/24 pour détecter port 22 (SSH) et 6443 (API K8s)
param(
  [string]$SubnetPrefix = "10.72.164",
  [int]$Start = 1,
  [int]$End = 254
)

Write-Host "=== Scan $SubnetPrefix.0/$Start-$End ===" -ForegroundColor Cyan

$alive = @()
for ($i = $Start; $i -le $End; $i++) {
  $ip = "$SubnetPrefix.$i"
  try {
    if (Test-Connection -Count 1 -Quiet $ip) {
      $alive += $ip
    }
  } catch {}
}

Write-Host "IPs en ligne: $($alive -join ', ')" -ForegroundColor Gray

$results = @()
foreach ($ip in $alive) {
  try { $ssh = (Test-NetConnection -ComputerName $ip -Port 22 -WarningAction SilentlyContinue).TcpTestSucceeded } catch { $ssh = $false }
  try { $api = (Test-NetConnection -ComputerName $ip -Port 6443 -WarningAction SilentlyContinue).TcpTestSucceeded } catch { $api = $false }
  if ($ssh -or $api) {
    $results += [pscustomobject]@{ IP = $ip; SSH = $ssh; API = $api }
  }
}

if ($results.Count -gt 0) {
  $results | Format-Table -AutoSize
} else {
  Write-Host "Aucun hôte avec SSH ou API K8s détecté" -ForegroundColor Yellow
}
