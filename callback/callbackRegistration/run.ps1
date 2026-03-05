using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request - emea2PostCdr."

# Interact with query parameters or the body of the request.
$name = $Request.Query.Name
if (-not $name) {
    $name = $Request.Body.Name
}

$body = "This HTTP triggered function executed successfully for emea2PostCdr."

# Add required 'id' property for Cosmos DB
$Request.body | Add-Member -MemberType NoteProperty -Name "id" -Value $Request.body.SIPCallId -Force

$sessionId = $Request.body.SessionId
$callId = $Request.body.SIPCallId
Write-Host Processing CDR for CallId: $callId, with SessionId: $sessionId
Write-Host "body:"
$Request.body | ConvertTo-Json | Write-Host


if ($name) {
    $body = "Hello, $name. This HTTP triggered function executed successfully for emea2PostCdr."
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
try {
    Push-OutputBinding -Name outputDocument -Value ($Request.body | ConvertTo-Json)  -ErrorAction Stop
}
catch {
    $error[0]
}

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
    Body = $body
})
