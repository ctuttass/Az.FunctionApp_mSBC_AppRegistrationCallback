using namespace System.Net
 
param($Request, $TriggerMetadata)
 
function Get-BearerTokenWithClientSecret {
    [CmdletBinding()]
    param (# The application ID (Client ID) registered in Azure Active Directory. Example: 2a203ebf-0695-47b7-bf27-ffdeed9a61e2
        [Parameter(Mandatory = $true, HelpMessage = 'Provide the Application (Client) ID')]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern('[a-f0-9]{8}-([a-f0-9]{4}-){3}[a-f0-9]{12}')]
        [guid]
        $AppId,

        # The resource scope for which the token is requested. Default is Microsoft Graph.
        [Parameter(Mandatory = $false, HelpMessage = 'Specify the OAuth 2.0 scope. Default: https://graph.microsoft.com/.default')]
        [string]
        $Scope,

        # The base URL for the identity provider's authentication endpoint.
        [Parameter(Mandatory = $false, HelpMessage = 'Specify the authentication URL. Default: https://login.microsoftonline.com/')]
        [ValidatePattern('^(http|HTTP)[sS]?:\/\/')]
        [uri]
        $AuthUrl,

        # Specifies a redirect URI, typically used in interactive authorization code flows.
        [Parameter(Mandatory = $false, HelpMessage = 'Provide a Redirect URI when using authorization code flow')]
        [uri]
        $RedirectUri,

        # The client secret or credential used for authentication. May be plain text, recommended as a `PSCredential` object.
        [object]
        $ClientSecret
    )

    # Create a header for the token request
    $ReqTokenHeader = @{
        ContentType = 'application/x-www-form-urlencoded'
    }

    # Create the base body for the token request (scope and client_Id always required)
    $ReqTokenBody = @{
        scope     = $Scope
        client_Id = $AppId
    }

    # Add RedirectUri to body if provided
    if ($RedirectUri) {
        $ReqTokenBody.Add('redirect_uri', $RedirectUri)
    }

    $ReqTokenBody.Add('grant_type', 'client_credentials')
    $ReqTokenBody.Add('client_secret', $ClientSecret)

    $Splat_for_Request = @{
        Body    = $ReqTokenBody
        Uri     = $AuthUrl
        Headers = $ReqTokenHeader
        Method  = 'POST'
    }

    try {
        $TokenResponse = Invoke-RestMethod @Splat_for_Request
        return $TokenResponse.access_token
    } catch {
        Write-Error "Fehler beim Abrufen des Tokens: $_"
        return $null
    }

}

# Query Parameter auslesen
$adminConsent = $Request.Query.admin_consent
$tenantId = $Request.Query.tenant
$stateEncoded = $Request.Query.state
$errorQuery = $Request.Query.error
$errorDesc = $Request.Query.error_description

# secrets lesen
$graphClientSecret = $env:GraphClientSecret
$ovhClientSecret = $env:ovhClientSecret

<# custumerId und clusterId werden normalerweise im state mitgegeben, hier hartkodiert für Testzwecke
$customerId = "julian005.tutti2"
$state = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($customerId))
#>
 
# State dekodieren
if ($stateEncoded) {
    $stateDecoded = [System.Text.Encoding]::UTF8.GetString(
        [Convert]::FromBase64String($stateEncoded)
    )
    $customerId = $stateDecoded.Split(".")[0]
    $clusterId = $stateDecoded.Split(".")[1]
} else {
    $stateDecoded = $null
}
 
# Logging
Write-Host "Consent Callback empfangen"
Write-Host "admin_consent  : $adminConsent"
Write-Host "tenant_id      : $tenantId"
Write-Host "state (raw)    : $stateEncoded"
Write-Host "state (decoded): $stateDecoded"
Write-Host "customer       : $customerId"
Write-Host "cluster        : $clusterId"



$splatForGraphToken = @{
    AppId        = "466343fd-79a4-4ae0-8bc4-b92ee5e968ac"
    Scope        = "https://graph.microsoft.com/.default"
    AuthUrl      = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
    RedirectUri  = "https://callback-gqagesgnh2e3cmdw.germanywestcentral-01.azurewebsites.net/callback?code=_2c21mS1qqWRadJowoA9ODiY8YTBduam04CrBbR8CHwxAzFuSt0_hg=="
    ClientSecret = $graphClientSecret
}

#what
$graphToken = Get-BearerTokenWithClientSecret @splatForGraphToken

Write-Host "Token: $($graphToken.Substring(0, 10))"
# get domains from graph api
$uri = "https://graph.microsoft.com/v1.0/domains"
$graphHeaders = @{
    "Content-Type"  = "application/json; charset=UTF-8"
    "Authorization" = "Bearer $($graphToken)"
}
$response = Invoke-RestMethod -Uri $uri -Headers $graphHeaders -Method GET
$response.value

# create domain in test tenant
$body = @{
    id                = "$($customerId).$($clusterId).spielwiese.ovh"
    isDefault         = $false
    supportedServices = @()
} | ConvertTo-Json

$response = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/domains" -Headers $graphHeaders -Method POST -Body $body
$response
Start-Sleep -Seconds 10
# get details of created domain
$response = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/domains/$($customerId).$($clusterId).spielwiese.ovh/verificationDnsRecords" -Headers $graphHeaders -Method GET
$response.value | where-object { $_.recordType -eq "TXT" }
$txtRecord = ($response.value | where-object { $_.recordType -eq "TXT" }).text

# ovh token holen
$body = @{
    grant_type    = "client_credentials"
    client_id     = "EU.87f208e9a0e6c9e8"
    client_secret = $ovhClientSecret
    scope         = "all"
}

$splatForOvhToken = @{
    Uri         = "https://www.ovh.com/auth/oauth2/token"
    Body        = $body
    Method      = "POST"
    ContentType = "application/x-www-form-urlencoded"
}

$ovhToken = Invoke-RestMethod @splatForOvhToken

Write-Host "OVH Token: $($ovhToken.access_token.Substring(0, 10))"

$ovhHeaders = @{
    Authorization  = "Bearer $($ovhToken.access_token)"
    'Content-Type' = 'application/json'
}

$uri = "https://eu.api.ovh.com/v1/domain/zone/spielwiese.ovh/record?subDomain=$($customerId).$($clusterId)"  
$response = Invoke-RestMethod -Uri $uri -Headers $ovhHeaders -Method GET
$response

#$uri = "https://eu.api.ovh.com/v1/domain/zone/spielwiese.ovh/record/5403044774"
#$response = Invoke-RestMethod -Uri $uri -Headers $ovhHeaders -Method GET
#$response

# txt record anlegen
$body = @{
    subDomain = "$($customerId).$($clusterId)"
    fieldType = "TXT"
    target    = $txtRecord

} | ConvertTo-Json

$uri = "https://eu.api.ovh.com/v1/domain/zone/spielwiese.ovh/record"
 
$record = Invoke-RestMethod -Uri $uri -Method POST -Headers $ovhHeaders -Body $body  
Start-Sleep -Seconds 5
#zone refreshen
Invoke-RestMethod -Uri " https://eu.api.ovh.com/v1/domain/zone/spielwiese.ovh/refresh" -Method  POST -Headers $ovhHeaders  

start-sleep -Seconds 10
Resolve-DnsName -Name "$($customerId).$($clusterId).spielwiese.ovh" -Type TXT -Server "8.8.8.8"

$uri = "https://graph.microsoft.com/v1.0/domains/$($customerId).$($clusterId).spielwiese.ovh/verify"
$response = Invoke-RestMethod -Uri $uri -Headers $graphHeaders -Method POST


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