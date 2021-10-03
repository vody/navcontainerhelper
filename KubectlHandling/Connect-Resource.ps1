param(
    [Parameter(Mandatory,Position=0)]
    [string]$Name,
    [Parameter(Mandatory,Position=1)]
    $Ports,
    [switch]$Permanently,
    [switch]$SkipError
)

[PSCustomObject]$connection = @{
    mapping = @{}
    process = 0
    outputFilePath = ''
    errorFilePath = ''
}
$connectionsFile = "C:\ProgramData\BcContainerHelper\Connections.json"
[PSCustomObject]$connections = $null
if ($Permanently) {
    if (Test-Path $connectionsFile) {
        $connections = Get-Content $connectionsFile -Raw | ConvertFrom-Json
        $connection = $connections.$Name
    }
    if ($connection.process -ne 0) {
        Stop-Process -Id $connection.process -ErrorAction SilentlyContinue
        Remove-Item $connection.outputFilePath -ErrorAction SilentlyContinue
        Remove-Item $connection.errorFilePath -ErrorAction SilentlyContinue
    }
    # TODO: Append existing ports to a new ports
}

$errorFileLength = 0
$outputFileLength = 0
$errorFile = New-TemporaryFile
$outputFile = New-TemporaryFile
$initialProcesses = Get-Process kubectl -ErrorAction SilentlyContinue

Write-Verbose "Starting kubectl port-forward $Name"
# TODO: Convert ports to string array
$initiator = Start-Process -FilePath 'kubectl' -ArgumentList 'port-forward',$Name,':17045',':18080' -PassThru -WindowStyle Hidden -RedirectStandardError $errorFile -RedirectStandardOutput $outputFile
Start-Sleep -Milliseconds 600
Do {
    Start-Sleep -Milliseconds 50
    $errorFileLength = (Get-Item $errorFile).Length
    $outputFileLength = (Get-Item $outputFile).Length
} Until ($errorFileLength -gt 0 -or $outputFileLength -gt 0)
Stop-Process $initiator -ErrorAction SilentlyContinue | Out-Null
if ($errorFileLength -gt 0) {
    $errorContent = Get-Content $errorFile
    Remove-Item $errorFile
    Remove-Item $outputFile
    if (-not $SkipError) {
        Throw $errorContent
    }
} else {
    $connection.process = (Get-Process kubectl -ErrorAction SilentlyContinue | ? {$_.Id -notin $initialProcesses.Id -and $_.Id -ne $initiator.Id}).Id
    $connection.errorFilePath = $errorFile.FullName
    $connection.outputFilePath = $outputFile.FullName
    Get-Content $outputFile | ForEach-Object {
        Write-Verbose "$_"
        $connection.mapping."$($_.Substring($_.LastIndexOf('->') + 3))" = [int]::Parse($_.Substring($_.LastIndexOf(':') + 1,$_.LastIndexOf(' ->') - $_.LastIndexOf(':') - 1))
    }
    if ($Permanently) {
        Write-Verbose "Saving new connected resource"
        if (-not $connections) {
            [PSCustomObject]$connections = $null
        }
        $connections.$Name = $connection
        $connections | ConvertTo-Json -Compress | Set-Content -Path $connectionsFile
    }
    $connection
}