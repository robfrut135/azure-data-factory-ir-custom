param(
	[string]
 	$gatewayKey,
	[string]
 	$resourceGroup,
	[string]
 	$stogageAccountName,
	[string]
	$datafactoryName
)

# Init log setting
$logLoc = "$env:SystemDrive\WindowsAzure\Logs\Plugins\Microsoft.Compute.CustomScriptExtension\"
if (! (Test-Path($logLoc)))
{
    New-Item -path $logLoc -type directory -Force
}
$logPath = "$logLoc\tracelog.log"

# Functions
function Now-Value()
{
    return (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
}

function Throw-Error([string] $msg)
{
	try
	{
		throw $msg
	}
	catch
	{
		$stack = $_.ScriptStackTrace
		Trace-Log "DMDTTP is failed: $msg`nStack:`n$stack"
	}
	throw $msg
}

function Trace-Log([string] $msg)
{
    $now = Now-Value
    try
    {
        "${now} $msg`n" | Out-File $logPath -Append
    }
    catch
    {
        #ignore any exception during trace
    }
}

function Run-Process([string] $process, [string] $arguments)
{
	Write-Verbose "Run-Process: $process $arguments"

	$errorFile = "$env:tmp\tmp$pid.err"
	$outFile = "$env:tmp\tmp$pid.out"
	"" | Out-File $outFile
	"" | Out-File $errorFile

	$errVariable = ""

	if ([string]::IsNullOrEmpty($arguments))
	{
		$proc = Start-Process -FilePath $process -Wait -Passthru -NoNewWindow -RedirectStandardError $errorFile -RedirectStandardOutput $outFile -ErrorVariable errVariable
	}
	else
	{
		$proc = Start-Process -FilePath $process -ArgumentList $arguments -Wait -Passthru -NoNewWindow -RedirectStandardError $errorFile -RedirectStandardOutput $outFile -ErrorVariable errVariable
	}

	$errContent = [string] (Get-Content -Path $errorFile -Delimiter "!!!DoesNotExist!!!")
	$outContent = [string] (Get-Content -Path $outFile -Delimiter "!!!DoesNotExist!!!")

	Remove-Item $errorFile
	Remove-Item $outFile

	if($proc.ExitCode -ne 0 -or $errVariable -ne "")
	{
		Throw-Error "Failed to run process: exitCode=$($proc.ExitCode), errVariable=$errVariable, errContent=$errContent, outContent=$outContent."
	}

	Trace-Log "Run-Process: ExitCode=$($proc.ExitCode), output=$outContent"

	if ([string]::IsNullOrEmpty($outContent))
	{
		return $outContent
	}

	return $outContent.Trim()
}

function Download-File([string] $url, [string] $path)
{
    try
    {
        $ErrorActionPreference = "Stop";
        $client = New-Object System.Net.WebClient
        $client.DownloadFile($url, $path)
        Trace-Log "Download file successfully. Location: $path"
    }
    catch
    {
        Trace-Log "Fail to download file"
        Trace-Log $_.Exception.ToString()
        throw
    }
}

function Install-MSI([string] $msiPath)
{
	if ([string]::IsNullOrEmpty($msiPath))
    {
		Throw-Error "MSI path is not specified"
    }
	if (!(Test-Path -Path $msiPath))
	{
		Throw-Error "Invalid MSI path: $msiPath"
	}
	Trace-Log "Start Integration Runtime Agent installation"
	Run-Process "msiexec.exe" "/i $msiPath INSTALLTYPE=AzureTemplate /quiet /norestart"
	Start-Sleep -Seconds 30
	Trace-Log "Installation of $msiPath is successful"
}

function Install-EXE([string] $exePath, [string] $exeArgs)
{
	if ([string]::IsNullOrEmpty($exePath))
    {
		Throw-Error "EXE path is not specified"
    }
	if (!(Test-Path -Path $exePath))
	{
		Throw-Error "Invalid EXE path: $exePath"
	}
	Trace-Log "Start $exePath installation"
	Run-Process $exePath $exeArgs
	Start-Sleep -Seconds 30
	Trace-Log "Installation of $exePath is successful"
}

function Register-Gateway([string] $instanceKey)
{
    Trace-Log "Register Integration Runtime Agent"
	$currentDate =  Get-Date -Format "yyMMddHHmmss"
	$filePath = "C:\Program Files\Microsoft Integration Runtime\4.0\Shared\dmgcmd.exe"
    Run-Process $filePath "-Restart"
    Run-Process $filePath "-EnableRemoteAccess 8060"
	Run-Process $filePath "-RegisterNewNode $instanceKey hip$currentDate"
	Start-Sleep -Seconds 30
    Trace-Log "Integration Runtime Agent registration is successful!"
}

function Install-JRE([string] $jreName)
{
	if ([string]::IsNullOrEmpty($jreName))
    {
		Throw-Error "JRE Name not specified"
    }

	$javaHome = "C:\Program Files\Java\$jreName\bin"

	if (!(Test-Path -Path $javaHome))
	{
		Throw-Error "Invalid JAVA_HOME: $javaHome"
	}

	Trace-Log "Start JRE installation"
    $env:Path += $javaHome
	$env:JAVA_HOME = $javaHome
	[System.Environment]::SetEnvironmentVariable('PATH', "$env:Path;$javaHome", [System.EnvironmentVariableTarget]::Machine)
    [System.Environment]::SetEnvironmentVariable('JAVA_HOME', $javaHome, [System.EnvironmentVariableTarget]::Machine)
    Trace-Log $env:JAVA_HOME
    Trace-Log $env:Path
	Trace-Log (java -version)
	Trace-Log "Installation of JRE is successful"
}

# Main
Trace-Log "START install.ps1"
Trace-Log "Log file: $logLoc"

### DataFactory Integration Runtime
Trace-Log "Data Factory Integration Runtime Agent"
$irUri = "https://go.microsoft.com/fwlink/?linkid=839822"
Trace-Log "Gateway download fw link: $irUri"
$gwPath= "$PWD\gateway.msi"
Trace-Log "Gateway download location: $gwPath"
Download-File $irUri $gwPath
Install-MSI $gwPath
Register-Gateway $gatewayKey

### JRE
Trace-Log "Java Runtime Environment"
$jreUri = "https://javadl.oracle.com/webapps/download/AutoDL?BundleId=242990_a4634525489241b9a9e1aa73d9e118e6"
Trace-Log "JRE download fw link: $jreUri"
$jrePath= "$PWD\java_x64.exe"
Trace-Log "JRE location: $jrePath"
Download-File $jreURI $jrePath
Install-EXE $jrePath "/s"
Install-JRE "jre1.8.0_261"

### Visual C++
Trace-Log "Visual C++ 2010 Redistributable"
$vcUri = "https://download.microsoft.com/download/3/2/2/3224B87F-CFA0-4E70-BDA3-3DE650EFEBA5/vcredist_x64.exe"
Trace-Log "Package from: $vcUri"
$vcPath= "$PWD\vcredist_x64.exe"
Trace-Log "Package location: $vcPath"
Download-File $vcUri $vcPath
Install-EXE $vcPath "-q"

### SAP Driver
Trace-Log "SAP HANA ODBC Driver"
Trace-Log "TODO"

### Azure Cloud config
Trace-Log "Set Azure Cloud config in environment"
[System.Environment]::SetEnvironmentVariable('RESOURCE_GROUP', $resourceGroup, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('STORAGE_ACCOUNT', $stogageAccountName, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('DATAFACTORY_NAME', $datafactoryName, [System.EnvironmentVariableTarget]::Machine)
Trace-Log "Set Azure Cloud config in environment is successful"

### Backup schedule
Trace-Log "Backup task registration"
$T = New-JobTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 10) -RepetitionDuration ([TimeSpan]::MaxValue)
$O = @{
  WakeToRun=$true
  StartIfNotIdle=$false
  MultipleInstancePolicy="Queue"
}
Register-ScheduledJob -Trigger $T -ScheduledJobOption $O -Name "IntegrationRuntimeBackup" -FilePath "$PWD\backup.ps1"
Trace-Log "Backup task registration is successful"

### Azure Client
Trace-Log "Azure Cloud configure client"
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Install-Module -Name Az -AllowClobber -Scope CurrentUser -Force
Trace-Log "Azure Cloud configure client is successful"

### Load backup inside Integration Runtime
try
{
	Trace-Log "Set Azure identity"
	Add-AzAccount -identity
	Connect-AzAccount -Identity
	Trace-Log "Set Azure identity is successful"

	Trace-Log "Download backup file from Storage"
	$backupStorage = Get-AzStorageAccount -ResourceGroupName $resourceGroup -Name $stogageAccountName
	$ctx = $backupStorage.Context
	Get-AzStorageBlobContent -Context $ctx -Container "backup" -Blob "datafactory/ir/$datafactoryName" -Destination "$PWD\datafactory_ir_backup" -Force
	Trace-Log "Download backup file is successful"

	Trace-Log "Load backup file to Integration Runtime"
	$irCmd = "C:\Program Files\Microsoft Integration Runtime\4.0\Shared\dmgcmd.exe"
	Run-Process $irCmd "-ImportBackupFile $PWD\datafactory_ir_backup datafactory_ir_backup"
	Trace-Log "Load backup file to Integration Runtime is successful"
}
catch
{
	Trace-Log "Integration Runtime EMPTY."
}

Trace-Log "END install.ps1"