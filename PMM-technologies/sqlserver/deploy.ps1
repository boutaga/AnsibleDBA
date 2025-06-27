# Define deployment variables
$DeployFolder = "C:\CustomDeployFolder"   # <-- adjust custom folder here
$SourceFolder = "C:\Prometheus\AP"   # folder containing the files and executable

# Ensure deploy folder exists
if (-Not (Test-Path $DeployFolder)) {
    New-Item -Path $DeployFolder -ItemType Directory | Out-Null
}

# Copy configuration and collector files 
Copy-Item -Path "$SourceFolder\README.md" -Destination $DeployFolder -Force
Copy-Item -Path "$SourceFolder\*.collector.yml" -Destination $DeployFolder -Force

# Copy executable and main config file if they exist
Copy-Item -Path "$SourceFolder\sql_exporter.exe" -Destination $DeployFolder -Force
Copy-Item -Path "$SourceFolder\sql_exporter.yml" -Destination $DeployFolder -Force

# Create a new service pointing to the deployed executable.
$SvcName = "SqlExporterSvc"
$BinaryPath = """$DeployFolder\sql_exporter.exe"" --config.file ""$DeployFolder\sql_exporter.yml"""
if (Get-Service -Name $SvcName -ErrorAction SilentlyContinue) {
    Write-Host "Service $SvcName already exists. Updating the binary path..."
    Set-Service -Name $SvcName -BinaryPathName $BinaryPath
} else {
    New-Service -Name $SvcName -BinaryPathName $BinaryPath -StartupType Automatic -DisplayName "Prometheus SQL Exporter"
    Write-Host "Service $SvcName created successfully."
}