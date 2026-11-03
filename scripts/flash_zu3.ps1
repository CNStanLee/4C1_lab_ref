#Requires -Version 5.1
# One-click PYNQ image download and microSD flashing for the AUP-ZU3 on Windows.
# Students should double-click flash_zu3.bat. Keep this file saved as UTF-8 with a BOM:
# Windows PowerShell misreads the Chinese messages without one. PowerShell also treats curly
# quotes as string delimiters, so the messages below only use straight quotes.
[CmdletBinding()]
param(
    [ValidateSet('4gb', '8gb')][string]$Variant,
    [int]$DiskNumber = -1,
    [string]$Zip,
    [switch]$NoVerify,
    [switch]$AllowLarge,
    [ValidateSet('en', 'zh')][string]$Lang
)

$ErrorActionPreference = 'Stop'
$PynqVersion = '3.1.1'
$BaseUrl = 'https://download.amd.com/opendownload/pynq'
# Refuse bigger disks unless -AllowLarge: a card this large is rare, an external drive is not.
$MaxCardBytes = 256000000000
$RepoDir = Split-Path -Parent $PSScriptRoot
$DownloadDir = Join-Path $RepoDir 'downloads'

# Size and checksum of AMD's published files, recorded on 2026-11-03. AMD publishes no
# checksums of its own, so a mismatch means a damaged download or a re-released file.
$Images = @{
    '4gb' = @{ ZipSize = [long]2204633663; ImgSize = [long]9755315200; Sha256 = 'b21dd5daab6c835cfc43140180a5a267ac2b43697b51d3a02b9f6288e77ca3fb' }
    '8gb' = @{ ZipSize = [long]2204637418; ImgSize = [long]9755336704; Sha256 = 'c995d48a1184452be1b18faaf492e8b46100cd29afa100cb83cf670662648b9f' }
}

$RawDiskSource = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace Zu3
{
    public static class RawDisk
    {
        const int ChunkBytes = 4 * 1024 * 1024;
        const int AlignBytes = 4096;

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr security,
            uint disposition, uint flags, IntPtr template);

        public static FileStream OpenDisk(int number)
        {
            const uint GenericReadWrite = 0xC0000000, ShareReadWrite = 3, OpenExisting = 3, WriteThrough = 0x80000000;
            string path = @"\\.\PhysicalDrive" + number;
            SafeFileHandle handle = CreateFileW(path, GenericReadWrite, ShareReadWrite, IntPtr.Zero, OpenExisting, WriteThrough, IntPtr.Zero);
            if (handle.IsInvalid)
                throw new IOException("Cannot open " + path + " (Windows error " + Marshal.GetLastWin32Error() + ")");
            // A buffer size of 1 sends every read and write straight to the disk.
            return new FileStream(handle, FileAccess.ReadWrite, 1, false);
        }

        // Returns a full buffer's worth unless the stream ends: inflating a zip gives short reads.
        static int Fill(Stream stream, byte[] buffer, int count)
        {
            int total = 0;
            while (total < count)
            {
                int got = stream.Read(buffer, total, count - total);
                if (got == 0) break;
                total += got;
            }
            return total;
        }

        // Raw disk I/O must cover whole sectors.
        static int PadToSector(byte[] buffer, int length)
        {
            int padding = (AlignBytes - length % AlignBytes) % AlignBytes;
            Array.Clear(buffer, length, padding);
            return length + padding;
        }

        static void Compare(byte[] expected, byte[] actual, int length, long offset)
        {
            for (int i = 0; i < length; i++)
                if (expected[i] != actual[i])
                    throw new InvalidDataException("Card differs from the image at byte " + (offset + i));
        }

        static void ShowProgress(string label, long done, long total, Stopwatch clock, ref long lastMs)
        {
            if (clock.ElapsedMilliseconds - lastMs < 1000 && done < total) return;
            lastMs = clock.ElapsedMilliseconds;
            double seconds = Math.Max(clock.Elapsed.TotalSeconds, 0.001);
            double bytesPerSecond = done / seconds;
            long remaining = (long)((total - done) / Math.Max(bytesPerSecond, 1));
            Console.Write("\r  {0} {1,5:F1}%  {2,5:F1} MB/s  {3}:{4:00} left   ", label, 100.0 * done / total,
                bytesPerSecond / 1000000, remaining / 60, remaining % 60);
        }

        // Windows mounts partitions, and then refuses writes to them, as soon as it sees a
        // partition table. The table lives in the first chunk, so that chunk goes last. The body is
        // also read back before then, since a mounted volume may change on its own and fail the check.
        public static void Flash(Stream image, Stream imageForVerify, long imageBytes, FileStream disk,
            string writeLabel, string verifyLabel)
        {
            byte[] head = new byte[ChunkBytes];
            byte[] buffer = new byte[ChunkBytes];
            int headRaw = Fill(image, head, ChunkBytes);
            int headLength = PadToSector(head, headRaw);

            long done = headRaw;
            long lastMs = 0;
            Stopwatch clock = Stopwatch.StartNew();
            disk.Position = headLength;
            while (true)
            {
                int got = Fill(image, buffer, ChunkBytes);
                if (got == 0) break;
                disk.Write(buffer, 0, PadToSector(buffer, got));
                done += got;
                ShowProgress(writeLabel, done, imageBytes, clock, ref lastMs);
            }
            disk.Flush(true);
            Console.WriteLine();
            if (done != imageBytes)
                throw new InvalidDataException("The image holds " + done + " bytes, expected " + imageBytes);

            if (imageForVerify != null)
            {
                byte[] actual = new byte[ChunkBytes];
                Fill(imageForVerify, buffer, ChunkBytes); // the head is checked after it is written
                long offset = headLength;
                done = headRaw;
                lastMs = 0;
                clock = Stopwatch.StartNew();
                disk.Position = headLength;
                while (true)
                {
                    int got = Fill(imageForVerify, buffer, ChunkBytes);
                    if (got == 0) break;
                    int length = PadToSector(buffer, got);
                    if (Fill(disk, actual, length) != length)
                        throw new InvalidDataException("Card ended early at byte " + offset);
                    Compare(buffer, actual, length, offset);
                    offset += length;
                    done += got;
                    ShowProgress(verifyLabel, done, imageBytes, clock, ref lastMs);
                }
                Console.WriteLine();
            }

            disk.Position = 0;
            disk.Write(head, 0, headLength);
            disk.Flush(true);
            if (imageForVerify != null)
            {
                disk.Position = 0;
                if (Fill(disk, buffer, headLength) != headLength)
                    throw new InvalidDataException("Card ended early at byte 0");
                Compare(head, buffer, headLength, 0);
            }
        }
    }
}
'@

