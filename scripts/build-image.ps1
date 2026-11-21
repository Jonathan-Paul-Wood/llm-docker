param(
    [string]$Image = 'open-llm-qwen3:1.0',
    [string]$Platform = 'linux/amd64',
    [ValidateRange(1, 256)][int]$BuildJobs = 6,
    [string]$OutputArchive = ''
)
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    & docker buildx build --load --platform $Platform --build-arg "BUILD_JOBS=$BuildJobs" --tag $Image .
    if ($LASTEXITCODE -ne 0) { throw 'Docker image build failed.' }
    if ($OutputArchive) {
        & docker save --output $OutputArchive $Image
        if ($LASTEXITCODE -ne 0) { throw 'Docker image export failed.' }
        Write-Host "Image exported to $OutputArchive"
    }
    Write-Host "Built $Image for $Platform"
}
finally {
    Pop-Location
}
