# Script pour aider à trouver les informations du cluster kubeadm
Write-Host "=== Aide pour trouver les informations du cluster ===" -ForegroundColor Cyan

Write-Host "`n1. IP DU MASTER KUBEADM" -ForegroundColor Yellow
Write-Host @"
Si vous avez un accès physique/console au master, exécutez :
  ip addr show
  # ou
  hostname -I

Si le master est une VM, vérifiez :
  - VirtualBox : Paramètres réseau de la VM
  - VMware : Paramètres réseau de la VM
  - Hyper-V : Paramètres de la machine virtuelle

Si vous pouvez vous connecter à un autre nœud du cluster :
  kubectl get nodes -o wide
"@ -ForegroundColor White

Write-Host "`n2. UTILISATEUR SSH" -ForegroundColor Yellow
Write-Host @"
Essayez ces utilisateurs courants :
  - ubuntu (défaut sur Ubuntu cloud images)
  - vagrant (si installé via Vagrant)
  - root (si accès root activé)
  - votre nom d'utilisateur

Ou depuis le master :
  whoami
"@ -ForegroundColor White

Write-Host "`n3. CLÉ SSH (optionnel)" -ForegroundColor Yellow
Write-Host @"
Si vous utilisez une clé SSH, elle peut être dans :
  - $env:USERPROFILE\.ssh\id_rsa
  - $env:USERPROFILE\.ssh\id_ed25519
  - C:\Users\...\Downloads\*.pem (pour AWS/cloud)

Si vous n'avez pas de clé, vous utiliserez un mot de passe.
"@ -ForegroundColor White

Write-Host "`n4. TEST DE CONNEXION" -ForegroundColor Yellow
Write-Host @"
Une fois que vous avez l'IP et l'utilisateur, testez la connexion :

Test avec mot de passe :
  ssh utilisateur@IP_MASTER

Test avec clé :
  ssh -i C:\chemin\vers\clé.pem utilisateur@IP_MASTER

Si la connexion fonctionne, vous êtes prêt !
"@ -ForegroundColor White

Write-Host "`n=== INFORMATIONS ACTUELLES ===" -ForegroundColor Cyan

# Vérifier si on peut détecter des machines sur le réseau local
Write-Host "`nMachines détectées sur le réseau (ARP) :" -ForegroundColor Yellow
try {
    $arp = arp -a | Select-String "192.168|10\.|172\." | Select-Object -First 5
    if ($arp) {
        $arp | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
    } else {
        Write-Host "  Aucune machine détectée via ARP" -ForegroundColor Gray
    }
} catch {
    Write-Host "  Impossible de scanner le réseau" -ForegroundColor Gray
}

Write-Host "`nClés SSH trouvées :" -ForegroundColor Yellow
$sshKeys = Get-ChildItem $env:USERPROFILE\.ssh -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "id_|\.pem|\.key" }
if ($sshKeys) {
    $sshKeys | ForEach-Object { Write-Host "  $($_.FullName)" -ForegroundColor Gray }
} else {
    Write-Host "  Aucune clé SSH trouvée dans $env:USERPROFILE\.ssh" -ForegroundColor Gray
    Write-Host "  Vous utiliserez probablement un mot de passe SSH" -ForegroundColor Gray
}

Write-Host "`n=== PROCHAINES ÉTAPES ===" -ForegroundColor Cyan
Write-Host "1. Trouvez l'IP du master (voir instructions ci-dessus)" -ForegroundColor White
Write-Host "2. Testez la connexion SSH : ssh utilisateur@IP" -ForegroundColor White
Write-Host "3. Exécutez le script de déploiement :" -ForegroundColor White
Write-Host "   .\scripts\setup-fleetman-auto.ps1 -MasterIP `"IP`" -User `"utilisateur`"" -ForegroundColor Green

