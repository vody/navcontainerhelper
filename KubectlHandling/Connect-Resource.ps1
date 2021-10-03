<# 
 .Synopsis
  Forward ports from kubernetes resource to localhost
 .Description
  
 .Parameter name
  
 .Parameter ports

 .Parameter permanently
  
 .Parameter skipError
  
 .Example
  
#>
function Connect-Resource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$name,
        [Parameter(Mandatory, Position = 1)]
        $ports,
        [switch]$permanently,
        [switch]$skipError
    )

    $mapping = @{}
    if ($ports -isnot [array]) {
        [array]$ports = $($ports)    
    }
    $ports | ForEach-Object {
        if ($_ -is [Int]) {
            $mapping[$_.ToString()] = 0
        }
        else {
            $item = $_
            $item.GetEnumerator() | ForEach-Object {
                $mapping[$_.Key] = $_.Value
            }
        }
    }

    [PSCustomObject]$connection = @{
        mapping        = @{}
        process        = 0
        outputFilePath = ''
        errorFilePath  = ''
    }
    $connectionsFile = "C:\ProgramData\BcContainerHelper\Connections.json"
    [PSCustomObject]$connections = $null
    if ($permanently) {
        if (Test-Path $connectionsFile) {
            $connections = Get-Content $connectionsFile -Raw | ConvertFrom-Json
            $connection = $connections.$name
        }
        if ($connection.process -ne 0) {
            Stop-Process -Id $connection.process -ErrorAction SilentlyContinue
            Remove-Item $connection.outputFilePath -ErrorAction SilentlyContinue
            Remove-Item $connection.errorFilePath -ErrorAction SilentlyContinue
        }
        $connection.mapping.PSObject.Properties | ForEach-Object {
            $mapping[$_.Name] = $_.Value
        }
    }
    $mappingStringArray = $mapping.GetEnumerator() | ForEach-Object {
        "$($_.Value):$($_.Key)"
    }
    $errorFileLength = 0
    $outputFileLength = 0
    $errorFile = New-TemporaryFile
    $outputFile = New-TemporaryFile
    $initialProcesses = Get-Process kubectl -ErrorAction SilentlyContinue

    Write-Verbose "Starting kubectl port-forward $name"
    $initiator = Start-Process -FilePath 'kubectl' -ArgumentList (@('port-forward', $name) + $mappingStringArray) -PassThru -WindowStyle Hidden -RedirectStandardError $errorFile -RedirectStandardOutput $outputFile
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
        if (-not $skipError) {
            Throw $errorContent
        }
    }
    else {
        $connection.process = (Get-Process kubectl -ErrorAction SilentlyContinue | Where-Object { $_.Id -notin $initialProcesses.Id -and $_.Id -ne $initiator.Id }).Id
        $connection.errorFilePath = $errorFile.FullName
        $connection.outputFilePath = $outputFile.FullName
        Get-Content $outputFile | ForEach-Object {
            Write-Verbose "$_"
            $local = $_.Substring($_.LastIndexOf('->') + 3)
            $remote = [int]::Parse($_.Substring($_.LastIndexOf(':') + 1, $_.LastIndexOf(' ->') - $_.LastIndexOf(':') - 1))
            if ($connection.mapping.$local) {
                $connection.mapping.$local = $remote
            }
            else {
                $connection.mapping | Add-Member -NotePropertyName $local -NotePropertyValue $remote
            }
        }
        if ($permanently) {
            Write-Verbose "Saving new connected resource"
            if (-not $connections) {
                [PSCustomObject]$connections = $null
            }
            $connections.$name = $connection
            $connections | ConvertTo-Json -Compress | Set-Content -Path $connectionsFile
        }
        $connection
    }
}
Export-ModuleMember -Function Connect-Resource -Alias Connect-Resource