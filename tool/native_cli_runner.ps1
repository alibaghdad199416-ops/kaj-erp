function Invoke-NativeCaptured {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$CommandLine
    )

    Write-Host "`n==> $Label" -ForegroundColor Cyan

    $commandProcessor = $env:ComSpec
    if ([string]::IsNullOrWhiteSpace($commandProcessor)) {
        $commandProcessor = 'cmd.exe'
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $commandProcessor
    $psi.Arguments = "/d /s /c `"$CommandLine`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi

    if (-not $process.Start()) {
        throw "$Label could not start"
    }

    # Read both streams asynchronously so a verbose CLI cannot deadlock.
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    $exitCode = $process.ExitCode
    $process.Dispose()

    if (-not [string]::IsNullOrWhiteSpace($stdout)) {
        Write-Host $stdout.TrimEnd()
    }
    if (-not [string]::IsNullOrWhiteSpace($stderr)) {
        # stderr is diagnostic text. The native exit code alone decides success.
        Write-Host $stderr.TrimEnd() -ForegroundColor DarkYellow
    }

    $combined = (($stdout, $stderr) -join "`n").Trim()
    if ($exitCode -ne 0) {
        throw "$Label failed with native exit code $exitCode`n$combined"
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        StdOut = $stdout
        StdErr = $stderr
        Combined = $combined
    }
}
