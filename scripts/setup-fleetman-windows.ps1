# Script de déploiement automatique Fleetman pour Windows (100% natif)
param(
    [Parameter(Mandatory=$true)]
    [string]$MasterIP,
    
    [Parameter(Mandatory=$true)]
    [string]$User,
    
    [string]$KeyPath = "",
    [string]$KubeConfigPath = "C:\Temp\kubeconfig.yaml"
)

$ErrorActionPreference = "Stop"

Write-Host "=== Déploiement automatique Fleetman ===" -ForegroundColor Cyan

# Vérifier que OpenSSH Client est installé
Write-Host "`n[Vérification] OpenSSH Client..." -ForegroundColor Yellow
try {
    $sshTest = Get-Command ssh -ErrorAction Stop
    Write-Host "  ✓ OpenSSH Client disponible" -ForegroundColor Green
} catch {
    Write-Host "  ✗ OpenSSH Client non trouvé" -ForegroundColor Red
    Write-Host "  Installation requise (PowerShell en tant qu'administrateur) :" -ForegroundColor Yellow
    Write-Host "    Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0" -ForegroundColor White
    exit 1
}

# Créer le dossier de destination
$tempDir = Split-Path $KubeConfigPath -Parent
if (-not (Test-Path $tempDir)) {
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    Write-Host "  ✓ Dossier créé : $tempDir" -ForegroundColor Green
}

# Étape 1: Récupérer admin.conf
Write-Host "`n[1/5] Récupération de admin.conf depuis $User@${MasterIP}..." -ForegroundColor Yellow

$scpOptions = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=$env:TEMP\known_hosts_tmp"
if ($KeyPath -and (Test-Path $KeyPath)) {
    $scpOptions += " -i `"$KeyPath`""
    Write-Host "  Utilisation de la clé : $KeyPath" -ForegroundColor Gray
} else {
    Write-Host "  Utilisation d'un mot de passe (vous devrez le saisir)" -ForegroundColor Gray
}

$scpCmd = "scp $scpOptions ${User}@${MasterIP}:/etc/kubernetes/admin.conf `"$KubeConfigPath`""

Write-Host "  Exécution de SCP..." -ForegroundColor Gray
try {
    Invoke-Expression $scpCmd
    if (Test-Path $KubeConfigPath) {
        Write-Host "  ✓ Fichier copié avec succès" -ForegroundColor Green
    } else {
        throw "Fichier non trouvé après copie"
    }
} catch {
    Write-Host "  ✗ Erreur lors de la copie : $_" -ForegroundColor Red
    Write-Host "`n  Vérifications :" -ForegroundColor Yellow
    Write-Host "    - L'IP $MasterIP est-elle correcte ?" -ForegroundColor White
    Write-Host "    - L'utilisateur '$User' existe-t-il ?" -ForegroundColor White
    Write-Host "    - Le fichier /etc/kubernetes/admin.conf existe-t-il sur le master ?" -ForegroundColor White
    Write-Host "    - Le mot de passe/clé SSH est-il correct ?" -ForegroundColor White
    exit 1
}

# Étape 2: Configurer kubectl
Write-Host "`n[2/5] Configuration de kubectl..." -ForegroundColor Yellow
$env:KUBECONFIG = $KubeConfigPath

# Vérifier que kubectl peut lire le fichier
try {
    $contexts = kubectl config get-contexts -o name 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Erreur lors de la lecture du kubeconfig"
    }
    
    if (-not $contexts -or $contexts.Count -eq 0) {
        throw "Aucun contexte trouvé"
    }
    
    # Sélectionner un contexte (priorité aux non docker-desktop)
    $targetContext = $contexts | Where-Object { $_ -notmatch "docker-desktop" } | Select-Object -First 1
    if (-not $targetContext) {
        $targetContext = $contexts[0]
    }
    
    Write-Host "  Contexte sélectionné : $targetContext" -ForegroundColor Gray
    kubectl config use-context $targetContext | Out-Null
    
    # Vérifier la connexion
    Write-Host "  Vérification de la connexion au cluster..." -ForegroundColor Gray
    $nodes = kubectl get nodes --no-headers 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Impossible de se connecter au cluster"
    }
    
    $nodeCount = ($nodes | Measure-Object).Count
    Write-Host "  ✓ Cluster accessible ($nodeCount nœud(s))" -ForegroundColor Green
    
} catch {
    Write-Host "  ✗ Erreur : $_" -ForegroundColor Red
    exit 1
}