function T([string]$En, [string]$Zh) { if ($script:Lang -eq 'zh') { $Zh } else { $En } }
function Say([string]$En, [string]$Zh) { Write-Host (T $En $Zh) }
function Step([string]$En, [string]$Zh) { Write-Host ''; Write-Host "==== $(T $En $Zh) ====" -ForegroundColor Cyan }
function Die([string]$En, [string]$Zh) { throw (T $En $Zh) }
function HumanSize([long]$Bytes) { '{0:F1} GB' -f ($Bytes / 1000000000) }

function Restart-Elevated($Bound) {
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    foreach ($param in $Bound.GetEnumerator()) {
        if ($param.Value -is [System.Management.Automation.SwitchParameter]) {
            if ($param.Value.IsPresent) { $argList += "-$($param.Key)" }
        } else {
            $argList += "-$($param.Key)"
            $argList += "`"$($param.Value)`""
        }
    }
    try {
        Start-Process -FilePath powershell.exe -Verb RunAs -ArgumentList $argList
    } catch {
        Write-Host 'Writing to a card needs administrator rights. Run again and click Yes.'
        Write-Host '写入存储卡需要管理员权限。请重新运行并点击"是"。'
        exit 1
    }
}

function Select-Language {
    if ($script:Lang) { return }
    $reply = Read-Host 'Language / 语言: [1] English (default)  [2] 中文'
    if ($reply -eq '2') { $script:Lang = 'zh' } else { $script:Lang = 'en' }
}

function Select-Variant {
    while (-not $script:Variant) {
        Say 'Look at your board: next to the memory chips it is marked "4G" or "8G".' `
            '请看开发板：内存芯片旁边印有 "4G" 或 "8G"。'
        $reply = Read-Host (T 'Which one is printed on your board? [4/8]' '你的板子上印的是哪个？[4/8]')
        if ($reply -match '^4(g|gb)?$') { $script:Variant = '4gb' }
        elseif ($reply -match '^8(g|gb)?$') { $script:Variant = '8gb' }
    }
}

function Describe-Disk($Disk) {
    'Disk {0}  {1}  {2}  [{3}]' -f $Disk.Number, (HumanSize $Disk.Size), $Disk.FriendlyName, $Disk.BusType
}

# Disks that look like an SD card: USB readers, removable disks and built-in SD slots.
function Get-CardCandidates {
    $removable = @(Get-CimInstance Win32_DiskDrive |
        Where-Object { $_.MediaType -like 'Removable*' } |
        ForEach-Object { [int]$_.Index })
    @(Get-Disk | Where-Object {
            -not $_.IsBoot -and -not $_.IsSystem -and $_.Size -gt 0 -and
            ($_.BusType -in 'USB', 'SD', 'MMC' -or $removable -contains [int]$_.Number)
        } | Sort-Object Number)
}

function Test-Target($Disk) {
    $size = HumanSize $Disk.Size
    if ($Disk.IsBoot -or $Disk.IsSystem) {
        Die "Disk $($Disk.Number) holds your running system. Refusing to touch it." "磁盘 $($Disk.Number) 上装着正在运行的系统，已拒绝操作。"
    }
    if ($Disk.IsReadOnly) {
        Die "Disk $($Disk.Number) is read-only. If your card adapter has a lock switch, slide it to unlocked." `
            "磁盘 $($Disk.Number) 是只读的。如果读卡器或卡套上有锁定开关，请拨到解锁位置。"
    }
    if ($Disk.Size -lt $script:Image.ImgSize) {
        Die "Disk $($Disk.Number) has $size, the image needs $(HumanSize $script:Image.ImgSize). Use a 16 GB or larger card." `
            "磁盘 $($Disk.Number) 容量为 $size，镜像需要 $(HumanSize $script:Image.ImgSize)。请使用 16 GB 或更大的卡。"
    }
    if ($Disk.Size -gt $MaxCardBytes -and -not $AllowLarge) {
        Die "Disk $($Disk.Number) has $size, which looks like a drive rather than a card. Use -AllowLarge if you are sure." `
            "磁盘 $($Disk.Number) 容量为 $size，看起来是硬盘而不是存储卡。如果确定无误，请加 -AllowLarge。"
    }
}

function Select-Card {
    if ($DiskNumber -ge 0) {
        $disk = Get-Disk -Number $DiskNumber
        Test-Target $disk
        return $disk
    }
    while ($true) {
        $cards = @(Get-CardCandidates)
        if ($cards.Count -eq 0) {
            $reply = Read-Host (T 'No SD card found. Insert the card, then press Enter to look again (q to quit)' '没有找到 SD 卡。请插入存储卡，然后按回车重新查找（输入 q 退出）')
            if ($reply -eq 'q') { Die 'Cancelled. Nothing was changed.' '已取消，未做任何更改。' }
            Start-Sleep -Seconds 2
            continue
        }
        Say 'These disks look like SD cards:' '以下磁盘看起来是 SD 卡：'
        for ($i = 0; $i -lt $cards.Count; $i++) {
            Write-Host ('  [{0}] {1}' -f ($i + 1), (Describe-Disk $cards[$i]))
        }
        $reply = Read-Host (T 'Number of your card (Enter to look again)' '请输入存储卡的编号（按回车重新查找）')
        $choice = 0
        if ([int]::TryParse($reply, [ref]$choice) -and $choice -ge 1 -and $choice -le $cards.Count) {
            $disk = $cards[$choice - 1]
            Test-Target $disk
            return $disk
        }
    }
}

function Confirm-Erase($Disk) {
    Write-Host ''
    Say 'EVERYTHING on this disk will be permanently erased:' '这块磁盘上的所有数据都将被永久清除：'
    Write-Host "  $(Describe-Disk $Disk)" -ForegroundColor Yellow
    Get-Partition -DiskNumber $Disk.Number -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host ('    {0}  {1}' -f (HumanSize $_.Size), $_.DriveLetter)
    }
    $reply = Read-Host (T 'Type ERASE to continue' '确认无误请输入 ERASE 继续')
    if ($reply -cne 'ERASE') { Die 'Cancelled. Nothing was changed.' '已取消，未做任何更改。' }
}

function Test-Sha256([string]$Path) {
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant() -eq $script:Image.Sha256
}

function Get-ImageZip {
    $zipName = "AUP-ZU3-$PynqVersion-$($script:Variant).zip"
    if ($Zip) {
        if (-not (Test-Path -LiteralPath $Zip -PathType Leaf)) { Die "File not found: $Zip" "找不到文件：$Zip" }
        Say "Checking $Zip ..." "正在校验 $Zip ..."
        if (-not (Test-Sha256 $Zip)) { Die "$Zip is not the official $zipName." "$Zip 不是官方的 $zipName。" }
        return (Resolve-Path -LiteralPath $Zip).Path
    }

    New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null
    $dest = Join-Path $DownloadDir $zipName
    $have = [long]0
    if (Test-Path -LiteralPath $dest) { $have = (Get-Item -LiteralPath $dest).Length }
    if ($have -gt $script:Image.ZipSize) {
        Remove-Item -LiteralPath $dest
        $have = 0
    }
    if ($have -lt $script:Image.ZipSize) {
        $need = $script:Image.ZipSize - $have
        $free = (New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($DownloadDir))).AvailableFreeSpace
        if ($free -lt $need) {
            Die "Not enough free disk space: the download needs $(HumanSize $need)." "磁盘空间不足：下载还需要 $(HumanSize $need)。"
        }
        Say "Downloading $zipName ($(HumanSize $script:Image.ZipSize)). If this stops, run the script again and it will resume." `
            "正在下载 $zipName（$(HumanSize $script:Image.ZipSize)）。如果中断，重新运行脚本即可继续下载。"
        & curl.exe -L --fail --retry 5 --retry-delay 5 -C - -o $dest "$BaseUrl/$zipName"
        if ($LASTEXITCODE -ne 0) { Die 'The download failed. Check your network and run the script again.' '下载失败。请检查网络后重新运行脚本。' }
    }
    Say 'Checking the download ...' '正在校验下载的文件 ...'
    if (-not (Test-Sha256 $dest)) {
        Remove-Item -LiteralPath $dest
        Die 'The downloaded file is damaged and was deleted. Run the script again. If this keeps happening, AMD may have re-released the image: follow the manual steps in the guide and tell your TA.' `
            '下载的文件已损坏并已删除，请重新运行脚本。如果反复出现，可能是 AMD 重新发布了镜像：请按指引中的手动步骤操作并告知助教。'
    }
    $dest
}

function Assert-ZipNotOnCard($Disk, [string]$ZipPath) {
    $letter = [IO.Path]::GetPathRoot($ZipPath).TrimEnd('\').TrimEnd(':')
    $onCard = @(Get-Partition -DiskNumber $Disk.Number -ErrorAction SilentlyContinue | Where-Object { "$($_.DriveLetter)" -eq $letter })
    if ($onCard.Count -gt 0) {
        Die "The image file is on the disk you are about to erase. Copy it to your computer first." '镜像文件就在要被清除的磁盘上。请先把它复制到电脑上。'
    }
}

# Removes the partitions so that Windows has no volume to protect while the card is written.
function Clear-Card($Disk) {
    $scriptFile = Join-Path $env:TEMP "zu3_diskpart_$PID.txt"
    Set-Content -LiteralPath $scriptFile -Encoding Ascii -Value @("select disk $($Disk.Number)", 'clean', 'exit')
    try {
        foreach ($attempt in 1..3) {
            $output = & diskpart.exe /s $scriptFile
            if ($LASTEXITCODE -eq 0) { return }
            Start-Sleep -Seconds 3 # Windows can hold a just-unmounted card for a moment
        }
    } finally {
        Remove-Item -LiteralPath $scriptFile -ErrorAction SilentlyContinue
    }
    Write-Host ($output -join "`n")
    Die 'Windows could not prepare the card. Re-insert it and try again, or try a different card.' 'Windows 无法准备这张卡。请重新插入后再试，或换一张卡。'
}

function Write-Card($Disk, [string]$ZipPath) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (-not ('Zu3.RawDisk' -as [type])) { Add-Type -TypeDefinition $RawDiskSource }

    $imgName = "AUP-ZU3-$PynqVersion-$($script:Variant).img"
    $imageBytes = $script:Image.ImgSize
    $archive = [IO.Compression.ZipFile]::OpenRead($ZipPath)
    $disk_ = $null
    $source = $null
    $sourceForVerify = $null
    try {
        $entry = $archive.GetEntry($imgName)
        if ($null -eq $entry) { Die "$imgName is missing from the zip." "压缩包中缺少 $imgName。" }
        $source = $entry.Open()
        if (-not $NoVerify) { $sourceForVerify = $entry.Open() }
        $disk_ = [Zu3.RawDisk]::OpenDisk($Disk.Number)
        Say 'Writing the card takes 5-15 minutes, and checking it another 5-10.' '写入存储卡需要 5-15 分钟，回读校验另需 5-10 分钟。'
        [Zu3.RawDisk]::Flash($source, $sourceForVerify, $imageBytes, $disk_, (T 'Writing ' '写入'), (T 'Checking' '校验'))
    } catch {
        Write-Host ''
        Write-Host $_.Exception.Message -ForegroundColor Red
        if ($_.Exception.InnerException -is [IO.InvalidDataException]) {
            Die 'The card does not match the image: it is faulty or fake. Try a different card.' '存储卡内容与镜像不一致：卡可能已损坏或是扩容假卡，请换一张卡。'
        }
        Die 'Writing failed. Do not boot from this card. Close other programs that might use it, check that antivirus is not blocking this script, then re-insert the card and try again, or try a different card.' `
            '写入失败。请不要用这张卡启动。请关闭可能占用它的程序，确认杀毒软件没有拦截本脚本，然后重新插入存储卡再试，或换一张卡。'
    } finally {
        foreach ($item in @($disk_, $sourceForVerify, $source, $archive)) {
            if ($null -ne $item) { $item.Dispose() }
        }
    }
}

function Invoke-Flash {
    Step "AUP-ZU3 PYNQ image v$PynqVersion" "AUP-ZU3 PYNQ 镜像 v$PynqVersion"

    Step 'Step 1 of 4: choose your board' '第 1/4 步：选择开发板'
    Select-Variant
    $script:Image = $Images[$script:Variant]
    Say "Image: AUP-ZU3-$PynqVersion-$($script:Variant).img" "镜像：AUP-ZU3-$PynqVersion-$($script:Variant).img"

    Step 'Step 2 of 4: choose your card' '第 2/4 步：选择存储卡'
    $disk = Select-Card
    Confirm-Erase $disk

    Step 'Step 3 of 4: get the image' '第 3/4 步：获取镜像'
    Say 'You can leave this running from here on. Nothing else needs your input.' '从这里开始无需再操作，可以让它自动运行。'
    $zipPath = Get-ImageZip

    Step 'Step 4 of 4: write the card' '第 4/4 步：写入存储卡'
    $current = Get-Disk -Number $disk.Number -ErrorAction SilentlyContinue
    if ($null -eq $current -or $current.Size -ne $disk.Size -or $current.SerialNumber -ne $disk.SerialNumber) {
        Die "Disk $($disk.Number) changed while the image was downloading. Check the card and run the script again; the download is kept." `
            "下载期间磁盘 $($disk.Number) 发生了变化。请检查存储卡后重新运行脚本，已下载的文件会保留。"
    }
    Test-Target $current
    Assert-ZipNotOnCard $current $zipPath
    Say 'If Windows asks to format a disk, from now on or later, click Cancel. Formatting would destroy the image.' `
        '从现在起，如果 Windows 提示要格式化磁盘，请一律点击"取消"。格式化会毁掉镜像。'
    Clear-Card $current
    Write-Card $current $zipPath
    Update-Disk -Number $current.Number -ErrorAction SilentlyContinue

    Step 'Done' '完成'
    Say 'The card is ready. Close any format prompts with Cancel, then remove the card. Next: follow the "Boot the board" section of the guide.' `
        '存储卡已写好。如有格式化提示请点"取消"关闭，然后拔出存储卡。下一步：请按指引中的"启动开发板"一节操作。'
}

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    if ($Zip) { $PSBoundParameters['Zip'] = (Resolve-Path -LiteralPath $Zip).Path }
    Restart-Elevated $PSBoundParameters
    exit 0
}

try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false } catch { }
$exitCode = 0
try {
    Select-Language
    Invoke-Flash
} catch {
    Write-Host ''
    Write-Host "[$(T 'ERROR' '错误')] $($_.Exception.Message)" -ForegroundColor Red
    $exitCode = 1
}
Write-Host ''
Read-Host (T 'Press Enter to close this window' '按回车关闭此窗口') | Out-Null
exit $exitCode
