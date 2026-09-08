Set-Location $PSScriptRoot
$py312 = "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe"
if (Test-Path $py312) {
    $python = $py312
} else {
    $python = "python"
}
try {
    $ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike "127.*" -and $_.PrefixOrigin -ne "WellKnown" } |
        Select-Object -First 1 -ExpandProperty IPAddress)
    if ($ip) {
        Write-Host "En el celular, misma Wi-Fi: http://$ip`:8501/?drive=1"
    }
} catch {
    Write-Host "Al abrir, use la URL Network que imprime Streamlit en el celular."
}
& $python -m streamlit run app.py --server.address 0.0.0.0 --server.port 8501
