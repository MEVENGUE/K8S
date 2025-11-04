# Script automatisé pour récupérer kubeconfig et déployer Fleetman
# Usage: .\scripts\setup-fleetman-auto.ps1 -MasterIP "10.0.0.10" -User "ubuntu"

param(
    [Parameter(Mandatory=$true)]
    [string]$MasterIP,
    
    [Parameter(Mandatory=$true)]
    [string]$User,
    
    [string]$KeyPath = "",
    [string]$KubeConfigPath = "C:\Temp\kubeconfig.yaml"
)

$ErrorActionPreference = "Stop"

Write-Host "=== Configuration automatique Fleetman ===" -ForegroundColor Cyan

# Étape 1: Récupérer admin.conf via WSL/SSH
Write-Host "`n[1/5] Récupération de admin.conf depuis $User@${MasterIP}..." -ForegroundColor Yellow

$tempDir = Split-Path $KubeConfigPath -Parent
if (-not (Test-Path $tempDir)) {
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
}

# Chemin WSL
$wslPath = "/mnt/" + ($KubeConfigPath -replace ":", "" -replace "\\", "/")

# Méthode 1: Via WSL SCP
if (Get-Command wsl -ErrorAction SilentlyContinue) {
    Write-Host "  Utilisation de WSL pour SCP..." -ForegroundColor Gray
    
    $scpCmd = "wsl scp"
    if ($KeyPath) {
        $wslKeyPath = "/mnt/" + ($KeyPath -replace ":", "" -replace "\\", "/")
        $scpCmd += " -i `"$wslKeyPath`""
    }
    $scpCmd += " ${User}@${MasterIP}:/etc/kubernetes/admin.conf $wslPath"
    
    try {
        Invoke-Expression $scpCmd
        if (Test-Path $KubeConfigPath) {
            Write-Host "  ✓ Fichier copié avec succès" -ForegroundColor Green
        } else {
            throw "Fichier non trouvé après copie"
        }
    } catch {
        Write-Host "  ✗ Erreur: $_" -ForegroundColor Red
        Write-Host "`n  Vérifiez que :" -ForegroundColor Yellow
        Write-Host "    - L'IP et l'utilisateur sont corrects" -ForegroundColor White
        Write-Host "    - SSH est accessible depuis WSL" -ForegroundColor White
        Write-Host "    - Le fichier /etc/kubernetes/admin.conf existe sur le master" -ForegroundColor White
        exit 1
    }
} else {
    Write-Host "  ✗ WSL non disponible. Veuillez copier admin.conf manuellement dans $KubeConfigPath" -ForegroundColor Red
    exit 1
}

# Étape 2: Configurer kubectl avec le nouveau kubeconfig
Write-Host "`n[2/5] Configuration de kubectl..." -ForegroundColor Yellow
$env:KUBECONFIG = $KubeConfigPath

# Lister et sélectionner le contexte
$contexts = kubectl config get-contexts -o name 2>$null
if (-not $contexts -or $contexts.Count -eq 0) {
    Write-Host "  ✗ Aucun contexte trouvé dans le kubeconfig" -ForegroundColor Red
    exit 1
}

$targetContext = $contexts | Where-Object { $_ -notmatch "docker-desktop" } | Select-Object -First 1
if (-not $targetContext) {
    $targetContext = $contexts[0]
}

Write-Host "  Contexte sélectionné: $targetContext" -ForegroundColor Gray
kubectl config use-context $targetContext | Out-Null

# Vérifier la connexion
Write-Host "  Vérification de la connexion au cluster..." -ForegroundColor Gray
$nodes = kubectl get nodes --no-headers 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ✗ Impossible de se connecter au cluster" -ForegroundColor Red
    exit 1
}
Write-Host "  ✓ Cluster accessible ($($nodes.Count) nœuds)" -ForegroundColor Green

# Étape 3: Déployer les manifests
Write-Host "`n[3/5] Déploiement des manifests Kubernetes..." -ForegroundColor Yellow
kubectl apply -f k8s/namespace.yaml 2>&1 | Write-Host
kubectl apply -n fleetman -f k8s 2>&1 | Write-Host

if ($LASTEXITCODE -ne 0) {
    Write-Host "  ✗ Erreur lors du déploiement" -ForegroundColor Red
    exit 1
}

# Étape 4: Attendre que les pods soient prêts
Write-Host "`n[4/5] Attente de la disponibilité des déploiements (max 3 min)..." -ForegroundColor Yellow
try {
    kubectl -n fleetman wait --for=condition=available deploy --all --timeout=180s 2>&1 | Write-Host
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ Tous les déploiements sont prêts" -ForegroundColor Green
    } else {
        Write-Host "  ⚠ Timeout ou erreur, vérification manuelle requise" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  ⚠ Vérification manuelle requise" -ForegroundColor Yellow
}

# Afficher l'état
Write-Host "`n  État des pods:" -ForegroundColor Gray
kubectl -n fleetman get pods | Write-Host

# Étape 5: Lancer le port-forward
Write-Host "`n[5/5] Démarrage du port-forward vers localhost:30080..." -ForegroundColor Yellow

$portForwardJob = Start-Job -ScriptBlock {
    param($kubeconfig)
    $env:KUBECONFIG = $kubeconfig
    kubectl -n fleetman port-forward svc/fleetman-webapp 30080:80 2>&1
} -ArgumentList $KubeConfigPath

Start-Sleep -Seconds 2

if ($portForwardJob.State -eq "Running") {
    Write-Host "  ✓ Port-forward actif (Job ID: $($portForwardJob.Id))" -ForegroundColor Green
    Write-Host "`n=== Déploiement terminé ===" -ForegroundColor Cyan
    Write-Host "  Accès à l'application: http://localhost:30080" -ForegroundColor Green
    Write-Host "`n  Pour arrêter le port-forward:" -ForegroundColor Yellow
    Write-Host "    Stop-Job -Id $($portForwardJob.Id); Remove-Job -Id $($portForwardJob.Id)" -ForegroundColor White
} else {
    Write-Host "  ⚠ Le port-forward peut nécessiter un démarrage manuel" -ForegroundColor Yellow
    Write-Host "    Commande: kubectl -n fleetman port-forward svc/fleetman-webapp 30080:80" -ForegroundColor White
}

Write-Host "`n  Vérification de l'état:" -ForegroundColor Gray
Write-Host "    kubectl -n fleetman get pods,svc" -ForegroundColor White

