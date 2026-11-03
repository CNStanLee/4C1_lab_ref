# AUP-ZU3 PYNQ 上手指引

[English](README.md) | **简体中文**

这份指引带你从一块全新的 AUP-ZU3 开发板开始，一直到在浏览器里使用运行起来的 PYNQ 系统。不需要任何 FPGA 或 Linux 基础，Windows 和 Ubuntu 都适用。

全程大约需要一小时，其中大部分时间是在等待下载和写卡。

**赶时间？** 完成[第 1 步](#1-检查所需物品)和[第 2 步](#2-获取这些文件)后，运行对应系统的一键脚本：

| | 写入存储卡 | 查看开发板日志 |
|---|---|---|
| **Windows** | 双击 `scripts\flash_zu3.bat` | 双击 `scripts\serial_zu3.bat` |
| **Ubuntu** | `bash scripts/flash_zu3.sh` | `bash scripts/serial_zu3.sh` |

## 你会遇到的术语

| 术语 | 含义 |
|---|---|
| **PYNQ** | AMD 推出的一套系统，可以用 Python 控制 FPGA。 |
| **镜像（Image）** | 一个包含完整操作系统的文件，可以直接复制到存储卡上。 |
| **烧录（Flashing）** | 把镜像逐字节复制到存储卡上。卡上原有的内容会全部被清除。 |
| **串口（UART）** | 与开发板之间的一条简单文本连接。即使其他功能都没有工作，它也能显示信息，所以是排查开发板无法启动的主要工具。 |
| **Jupyter** | 用来在开发板上编写和运行 Python 的网页。 |

## 1. 检查所需物品

| 物品 | 说明 |
|---|---|
| AUP-ZU3 开发板 | 在内存芯片旁边找到 **4G** 或 **8G** 标记，后面需要用到。 |
| microSD 卡 | **16 GB 或更大**，请选择知名品牌。卡上的所有内容都会被清除。 |
| SD 读卡器 | 电脑自带的卡槽或 USB 读卡器都可以。 |
| USB-C 电源 | 必须支持 USB PD 协议的 **9 V、3 A** 输出。普通手机充电器或电脑 USB 口通常达不到要求。 |
| USB-C 线 2 或 3 根 | 一根供电，一根连接 Jupyter，一根查看串口日志（可选，但调试时必须用到）。线材必须能传输数据，有些线只能充电。 |
| 电脑 | Windows 10 或 11，或者 Ubuntu 22.04 或 24.04，至少有 3 GB 可用磁盘空间。 |

## 2. 获取这些文件

1. 在本仓库 GitHub 页面的顶部，点击绿色的 **Code** 按钮，然后点击 **Download ZIP**。
2. 解压：
   - **Windows：** 右键点击 ZIP 文件，选择 **全部解压缩**。如果不解压就直接在 ZIP 里运行，脚本将无法工作。
   - **Ubuntu：** 右键点击 ZIP 文件，选择 **提取到此处**。

如果你已经在使用 git，也可以运行 `git clone https://github.com/CNStanLee/4C1_lab_ref.git`。

## 3. 把镜像写入存储卡

把 microSD 卡插入电脑，然后选择**方式 A**（推荐）或**方式 B**。

> [!WARNING]
> 这一步会永久清除你所选磁盘上的数据。请先备份卡上的内容，并拔掉其他 USB 存储设备，以免选错。

### 方式 A：一键脚本

脚本会自动完成所有工作：下载正确的镜像、校验文件、写入存储卡，并回读存储卡以确认写入无误。

**Windows：**

1. 打开 `scripts` 文件夹，双击 **`flash_zu3.bat`**。
2. 如果出现蓝色的“Windows 已保护你的电脑”窗口，点击**更多信息**，再点击**仍要运行**。
3. 当 Windows 询问是否允许此应用进行更改时，点击**是**。随后会打开一个新窗口。

**Ubuntu：**

1. 打开解压后的文件夹，在空白处右键，选择**在终端中打开**。
2. 输入下面的命令并按回车：

   ```bash
   bash scripts/flash_zu3.sh
   ```

3. 如果要求输入密码，请输入你的 Ubuntu 登录密码并按回车。输入时屏幕上不会显示任何字符，这是正常现象。

**两个系统接下来都一样**，脚本会询问四件事：

```text
Language / 语言: [1] English (default)  [2] 中文 : 2

==== 第 1/4 步：选择开发板 ====
请看开发板：内存芯片旁边印有 “4G” 或 “8G”。
你的板子上印的是哪个？[4/8]： 8

==== 第 2/4 步：选择存储卡 ====
以下磁盘看起来是 SD 卡：
  [1] /dev/sdb  32GB  Generic SD Reader
请输入存储卡的编号（按回车重新查找）： 1

这块磁盘上的所有数据都将被永久清除：
  /dev/sdb  32GB  Generic SD Reader
确认无误请输入 ERASE 继续： ERASE
```

输入 `ERASE` 之前，请确认容量与你的存储卡相符。Windows 显示的是磁盘编号，而不是 `/dev/sdb`。

之后就可以离开了。整个过程通常需要 15 到 45 分钟，取决于网络和存储卡的速度。请等到屏幕上出现**完成**。

> [!IMPORTANT]
> **仅限 Windows：** Windows 无法识别存储卡上的其中一个分区，因此可能提示**“需要将磁盘格式化”**。请一律点击**取消**。格式化会毁掉镜像。

如果下载中断，重新运行脚本即可，它会从中断处继续。

### 方式 B：用 balenaEtcher 手动写入

如果脚本在你的电脑上无法运行，请使用这种方式。

1. 下载与开发板对应的镜像。每个文件约 2.2 GB，下载后不需要解压。

   | 板上标记 | 下载 |
   |---|---|
   | 4G | [AUP-ZU3-3.1.1-4gb.zip](https://download.amd.com/opendownload/pynq/AUP-ZU3-3.1.1-4gb.zip) |
   | 8G | [AUP-ZU3-3.1.1-8gb.zip](https://download.amd.com/opendownload/pynq/AUP-ZU3-3.1.1-8gb.zip) |

2. 安装并打开 [balenaEtcher](https://etcher.balena.io/)。
3. 点击 **Flash from file**，选择下载好的 ZIP 文件。
4. 点击 **Select target**，选择你的存储卡，并仔细核对容量。
5. 点击 **Flash!**，等待写入和校验全部完成。

## 4. 启动开发板

![AUP-ZU3 接线图：BOOT 开关拨到 SD，插入 microSD 卡，USB-C 数据线接 USB 3.0 DRP I，USB-C 电源接 EXT PWR](https://xilinx.github.io/AUP-ZU3/images/aup_zu3_setup.png)

*图片来自 AMD 的 [AUP-ZU3 入门指南](https://xilinx.github.io/AUP-ZU3/getting_started.html)。*

在电源开关处于**关闭**状态时，按图中的编号操作：

1. 把 **BOOT** 开关拨到 **SD**。
2. 把 microSD 卡推入卡槽，卡的金属触点朝向电路板。
3. 用 USB-C 线连接电脑和标有 **USB 3.0 DRP I** 的接口。
4. 把 USB-C 电源接到标有 **EXT PWR** 的接口。

然后**打开**电源开关，观察指示灯：

| 时间 | 应该看到 | 含义 |
|---|---|---|
| 立即 | **ON** 灯亮起，两个 **PS** 灯也亮起，其中一个像心跳一样闪烁 | 开发板已通电并开始启动 |
| 30 到 60 秒 | **DONE** 灯亮起 | FPGA 已完成配置 |
| 几秒钟后 | 8 个白色 LED 闪烁，4 个彩色 LED 交替变色 | **开发板已就绪** |

如果情况不是这样，请查看[第 6 步](#6-查看开发板日志)或[常见问题](#常见问题)。

## 5. 打开 Jupyter

第 4 步接的 USB 线相当于电脑和开发板之间的一个小型网络。它一般会自动连接，电脑也会自动获得地址。

1. 打开浏览器，访问 **<http://192.168.3.1/lab>**。
2. 提示输入密码时，输入 **`xilinx`**。

现在应该能看到 JupyterLab，左侧的文件列表中有示例 notebook。**开发板已经可以使用了。** 🎉

如果页面打不开，也可以试试 <http://192.168.3.1:9090/lab>。

**关闭开发板之前，** 请在 Jupyter 中打开终端，运行 `sudo poweroff`，然后等待约 10 秒。在 Linux 运行时直接断电，可能会损坏存储卡上的文件。

## 6. 查看开发板日志

开发板从启动的那一刻起就会通过串口输出信息。出现问题时，日志通常能告诉你原因，这也是助教最想看到的内容。`serial_zu3` 工具会找到正确的串口、处理好权限，并在免费的串口终端 [COMTool](https://github.com/Neutree/COMTool) 中打开。COMTool 会在首次运行时自动下载。

1. 用 USB-C 线连接电脑和标有 **PROG UART** 的接口，然后打开开发板电源。
2. 启动工具：
   - **Windows：** 双击 **`scripts\serial_zu3.bat`**。
   - **Ubuntu：** 运行 `bash scripts/serial_zu3.sh`。首次运行时可能要求输入密码，以便为你开通串口权限。
3. 在 COMTool 中确认 **Port（端口）** 显示的是工具找到的串口，然后点击 **OPEN（打开）**。
4. 按开发板上的**复位键**重启，完整的日志就会从头开始滚动显示。

串口参数是波特率 115200、8 位数据位、无校验、1 位停止位，工具会自动填好。每次连接的日志都会自动保存到 `logs` 文件夹下带时间戳的文件中，方便发给助教。

### 如何看日志

开发板分阶段启动。根据能看到的最后一个阶段，就能大致判断问题所在：

| 阶段 | 关键内容 | 如果停在这里 |
|---|---|---|
| 没有任何输出 | 复位后没有文字 | 检查 BOOT 开关是否在 **SD**，存储卡是否已插入。如果都没问题，请重新写卡。 |
| 第一阶段引导 | `Xilinx Zynq MP First Stage Boot Loader` | 存储卡可能有问题。请重新写卡，最好换一张卡。 |
| U-Boot | `U-Boot` | 启动文件或存储卡可能有问题。请重新写卡，并确认所选镜像与板上的 4G 或 8G 标记一致。 |
| Linux | `Starting kernel`，然后是大量信息 | 记下最后几行以及其中的 `error` 或 `panic`，并保存日志交给助教。 |
| 启动完成 | 登录提示，或 `root@pynq:~#` 这样的命令提示符 | 系统已启动。如果要求登录，用户名和密码都是 `xilinx`。 |

要运行命令，请在 COMTool 底部的发送框中输入，然后点击 **Send（发送）**。例如，`ip a` 可以查看开发板的网络地址，其中应该包含 `192.168.3.1`。

### 工具的其他用法

| 任务 | Windows（在仓库文件夹下的 PowerShell 中） | Ubuntu |
|---|---|---|
| 只列出串口 | `.\scripts\serial_zu3.bat -List` | `bash scripts/serial_zu3.sh --list` |
| 手动指定串口 | `.\scripts\serial_zu3.bat -Port COM5` | `bash scripts/serial_zu3.sh --port /dev/ttyUSB1` |
| 用终端代替 COMTool | 不支持 | `bash scripts/serial_zu3.sh --cli` |

## 常见问题

### 写入存储卡

| 问题 | 解决方法 |
|---|---|
| 脚本没有列出我的存储卡 | 拔出存储卡再重新插入，然后按回车重新查找。也可以换一个 USB 口或读卡器。 |
| 提示 “read-only”（只读） | 有些卡套侧面有一个小的锁定开关，请把它拨离 **LOCK** 一侧。 |
| 提示存储卡内容与镜像不一致 | 这张卡已损坏，或者是虚标容量的假卡。请换一张知名品牌的存储卡。 |
| Windows 上提示写入失败 | 关闭文件资源管理器窗口和其他可能占用存储卡的程序，然后重试。杀毒软件也可能拦截写入。如果一直失败，请使用[方式 B](#方式-b用-balenaetcher-手动写入)。 |
| 下载一直失败，或提示文件已损坏 | 换一个更稳定的网络，然后重新运行脚本。如果仍然失败，可能是 AMD 更换了文件，请使用[方式 B](#方式-b用-balenaetcher-手动写入)并告知助教。 |
| Windows 提示磁盘需要格式化 | 点击**取消**。这是正常现象。 |
| 窗口中的中文显示为乱码 | 选择英文，或者在 Windows Terminal 中运行脚本。 |

### 启动开发板

| 问题 | 解决方法 |
|---|---|
| 所有指示灯都不亮 | 检查电源开关是否打开，线是否插在 **EXT PWR** 上。换一个确定能提供 9 V、3 A 的电源试试。 |
| **ON** 灯亮，但 PS 灯不亮 | 开发板没有从存储卡启动。检查存储卡是否插到位、BOOT 是否在 **SD**，然后重新写卡，最好换一张卡。 |
| **DONE** 灯不亮，或 LED 没有闪烁 | 系统没有完成启动。请[查看日志](#6-查看开发板日志)，确认停在了哪一步。 |
| 不断重启 | 保存日志交给助教。电源功率不足是常见原因，也请换一个电源试试。 |
| 风扇接口附近的红灯亮起 | 开发板过热。请关闭电源，等它冷却，并确保散热片周围通风。 |

### 连接 Jupyter

| 问题 | 解决方法 |
|---|---|
| 网页打不开 | 等白色 LED 闪烁之后再试。确认线插在 **USB 3.0 DRP I** 而不是 PROG UART，并且不是只能充电的线。也可以尝试关闭 VPN。 |
| 电脑上没有出现新的网络连接 | **Windows：** 打开设备管理器，查看是否有带黄色警告标记的设备。**Ubuntu：** 运行 `ip a`，查看是否有地址为 `192.168.3.x` 的新连接。 |
| 仍然无法连接 | 使用[串口日志](#6-查看开发板日志)，运行 `ip a` 检查是否有 `192.168.3.1`，再运行 `ps -ef \| grep -i jupyter` 检查 Jupyter 是否在运行。 |

### 串口

| 问题 | 解决方法 |
|---|---|
| 没有出现串口 | 线必须插在 **PROG UART** 上，并且必须能传输数据。换一根线和一个 USB 口试试。 |
| **Windows：** 工具提示缺少驱动 | 安装 [FTDI VCP 驱动](https://ftdichip.com/drivers/vcp-drivers/)，然后重新插线。 |
| **Windows：** 提示被其他程序占用 | 关闭 PuTTY、Tera Term、Vitis 串口终端或其他 COMTool 窗口。同一时间只能有一个程序使用串口。 |
| **Ubuntu：** 提示 “Permission denied” | 重新运行工具。如果仍然不行，请注销 Ubuntu 后重新登录。 |
| **Ubuntu：** 开发板已连接，但没有串口 | Ubuntu 的 `brltty` 服务可能会占用串口。如果你不使用盲文显示器，请运行 `sudo apt remove brltty`。 |
| 显示乱码 | 把波特率设为 **115200**。 |
| 点击 OPEN 后没有任何内容 | 按复位键。如果仍然没有内容，检查 BOOT 是否在 **SD**，存储卡是否已插入。 |
| Ubuntu 上 COMTool 无法启动 | 运行 `bash scripts/serial_zu3.sh --cli` 改用终端。退出时先按 `Ctrl+A`，再按 `Ctrl+X`。 |

还是解决不了？请联系助教并附上 `logs` 文件夹中的日志，也可以在 [PYNQ 论坛](https://discuss.pynq.io)上搜索。

## 脚本选项

大多数人不需要用到这些选项。

| `flash_zu3.sh`（Ubuntu） | `flash_zu3.bat`（Windows） | 作用 |
|---|---|---|
| `--variant 4gb` 或 `8gb` | `-Variant 4gb` 或 `8gb` | 跳过开发板型号的提问 |
| `--device /dev/sdX` | `-DiskNumber N` | 跳过存储卡列表（安全检查和 `ERASE` 确认仍然有效） |
| `--zip FILE` | `-Zip FILE` | 使用已下载好的镜像，例如实验室 U 盘里的文件 |
| `--no-verify` | `-NoVerify` | 跳过回读校验。速度更快，但无法发现坏卡 |
| `--allow-large` | `-AllowLarge` | 允许选择超过 256 GB 的磁盘。默认会拒绝，以保护移动硬盘 |
| `--lang en` 或 `zh` | `-Lang en` 或 `zh` | 跳过语言选择 |

`serial_zu3` 还支持 `--baud RATE`（Ubuntu）或 `-Baud RATE`（Windows），以及上面的语言选项。

## 关于镜像和工具

- **镜像：** AUP-ZU3 PYNQ **v3.1.1**，来自 [pynq.io](https://www.pynq.io/)。2026 年 11 月时，这块板子的 v4.0 还标注为 “coming soon”（即将推出），所以脚本使用 v3.1.1。
- **校验和：** AMD 没有公布这些文件的校验和。下面的值是 2026 年 11 月 3 日从 AMD 下载服务器计算得到的，脚本会用它们进行校验。

  | 文件 | SHA-256 |
  |---|---|
  | `AUP-ZU3-3.1.1-4gb.zip` | `b21dd5daab6c835cfc43140180a5a267ac2b43697b51d3a02b9f6288e77ca3fb` |
  | `AUP-ZU3-3.1.1-8gb.zip` | `c995d48a1184452be1b18faaf492e8b46100cd29afa100cb83cf670662648b9f` |

- **COMTool：** [Neutree/COMTool](https://github.com/Neutree/COMTool) v3.4.1，采用 LGPL-3.0 许可证。它会在首次运行工具时从官方发布页下载，不包含在本仓库中。
- **更多开发板资料：** [AUP-ZU3 网站](https://xilinx.github.io/AUP-ZU3/)，以及提供参考手册和原理图的 [Real Digital 产品页](https://www.realdigital.org/hardware/aup-zu3)。
