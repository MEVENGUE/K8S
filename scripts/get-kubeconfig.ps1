# Script pour récupérer admin.conf depuis le master kubeadm
# Usage: .\scripts\get-kubeconfig.ps1 -MasterIP "10.0.0.10" -User "ubuntu"

param(
    [string]$MasterIP = "",
    [string]$User = "",
    [string]$KeyPath = "",
    [string]$OutputPath = "C:\Temp\kubeconfig.yaml"
)

Write-Host "=== Récupération de admin.conf depuis le master kubeadm ===" -ForegroundColor Cyan

# Méthode 1: Via SSH/SCP
if ($MasterIP -and $User) {
    Write-Host "`nTentative de copie via SCP..." -ForegroundColor Yellow
    
    # Créer le dossier de destination
    $dir = Split-Path $OutputPath -Parent
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    
    # Commande SCP
    $scpCmd = "scp"
    if ($KeyPath) {
        $scpCmd += " -i `"$KeyPath`""
    }
    $scpCmd += " ${User}@${MasterIP}:/etc/kubernetes/admin.conf `"$OutputPath`""
    
    Write-Host "Exécution: $scpCmd" -ForegroundColor Gray
    try {
        Invoke-Expression $scpCmd
        if ($LASTEXITCODE -eq 0 -and (Test-Path $OutputPath)) {
            Write-Host "`n✓ Fichier copié avec succès: $OutputPath" -ForegroundColor Green
            return $OutputPath
        }
    } catch {
        Write-Host "✗ Erreur SCP: $_" -ForegroundColor Red
    }
}

# Méthode 2: Si le fichier existe déjà localement
Write-Host "`nRecherche de fichiers existants..." -ForegroundColor Yellow
$searchPaths = @(
    "$env:USERPROFILE\Downloads\admin.conf",
    "$env:USERPROFILE\Desktop\admin.conf",
    "C:\Temp\admin.conf",
    "$env:USERPROFILE\admin.conf"
)

foreach ($path in $searchPaths) {
    if (Test-Path $path) {
        Write-Host "✓ Fichier trouvé: $path" -ForegroundColor Green
        Copy-Item $path $OutputPath -Force
        return $OutputPath
    }
}

# Méthode 3: Instructions manuelles
Write-Host "`n=== Instructions manuelles ===" -ForegroundColor Cyan
Write-Host @"
Si vous avez un accès au master kubeadm :

Option A - Via SSH depuis PowerShell :
  scp utilisateur@IP_MASTER:/etc/kubernetes/admin.conf C:\Temp\kubeconfig.yaml

Option B - Depuis le master lui-même :
  1. Connectez-vous au master
  2. Copiez le contenu : cat /etc/kubernetes/admin.conf
  3. Créez C:\Temp\kubeconfig.yaml sur Windows
  4. Collez le contenu dans ce fichier

Option C - Si accès WSL :
  wsl scp utilisateur@IP_MASTER:/etc/kubernetes/admin.conf /mnt/c/Temp/kubeconfig.yaml

Option D - Via partage réseau ou clé USB

Une fois le fichier disponible, exécutez :
  `$env:KUBECONFIG='C:\Temp\kubeconfig.yaml'
  kubectl config get-contexts
  kubectl config use-context <nom-du-contexte>
"@ -ForegroundColor Yellow

Write-Host "`nVeuillez fournir l'une des informations suivantes :" -ForegroundColor Cyan
Write-Host "  - IP du master et utilisateur SSH (ex: ubuntu@10.0.0.10)" -ForegroundColor White
Write-Host "  - Chemin vers admin.conf s'il est déjà sur cette machine" -ForegroundColor White
Write-Host "  - Ou suivez les instructions manuelles ci-dessus" -ForegroundColor White

return $null

