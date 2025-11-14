# Script de vérification complète de la chaîne Fleetman
# Vérifie chaque maillon et identifie les problèmes

Write-Host "=== VÉRIFICATION COMPLÈTE DE LA CHAÎNE FLEETMAN ==="
Write-Host ""

# 1. État des pods et endpoints
Write-Host "1. ÉTAT DES PODS ET ENDPOINTS:"
kubectl -n fleetman get pods,endpoints | Select-Object -First 15
Write-Host ""

# 2. Vérification de la chaîne complète
Write-Host "2. VÉRIFICATION DE LA CHAÎNE:"
Write-Host ""

Write-Host "A. Position Simulator → Queue:"
$simulatorPod = kubectl -n fleetman get pod -l app=fleetman-position-simulator -o jsonpath='{.items[0].metadata.name}' 2>&1
if ($simulatorPod -and $simulatorPod -notmatch "error") {
    $simLogs = kubectl -n fleetman logs $simulatorPod --tail=20 | Select-String -Pattern "sent|message|ActiveMQ" -Quiet
    if ($simLogs) {
        Write-Host "  ✓ Envoie des messages"
    } else {
        Write-Host "  ⚠ Pas de messages visibles dans les logs"
    }
} else {
    Write-Host "  ✗ Pod non trouvé"
}

Write-Host "`nB. Queue → Position Tracker:"
$trackerLogs = kubectl -n fleetman logs -l app=fleetman-position-tracker --tail=50 | Select-String -Pattern "Received message|Inserting Document" -Quiet
if ($trackerLogs) {
    Write-Host "  ✓ Reçoit et traite les messages"
} else {
    Write-Host "  ✗ Ne reçoit pas de messages"
}

Write-Host "`nC. Position Tracker → MongoDB:"
$mongoLogs = kubectl -n fleetman logs -l app=fleetman-position-tracker --tail=50 | Select-String -Pattern "Execution of command.*completed successfully" -Quiet
if ($mongoLogs) {
    Write-Host "  ✓ Insère dans MongoDB"
} else {
    Write-Host "  ✗ N'insère pas dans MongoDB"
}

Write-Host "`nD. Position Tracker → API Gateway (HTTP):"
$trackerPod = kubectl -n fleetman get pod -l app=fleetman-position-tracker -o jsonpath='{.items[0].metadata.name}' 2>&1
if ($trackerPod -and $trackerPod -notmatch "error") {
    $test = kubectl -n fleetman exec deploy/fleetman-api-gateway -- sh -c "curl -sS -m 3 http://fleetman-position-tracker:8080/vehicles 2>&1" 2>&1
    $testStr = if ($test -is [string]) { $test } else { $test.ToString() }
    if ($testStr -match 'vehicle') {
        Write-Host "  ✓✓✓ API Gateway peut joindre le Position Tracker !"
    } elseif ($testStr -match 'name') {
        Write-Host "  ✓✓✓ API Gateway peut joindre le Position Tracker !"
    } elseif ($testStr -match '404') {
        Write-Host "  ⚠ Position Tracker répond mais 404 (endpoint non trouvé)"
    } elseif ($testStr -match 'timeout') {
        Write-Host "  ✗ Timeout (Position Tracker ne répond pas)"
    } elseif ($testStr -match 'TIMEOUT') {
        Write-Host "  ✗ Timeout (Position Tracker ne répond pas)"
    } else {
        if ($testStr -and $testStr.Length -gt 0) {
            $len = [Math]::Min(100, $testStr.Length)
            Write-Host "  ? Réponse: $($testStr.Substring(0, $len))"
        } else {
            Write-Host "  ? Pas de réponse"
        }
    }
} else {
    Write-Host "  ✗ Pod Position Tracker non trouvé"
}

Write-Host "`nE. API Gateway → Web App:"
$webPod = kubectl -n fleetman get pod -l app=fleetman-webapp -o jsonpath='{.items[0].metadata.name}' 2>&1
if ($webPod -and $webPod -notmatch "error") {
    $test2 = kubectl -n fleetman exec $webPod -- sh -c "wget -qO- --timeout=3 http://fleetman-api-gateway:8080/actuator/health 2>&1 || curl -sf --max-time 3 http://fleetman-api-gateway:8080/actuator/health 2>&1 || echo 'FAIL'" 2>&1
    if ($test2 -match 'UP|status') {
        Write-Host "  ✓ Web App peut joindre l'API Gateway"
    } elseif ($test2 -match '404') {
        Write-Host "  ⚠ API Gateway répond mais 404"
    } else {
        Write-Host "  ✗ Web App ne peut pas joindre l'API Gateway"
    }
}

Write-Host ""
Write-Host "3. TEST FINAL - ENDPOINT /vehicles:"
Write-Host ""

Write-Host "Depuis API Gateway:"
$finalTest = kubectl -n fleetman exec deploy/fleetman-api-gateway -- sh -c "curl -sS -m 5 http://localhost:8080/vehicles 2>&1" 2>&1
if (($finalTest -match 'vehicle') -or ($finalTest -match 'name')) {
    Write-Host "  ✓✓✓ SUCCÈS ! L'endpoint /vehicles fonctionne !"
    if ($finalTest -and $finalTest.Length -gt 0) {
        $len = [Math]::Min(300, $finalTest.Length)
        Write-Host "  Données: $($finalTest.Substring(0, $len))"
    }
} elseif ($finalTest -match '404') {
    Write-Host "  ✗ 404 - Endpoint non trouvé"
} elseif (($finalTest -match 'timeout') -or ($finalTest -match 'TIMEOUT')) {
    Write-Host "  ✗ Timeout - L'API Gateway ne peut pas joindre le Position Tracker"
} else {
    if ($finalTest -and $finalTest.Length -gt 0) {
        $len = [Math]::Min(200, $finalTest.Length)
        Write-Host "  ? Réponse: $($finalTest.Substring(0, $len))"
    } else {
        Write-Host "  ? Pas de réponse"
    }
}

Write-Host ""
Write-Host "4. RÉSUMÉ:"
Write-Host ""
Write-Host "Pour que les camions s'affichent, il faut que:"
Write-Host "  ✓ Position Tracker expose l'endpoint /vehicles"
Write-Host "  ✓ API Gateway peut joindre le Position Tracker"
Write-Host "  ✓ Web App peut joindre l'API Gateway"
Write-Host ""
Write-Host "Application accessible sur: http://localhost:30080"
Write-Host "Assurez-vous que le port-forward est actif:"
Write-Host "  kubectl -n fleetman port-forward svc/fleetman-webapp 30080:80 --address=0.0.0.0"

