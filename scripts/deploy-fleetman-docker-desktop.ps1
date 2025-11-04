# Script de déploiement Fleetman sur Docker Desktop Kubernetes
Write-Host "=== Déploiement Fleetman sur Docker Desktop ===" -ForegroundColor Cyan

# Vérifier que Docker Desktop est accessible
Write-Host "`n[Vérification] Docker Desktop..." -ForegroundColor Yellow
try {
    $docker = docker ps 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Docker n'est pas accessible"
    }
    Write-Host "  ✓ Docker Desktop est actif" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Docker Desktop n'est pas accessible" -ForegroundColor Red
    Write-Host "  Veuillez démarrer Docker Desktop et activer Kubernetes dans les paramètres" -ForegroundColor Yellow
    Write-Host "  (Settings > Kubernetes > Enable Kubernetes)" -ForegroundColor White
    exit 1
}

# Vérifier que Kubernetes est accessible
Write-Host "`n[Vérification] Kubernetes..." -ForegroundColor Yellow
kubectl config use-context docker-desktop | Out-Null

try {
    $nodes = kubectl get nodes --no-headers 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Kubernetes n'est pas accessible"
    }
    Write-Host "  ✓ Cluster Kubernetes accessible" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Kubernetes n'est pas accessible" -ForegroundColor Red
    Write-Host "  Veuillez activer Kubernetes dans Docker Desktop :" -ForegroundColor Yellow
    Write-Host "    1. Ouvrez Docker Desktop" -ForegroundColor White
    Write-Host "    2. Allez dans Settings > Kubernetes" -ForegroundColor White
    Write-Host "    3. Cochez 'Enable Kubernetes'" -ForegroundColor White
    Write-Host "    4. Attendez que le cluster soit prêt (icône Kubernetes devient vert)" -ForegroundColor White
    exit 1
}

# Déployer les manifests
Write-Host "`n[Déploiement] Création du namespace..." -ForegroundColor Yellow
kubectl apply -f k8s/namespace.yaml 2>&1 | Out-Null

Write-Host "[Déploiement] Application des manifests..." -ForegroundColor Yellow
kubectl apply -n fleetman -f k8s 2>&1 | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Host "  ✗ Erreur lors du déploiement" -ForegroundColor Red
    exit 1
}

Write-Host "  ✓ Manifests appliqués" -ForegroundColor Green

# Attendre que les pods soient prêts
Write-Host "`n[Attente] Disponibilité des pods (max 3 min)..." -ForegroundColor Yellow
$startTime = Get-Date
$timeout = 180

do {
    Start-Sleep -Seconds 5
    Write-Host "." -ForegroundColor Gray -NoNewline
    
    $ready = kubectl -n fleetman wait --for=condition=available deploy --all --timeout=5s 2>&1
    $elapsed = ((Get-Date) - $startTime).TotalSeconds
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n  ✓ Tous les déploiements sont prêts (${elapsed}s)" -ForegroundColor Green
        break
    }
    
    if ($elapsed -ge $timeout) {
        Write-Host "`n  ⚠ Timeout atteint" -ForegroundColor Yellow
        break
    }
} while ($true)

# Afficher l'état
Write-Host "`n  État des pods :" -ForegroundColor Gray
kubectl -n fleetman get pods | Write-Host

# Lancer le port-forward
Write-Host "`n[Port-forward] Démarrage vers localhost:30080..." -ForegroundColor Yellow

$pfScript = @"
`$env:KUBECONFIG = '$env:USERPROFILE\.kube\config'
kubectl config use-context docker-desktop
kubectl -n fleetman port-forward svc/fleetman-webapp 30080:80
"@

$pfScriptPath = "$env:TEMP\fleetman-portforward.ps1"
$pfScript | Out-File -FilePath $pfScriptPath -Encoding UTF8

try {
    $portForwardJob = Start-Process powershell.exe -ArgumentList "-NoExit", "-File", $pfScriptPath -PassThru -WindowStyle Minimized
    
    Start-Sleep -Seconds 3
    
    if ($portForwardJob -and -not $portForwardJob.HasExited) {
        Write-Host "  ✓ Port-forward démarré (PID: $($portForwardJob.Id))" -ForegroundColor Green
        Write-Host "`n=== Déploiement terminé ===" -ForegroundColor Cyan
        Write-Host "  Accès à l'application : http://localhost:30080" -ForegroundColor Green
        Write-Host "`n  Pour arrêter le port-forward :" -ForegroundColor Yellow
        Write-Host "    Stop-Process -Id $($portForwardJob.Id)" -ForegroundColor White
    } else {
        Write-Host "  ⚠ Le port-forward nécessite un démarrage manuel" -ForegroundColor Yellow
        Write-Host "    Commande : kubectl -n fleetman port-forward svc/fleetman-webapp 30080:80" -ForegroundColor White
    }
} catch {
    Write-Host "  ⚠ Erreur : $_" -ForegroundColor Yellow
    Write-Host "    Démarrez manuellement : kubectl -n fleetman port-forward svc/fleetman-webapp 30080:80" -ForegroundColor White
}

Write-Host "`n  Commandes utiles :" -ForegroundColor Gray
Write-Host "    kubectl -n fleetman get pods,svc" -ForegroundColor White
Write-Host "    kubectl -n fleetman logs <pod-name>" -ForegroundColor White
Write-Host "    kubectl -n fleetman rollout restart deploy/fleetman-queue" -ForegroundColor White

