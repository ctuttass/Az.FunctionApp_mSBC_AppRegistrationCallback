using namespace System.Net
 
param($Request, $TriggerMetadata)
 
# Query Parameter auslesen
$adminConsent = $Request.Query.admin_consent
$tenantId = $Request.Query.tenant
$stateEncoded = $Request.Query.state
$errorQuery = $Request.Query.error
$errorDesc = $Request.Query.error_description

# secrets lesen
$geheim = $env:TestSecret
 
# State dekodieren
if ($stateEncoded) {
    $stateDecoded = [System.Text.Encoding]::UTF8.GetString(
        [Convert]::FromBase64String($stateEncoded)
    )
} else {
    $stateDecoded = $null
}
 
# Logging
Write-Host "Consent Callback empfangen"
Write-Host "admin_consent : $adminConsent"
Write-Host "tenant_id     : $tenantId"
Write-Host "state (raw)   : $stateEncoded"
Write-Host "state (decoded): $stateDecoded"
Write-Host "geheim: $geheim"
 
# Fehlerfall
if ($errorQuery) {
    Write-Host "FEHLER: $errorQuery — $errorDesc"
    
    Push-OutputBinding -Name Response -Value (
        [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = "Consent abgelehnt: $errorQuery`n$errorDesc"
        }
    )
    return
}
 
# Erfolgsfall
$responseBody = @"
Consent erfolgreich!
 
Kunde (state) : $stateDecoded
Tenant-ID     : $tenantId
admin_consent : $adminConsent
"@
 
Push-OutputBinding -Name Response -Value (
    [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $responseBody
    }
)