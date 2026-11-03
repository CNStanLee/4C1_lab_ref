#Requires -Version 5.1
# Finds the AUP-ZU3 serial port, checks that it is free, and opens it in COMTool on Windows.
# Students should double-click serial_zu3.bat. Keep this file saved as UTF-8 with a BOM:
# Windows PowerShell misreads the Chinese messages without one. PowerShell also treats curly
# quotes as string delimiters, so the messages below only use straight quotes.
[CmdletBinding()]
param(
    [string]$Port,
    [int]$Baud = 115200,
    [switch]$List,
    [ValidateSet('en', 'zh')][string]$Lang
)

$ErrorActionPreference = 'Stop'
$ComtoolVersion = '3.4.1'
$ComtoolArchive = "comtool_windows_v$ComtoolVersion.7z"
$ComtoolUrl = "https://github.com/Neutree/COMTool/releases/download/v$ComtoolVersion/$ComtoolArchive"
$ComtoolSha256 = 'fb6fe9b2c28a7596cc125ad6309b626823c0093e58d1194e34871b1fe2a17f30'
# COMTool for Windows ships as a .7z, and 7zr.exe is the standalone extractor from the 7-Zip project.
$SevenZipUrl = 'https://github.com/ip7z/7zip/releases/download/24.09/7zr.exe'
$SevenZipSha256 = 'd2c0045523cf053a6b43f9315e9672fc2535f06aeadd4ffa53c729cd8b2b6dfe'
$WaitSeconds = 120

$RepoDir = Split-Path -Parent $PSScriptRoot
$ToolsDir = Join-Path $RepoDir '.tools'
$LogDir = Join-Path $RepoDir 'logs'
$ComtoolDir = Join-Path $ToolsDir 'comtool'
$ComtoolExe = Join-Path $ComtoolDir 'comtool.exe'

function T([string]$En, [string]$Zh) { if ($script:Lang -eq 'zh') { $Zh } else { $En } }
function Say([string]$En, [string]$Zh) { Write-Host (T $En $Zh) }
function Die([string]$En, [string]$Zh) { throw (T $En $Zh) }

function Select-Language {
    if ($script:Lang) { return }
    $reply = Read-Host 'Language / 语言: [1] English (default)  [2] 中文'
    if ($reply -eq '2') { $script:Lang = 'zh' } else { $script:Lang = 'en' }
}

# The board's FT2232 has two channels: channel A is JTAG and channel B is the UART. Windows
# usually gives only channel B a COM port, and shows the channel at the end of the device ID.
function Get-PortRole([string]$DeviceId) {
    if ($DeviceId -notmatch 'VID_0403[+&]PID_6010') { return 'other' }
    if ($DeviceId -match 'A\\[0-9A-F]+$' -or $DeviceId -match 'MI_00') { return 'jtag' }
    'uart'
}

function Get-SerialPorts {
    @(Get-CimInstance Win32_PnPEntity -Filter "Name LIKE '%(COM%'" | ForEach-Object {
            if ($_.Name -match '\((COM\d+)\)') {
                [pscustomobject]@{ Port = $Matches[1]; Name = $_.Name; Role = Get-PortRole $_.PNPDeviceID }
            }
        })
}

function Get-RoleText([string]$Role) {
    switch ($Role) {
        'uart' { T 'AUP-ZU3 UART (boot log)' 'AUP-ZU3 串口（启动日志）' }
        'jtag' { T 'AUP-ZU3 JTAG (not for logs)' 'AUP-ZU3 JTAG（不是日志口）' }
        default { T 'other device' '其他设备' }
    }
}

function Test-PortFree([string]$Name) {
    $serial = New-Object System.IO.Ports.SerialPort $Name, $Baud
    try {
        $serial.Open()
        $serial.Close()
        $true
    } catch {
        $false
    } finally {
        $serial.Dispose()
    }
}

function Show-Ports {
    Say 'Serial ports found:' '检测到的串口：'
    foreach ($item in Get-SerialPorts) {
        if (Test-PortFree $item.Port) { $state = T 'can open' '可打开' } else { $state = T 'in use' '被占用' }
        Write-Host ('  {0,-7} {1}  [{2}]  {3}' -f $item.Port, (Get-RoleText $item.Role), $state, $item.Name)
    }
}