# Étape 3: Déployer les manifests
Write-Host "`n[3/5] Déploiement des manifests Kubernetes..." -ForegroundColor Yellow

try {
    kubectl apply -f k8s/namespace.yaml 2>&1 | Out-Null
    kubectl apply -n fleetman -f k8s 2>&1 | Out-Null
    
    if ($LASTEXITCODE -ne 0) {
        throw "Erreur lors du déploiement"
    }
    
    Write-Host "  ✓ Manifests appliqués" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Erreur : $_" -ForegroundColor Red
    exit 1
}

# Étape 4: Attendre que les pods soient prêts
Write-Host "`n[4/5] Attente de la disponibilité des déploiements (max 3 min)..." -ForegroundColor Yellow

try {
    $timeout = 180
    $startTime = Get-Date
    
    Write-Host "  Attente..." -ForegroundColor Gray -NoNewline
    
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
            Write-Host "`n  ⚠ Timeout atteint, vérification manuelle requise" -ForegroundColor Yellow
            break
        }
    } while ($true)
    
} catch {
    Write-Host "`n  ⚠ Erreur lors de l'attente : $_" -ForegroundColor Yellow
}

# Afficher l'état
Write-Host "`n  État des pods :" -ForegroundColor Gray
kubectl -n fleetman get pods | Write-Host

# Étape 5: Lancer le port-forward
Write-Host "`n[5/5] Démarrage du port-forward vers localhost:30080..." -ForegroundColor Yellow

# Créer un script temporaire pour le port-forward
$pfScript = @"
`$env:KUBECONFIG = '$KubeConfigPath'
kubectl -n fleetman port-forward svc/fleetman-webapp 30080:80
"@

$pfScriptPath = "$env:TEMP\fleetman-portforward.ps1"
$pfScript | Out-File -FilePath $pfScriptPath -Encoding UTF8

try {
    $portForwardJob = Start-Process powershell.exe -ArgumentList "-NoExit", "-File", $pfScriptPath -PassThru -WindowStyle Minimized
    
    Start-Sleep -Seconds 2
    
    if ($portForwardJob -and -not $portForwardJob.HasExited) {
        Write-Host "  ✓ Port-forward démarré (PID: $($portForwardJob.Id))" -ForegroundColor Green
        Write-Host "`n=== Déploiement terminé ===" -ForegroundColor Cyan
        Write-Host "  Accès à l'application : http://localhost:30080" -ForegroundColor Green
        Write-Host "`n  Pour arrêter le port-forward :" -ForegroundColor Yellow
        Write-Host "    Stop-Process -Id $($portForwardJob.Id)" -ForegroundColor White
    } else {
        Write-Host "  ⚠ Le port-forward nécessite un démarrage manuel" -ForegroundColor Yellow
        Write-Host "    Commande : kubectl -n fleetman port-forward svc/fleetman-webapp 30080:80" -ForegroundColor White
        Write-Host "    (Dans une nouvelle fenêtre PowerShell avec : `$env:KUBECONFIG='$KubeConfigPath')" -ForegroundColor White
    }
} catch {
    Write-Host "  ⚠ Erreur lors du démarrage du port-forward : $_" -ForegroundColor Yellow
    Write-Host "    Démarrez manuellement : kubectl -n fleetman port-forward svc/fleetman-webapp 30080:80" -ForegroundColor White
}

Write-Host "`n  Commandes utiles :" -ForegroundColor Gray
Write-Host "    kubectl -n fleetman get pods,svc" -ForegroundColor White
Write-Host "    kubectl -n fleetman logs <pod-name>" -ForegroundColor White
Write-Host "    kubectl -n fleetman rollout restart deploy/fleetman-queue" -ForegroundColor White