# Called while waiting: explains why a board that is plugged in has no COM port.
function Show-MissingPortHelp {
    $devices = @(Get-CimInstance Win32_PnPEntity -Filter "PNPDeviceID LIKE '%VID_0403%PID_6010%'")
    if ($devices.Count -eq 0) { return }
    if (@($devices | Where-Object { $_.ConfigManagerErrorCode -ne 0 }).Count -gt 0) {
        Say "Windows sees the board's USB chip but has no working driver. Install the FTDI VCP driver from https://ftdichip.com/drivers/vcp-drivers/ and then replug the cable." `
            '系统已检测到开发板的 USB 芯片，但驱动不可用。请从 https://ftdichip.com/drivers/vcp-drivers/ 安装 FTDI VCP 驱动，然后重新插线。'
    } else {
        Say 'Windows sees the board, but no COM port. In Device Manager, under Universal Serial Bus controllers, open "USB Serial Converter B". On the Advanced tab tick "Load VCP", then replug the cable.' `
            '系统已检测到开发板，但没有 COM 口。请打开设备管理器，在"通用串行总线控制器"下打开 "USB Serial Converter B"，在"高级"页勾选 "Load VCP"，然后重新插线。'
    }
}

function Wait-ForBoardPort {
    $waited = 0
    $helped = $false
    while ($waited -lt $WaitSeconds) {
        $ports = @(Get-SerialPorts)
        if (@($ports | Where-Object { $_.Role -eq 'uart' }).Count -gt 0) { return $ports }
        if ($waited -eq 0) {
            Say 'Waiting for the board. Connect a USB-C cable from your computer to the port marked PROG UART, and power the board on ...' `
                '正在等待开发板。请用 USB-C 线连接电脑和板上标有 PROG UART 的接口，并打开开发板电源 ...'
        }
        if ($waited -ge 15 -and -not $helped) {
            Show-MissingPortHelp
            $helped = $true
        }
        Start-Sleep -Seconds 3
        $waited += 3
    }
    @(Get-SerialPorts)
}

function Select-Port {
    if ($script:Port) {
        if ([IO.Ports.SerialPort]::GetPortNames() -notcontains $script:Port) { Die "$($script:Port) does not exist." "$($script:Port) 不存在。" }
        return
    }
    $ports = @(Wait-ForBoardPort)
    if ($ports.Count -eq 0) {
        Die 'No serial port appeared. See "Troubleshooting" in the guide.' '没有出现串口。请查看指引中的"常见问题"。'
    }
    $uarts = @($ports | Where-Object { $_.Role -eq 'uart' })
    if ($uarts.Count -eq 1) {
        $script:Port = $uarts[0].Port
        Say "Found the AUP-ZU3 serial port: $($script:Port)" "已找到 AUP-ZU3 串口：$($script:Port)"
        return
    }
    if ($uarts.Count -gt 1) {
        Say 'More than one AUP-ZU3 is connected.' '连接了多块 AUP-ZU3。'
        $candidates = $uarts
    } else {
        Say 'No AUP-ZU3 was recognised. Is the cable in the port marked PROG UART? You can still pick a port:' `
            '没有识别到 AUP-ZU3。线是否插在 PROG UART 接口上？也可以手动选择一个串口：'
        $candidates = $ports
    }
    for ($i = 0; $i -lt $candidates.Count; $i++) {
        Write-Host ('  [{0}] {1}  {2}' -f ($i + 1), $candidates[$i].Port, $candidates[$i].Name)
    }
    $reply = Read-Host (T 'Number of the port to open' '请输入要打开的串口编号')
    $choice = 0
    if (-not [int]::TryParse($reply, [ref]$choice) -or $choice -lt 1 -or $choice -gt $candidates.Count) {
        Die 'Not a valid number.' '编号无效。'
    }
    $script:Port = $candidates[$choice - 1].Port
}

# Windows needs no special rights for a COM port, but only one program can hold it at a time.
function Wait-PortFree {
    while (-not (Test-PortFree $script:Port)) {
        $reply = Read-Host (T "$($script:Port) is in use by another program, such as PuTTY, Tera Term, the Vitis terminal or another COMTool. Close it, then press Enter (q to quit)" `
                "$($script:Port) 正被其他程序占用，例如 PuTTY、Tera Term、Vitis 终端或另一个 COMTool。请关闭它，然后按回车（输入 q 退出）")
        if ($reply -eq 'q') { Die 'Cancelled.' '已取消。' }
    }
}

function Get-VerifiedFile([string]$Url, [string]$Path, [string]$Sha256) {
    & curl.exe -L --fail --retry 3 -o $Path $Url
    if ($LASTEXITCODE -ne 0) { Die 'The download failed. Check your network and try again.' '下载失败。请检查网络后重试。' }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant() -ne $Sha256) {
        Remove-Item -LiteralPath $Path
        Die 'A downloaded file is damaged. Run the script again.' '下载的文件已损坏，请重新运行脚本。'
    }
}

function Install-Comtool {
    if (Test-Path -LiteralPath $ComtoolExe) { return }
    New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null
    Say "Downloading COMTool $ComtoolVersion (first run only) ..." "正在下载 COMTool $ComtoolVersion（仅首次运行需要）..."
    $archive = Join-Path $ToolsDir $ComtoolArchive
    $extractor = Join-Path $ToolsDir '7zr.exe'
    Get-VerifiedFile $SevenZipUrl $extractor $SevenZipSha256
    Get-VerifiedFile $ComtoolUrl $archive $ComtoolSha256
    & $extractor x -y "-o$ToolsDir" $archive | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $ComtoolExe)) {
        Die 'COMTool could not be unpacked. Check that antivirus is not blocking it, then run the script again.' 'COMTool 解压失败。请确认杀毒软件没有拦截，然后重新运行脚本。'
    }
    Remove-Item -LiteralPath $archive, $extractor
}

# Fills in COMTool's config so that it opens on this port and saves the log to a file. Its
# serial settings only accept known keys: anything unexpected there stops it from starting.
# COMTool on Windows reads config.json from its working directory, and rejects a BOM.
function Write-ComtoolConfig {
    New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
    $path = Join-Path $ComtoolDir 'config.json'
    $config = $null
    if (Test-Path -LiteralPath $path) {
        try { $config = [IO.File]::ReadAllText($path) | ConvertFrom-Json } catch { $config = $null }
    }
    if ($null -eq $config -or $config.version -ne 3) {
        $config = [pscustomobject]@{
            version = 3; skin = 'light'; locale = 'en'; encoding = 'UTF-8'; skipVersion = $null
            connId = 'serial'; pluginsInfo = [pscustomobject]@{ external = [pscustomobject]@{} }
            activeItem = 'dbg-1'; currItem = $null; items = @()
        }
    }
    $item = @($config.items) | Where-Object { $null -ne $_ -and $_.pluginId -eq 'dbg' } | Select-Object -First 1
    if ($null -eq $item) {
        $item = [pscustomobject]@{
            name = 'Send Receive'; pluginId = 'dbg'
            config = [pscustomobject]@{ conns = [pscustomobject]@{}; plugin = [pscustomobject]@{} }
        }
        $config.items = @($item) + @(@($config.items) | Where-Object { $null -ne $_ })
    }
    $item.config.conns = [pscustomobject]@{
        currConn = 'serial'
        serial = [pscustomobject]@{ port = $script:Port; baudrate = $Baud }
    }
    $plugin = $item.config.plugin
    $plugin | Add-Member -Force -NotePropertyName saveLog -NotePropertyValue $true
    $plugin | Add-Member -Force -NotePropertyName saveLogAutoNew -NotePropertyValue $true
    $plugin | Add-Member -Force -NotePropertyName saveLogPath -NotePropertyValue (Join-Path $LogDir 'zu3.log')
    if ($script:Lang -eq 'zh') { $config.locale = 'zh_CN' } else { $config.locale = 'en' }
    $config.currItem = $item.name
    [IO.File]::WriteAllText($path, ($config | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding $false))
}

function Invoke-SerialTool {
    if ($List) {
        Show-Ports
        return
    }
    Select-Port
    Wait-PortFree
    Install-Comtool
    Write-ComtoolConfig
    Start-Process -FilePath $ComtoolExe -WorkingDirectory $ComtoolDir
    Write-Host ''
    Say "Port $($script:Port) at $Baud baud. In COMTool:" "串口 $($script:Port)，波特率 $Baud。在 COMTool 中："
    Say "  1. Check that the Port box shows $($script:Port), then click OPEN." "  1. 确认 Port（端口）一栏显示 $($script:Port)，然后点击 OPEN（打开）。"
    Say "  2. Press the board's reset button to see the log from the very start." '  2. 按开发板上的复位键，即可从头查看启动日志。'
    Say "  Logs are saved in $LogDir" "  日志保存在 $LogDir"
}

try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false } catch { }
$exitCode = 0
try {
    Select-Language
    Invoke-SerialTool
} catch {
    Write-Host ''
    Write-Host "[$(T 'ERROR' '错误')] $($_.Exception.Message)" -ForegroundColor Red
    $exitCode = 1
}
Write-Host ''
Read-Host (T 'Press Enter to close this window' '按回车关闭此窗口') | Out-Null
exit $exitCode
