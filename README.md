# AUP-ZU3 PYNQ Setup Guide

**English** | [简体中文](README.zh-CN.md)

This guide takes you from a new AUP-ZU3 board to a running PYNQ system that you can use from your web browser. You don't need any FPGA or Linux experience, and it works on Windows and Ubuntu.

Allow about an hour. Most of that is waiting for downloads and for the card to be written.

**In a hurry?** Do [step 1](#1-check-what-you-have) and [step 2](#2-get-these-files), then run the one-click script for your system:

| | Write the card | See the board's log |
|---|---|---|
| **Windows** | Double-click `scripts\flash_zu3.bat` | Double-click `scripts\serial_zu3.bat` |
| **Ubuntu** | `bash scripts/flash_zu3.sh` | `bash scripts/serial_zu3.sh` |

## Words you'll see

| Word | Meaning |
|---|---|
| **PYNQ** | A system from AMD that lets you control the FPGA from Python. |
| **Image** | A single file containing a complete operating system, ready to copy onto a card. |
| **Flashing** | Copying an image onto a card, byte for byte. It erases everything already on the card. |
| **Serial port (UART)** | A simple text connection to the board. It shows messages even when nothing else is working, so it's the main tool for finding out why a board won't start. |
| **Jupyter** | The web page you use to write and run Python on the board. |

## 1. Check what you have

| You need | Details |
|---|---|
| AUP-ZU3 board | Find the **4G** or **8G** mark next to the memory chips. You'll need to know which one you have. |
| microSD card | **16 GB or larger**, from a known brand. Everything on it will be erased. |
| SD card reader | Your computer's built-in slot, or a USB reader. |
| USB-C power supply | Must support USB Power Delivery at **9 V, 3 A**. A normal phone charger or computer USB port often can't provide this. |
| USB-C cable × 2 or 3 | One for power, one for Jupyter, and one for the serial log (optional, but needed for debugging). They must carry data: some charging-only cables don't. |
| Computer | Windows 10 or 11, or Ubuntu 22.04 or 24.04, with at least 3 GB of free disk space. |

## 2. Get these files

1. At the top of this repository's GitHub page, click the green **Code** button, then **Download ZIP**.
2. Unzip it:
   - **Windows:** right-click the ZIP file, then choose **Extract All**. The scripts won't work if you run them from inside the ZIP without extracting it first.
   - **Ubuntu:** right-click the ZIP file, then choose **Extract Here**.

If you already use git, `git clone https://github.com/CNStanLee/4C1_lab_ref.git` works too.

## 3. Write the image to the card

Put the microSD card in your computer. Then choose **option A** (recommended) or **option B**.

> [!WARNING]
> This permanently erases the disk you choose. Back up anything on the card first, and unplug any other USB drives so you can't pick the wrong one.

### Option A: one-click script

The script does everything: it downloads the correct image, checks it, writes the card, and reads the card back to confirm that it was written correctly.

**On Windows:**

1. Open the `scripts` folder and double-click **`flash_zu3.bat`**.
2. If a blue "Windows protected your PC" box appears, click **More info**, then **Run anyway**.
3. When Windows asks whether to let the app make changes, click **Yes**. A new window opens.

**On Ubuntu:**

1. Open the folder you unzipped, right-click an empty area, and choose **Open in Terminal**.
2. Type this command and press Enter:

   ```bash
   bash scripts/flash_zu3.sh
   ```

3. If it asks for a password, type your Ubuntu login password and press Enter. Nothing appears on screen as you type, which is normal.

**On both systems,** the script then asks you four things:

```text
Language / 语言: [1] English (default)  [2] 中文 : 1

==== Step 1 of 4: choose your board ====
Look at your board: next to the memory chips it is marked "4G" or "8G".
Which one is printed on your board? [4/8]: 8

==== Step 2 of 4: choose your card ====
These disks look like SD cards:
  [1] /dev/sdb  32GB  Generic SD Reader
Number of your card (Enter to look again): 1

EVERYTHING on this disk will be permanently erased:
  /dev/sdb  32GB  Generic SD Reader
Type ERASE to continue: ERASE
```

Check that the size matches your card before you type `ERASE`. Windows shows a disk number instead of `/dev/sdb`.

After that you can walk away. It typically takes 15 to 45 minutes in total, depending on your network and card. Wait until you see **Done**.

> [!IMPORTANT]
> **Windows only:** Windows can't read one of the card's partitions, so it may say **"You need to format the disk"**. Always click **Cancel**. Formatting would destroy the image.

If the download is interrupted, just run the script again. It carries on from where it stopped.

### Option B: do it by hand with balenaEtcher

Use this if the script doesn't work on your computer.

1. Download the image for your board. Each file is about 2.2 GB, and you don't need to unzip it.

   | Board mark | Download |
   |---|---|
   | 4G | [AUP-ZU3-3.1.1-4gb.zip](https://download.amd.com/opendownload/pynq/AUP-ZU3-3.1.1-4gb.zip) |
   | 8G | [AUP-ZU3-3.1.1-8gb.zip](https://download.amd.com/opendownload/pynq/AUP-ZU3-3.1.1-8gb.zip) |

2. Install [balenaEtcher](https://etcher.balena.io/) and open it.
3. Click **Flash from file** and choose the ZIP file you downloaded.
4. Click **Select target** and choose your card. Check the size carefully.
5. Click **Flash!** and wait until it finishes and validates the card.

## 4. Boot the board

![AUP-ZU3 setup: BOOT switch set to SD, microSD card inserted, USB-C data cable in USB 3.0 DRP I, USB-C power in EXT PWR](https://xilinx.github.io/AUP-ZU3/images/aup_zu3_setup.png)

*Image: AMD, from the [AUP-ZU3 getting started guide](https://xilinx.github.io/AUP-ZU3/getting_started.html).*

With the power switch **off**, follow the numbers in the picture:

1. Slide the **BOOT** switch to **SD**.
2. Push the microSD card into the slot, with the card's metal contacts facing the board.
3. Connect a USB-C cable from your computer to the port marked **USB 3.0 DRP I**.
4. Connect the USB-C power supply to the port marked **EXT PWR**.

Now turn the power switch **on** and watch the lights:

| Time | What you should see | What it means |
|---|---|---|
| Right away | The **ON** light, plus two **PS** lights, one of them flashing like a heartbeat | The board has power and has started to boot |
| 30 to 60 seconds | The **DONE** light comes on | The FPGA has been configured |
| A few seconds later | The 8 white LEDs flash and the 4 colour LEDs change colour | **The board is ready** |

If you don't see this, go to [step 6](#6-see-the-boards-log) or [Troubleshooting](#troubleshooting).

## 5. Open Jupyter

The USB cable from step 4 acts as a small network between your computer and the board. It should connect by itself, with your computer receiving an address automatically.

1. Open a web browser and go to **<http://192.168.3.1/lab>**.
2. When it asks for a password, type **`xilinx`**.

You should now see JupyterLab, with example notebooks in the file list on the left. **Your board is working.** 🎉

If the page doesn't load, also try <http://192.168.3.1:9090/lab>.

**Before you switch the board off,** open a terminal in Jupyter and run `sudo poweroff`, then wait about 10 seconds. Cutting the power while Linux is running can damage the files on the card.

## 6. See the board's log

The board prints messages through its serial port from the moment it starts. If anything goes wrong, this log usually tells you why, and it's what a TA will want to see. The `serial_zu3` tool finds the right port, sorts out the permissions, and opens it in [COMTool](https://github.com/Neutree/COMTool), a free serial terminal. COMTool downloads automatically the first time.

1. Connect a USB-C cable from your computer to the port marked **PROG UART**, and turn the board on.
2. Start the tool:
   - **Windows:** double-click **`scripts\serial_zu3.bat`**.
   - **Ubuntu:** run `bash scripts/serial_zu3.sh`. The first time, it may ask for your password so that it can give you access to the port.
3. In COMTool, check that **Port** shows the port the tool found, then click **OPEN**.
4. Press the board's **reset button** to restart it. The whole log now scrolls past from the very beginning.

The settings are 115200 baud, 8 data bits, no parity, 1 stop bit, and the tool fills these in for you. Each session is saved automatically to a timestamped file in the `logs` folder, so you can send it to a TA.

### Reading the log

The board starts in stages. The last stage you can see tells you roughly where the problem is:

| Stage | What to look for | If it stops here |
|---|---|---|
| Nothing at all | No text after reset | Check that the BOOT switch is on **SD** and the card is inserted. If you've done that, write the card again. |
| First-stage boot | `Xilinx Zynq MP First Stage Boot Loader` | The card may be faulty. Write it again, ideally on a different card. |
| U-Boot | `U-Boot` | The boot files or the card may be bad. Write the card again. Also check that you chose the image matching your board's 4G or 8G mark. |
| Linux | `Starting kernel`, then many lines of messages | Note the last few lines and any `error` or `panic`, and save the log for a TA. |
| Finished | A login prompt or a command prompt such as `root@pynq:~#` | The system has started. If asked, the username and password are both `xilinx`. |

To run a command, type it in COMTool's send box at the bottom and click **Send**. For example, `ip a` shows the board's network addresses, and `192.168.3.1` should be among them.

### Other ways to use the tool

| Task | Windows (in PowerShell, from the repository folder) | Ubuntu |
|---|---|---|
| Just list the ports | `.\scripts\serial_zu3.bat -List` | `bash scripts/serial_zu3.sh --list` |
| Choose the port yourself | `.\scripts\serial_zu3.bat -Port COM5` | `bash scripts/serial_zu3.sh --port /dev/ttyUSB1` |
| Use the terminal instead of COMTool | Not available | `bash scripts/serial_zu3.sh --cli` |

## Troubleshooting

### Writing the card

| Problem | What to do |
|---|---|
| The script doesn't list my card | Take the card out and put it back, then press Enter to look again. Try a different USB port or reader. |
| "read-only" | Some card adapters have a small lock switch on the side. Slide it away from **LOCK**. |
| "The card does not match the image" | The card is faulty or fake, showing more capacity than it really has. Use a different card from a known brand. |
| "Writing failed" on Windows | Close File Explorer windows and other programs that might be using the card, then try again. Antivirus software can also block it. If it keeps failing, use [option B](#option-b-do-it-by-hand-with-balenaetcher). |
| The download keeps failing or the file is "damaged" | Move to a more reliable network and run the script again. If it still fails, AMD may have replaced the file, so use [option B](#option-b-do-it-by-hand-with-balenaetcher) and tell your TA. |
| Windows says the disk needs formatting | Click **Cancel**. This is normal. |
| Chinese text looks garbled in the window | Choose English, or run the script from Windows Terminal. |

### Starting the board

| Problem | What to do |
|---|---|
| No lights at all | Check that the power switch is on and the cable is in **EXT PWR**. Try a power supply that definitely provides 9 V at 3 A. |
| The **ON** light is on, but the PS lights aren't | The board isn't starting from the card. Check the card is fully inserted and BOOT is on **SD**, then write the card again, ideally on a different card. |
| No **DONE** light or LED flashes | The system didn't finish starting. [Read the log](#6-see-the-boards-log) to see where it stopped. |
| It keeps restarting | Save the log for a TA. A weak power supply is a common cause, so also try a different one. |
| A red light near the fan connector | The board is too hot. Turn it off, let it cool, and make sure air can reach the heatsink. |

### Connecting to Jupyter

| Problem | What to do |
|---|---|
| The page won't load | Wait until the white LEDs have flashed. Check that the cable is in **USB 3.0 DRP I**, not PROG UART, and that it isn't a charge-only cable. Try turning off any VPN. |
| No new network connection on my computer | **Windows:** open Device Manager and look for a device with a yellow warning mark. **Ubuntu:** run `ip a` and look for a new connection with a `192.168.3.x` address. |
| Still not working | Use the [serial log](#6-see-the-boards-log), run `ip a` to check for `192.168.3.1`, and run `ps -ef \| grep -i jupyter` to check that Jupyter is running. |

### Serial port

| Problem | What to do |
|---|---|
| No port appears | The cable must be in **PROG UART**, and it must carry data. Try another cable and USB port. |
| **Windows:** the tool says the driver is missing | Install the [FTDI VCP driver](https://ftdichip.com/drivers/vcp-drivers/), then plug the cable in again. |
| **Windows:** "in use by another program" | Close PuTTY, Tera Term, the Vitis serial terminal, or any other COMTool window. Only one program can use the port at a time. |
| **Ubuntu:** "Permission denied" | Run the tool again. If that doesn't fix it, log out of Ubuntu and back in. |
| **Ubuntu:** no port, but the board is connected | Ubuntu's `brltty` service can take over serial ports. If you don't use a braille display, run `sudo apt remove brltty`. |
| The text is garbled | Set the baud rate to **115200**. |
| Nothing appears after clicking OPEN | Press the reset button. If there's still nothing, check that BOOT is on **SD** and the card is inserted. |
| COMTool won't start on Ubuntu | Run `bash scripts/serial_zu3.sh --cli` to use the terminal instead. To quit it, press `Ctrl+A`, then `Ctrl+X`. |

Still stuck? Ask your TA and include the log from the `logs` folder. You can also search the [PYNQ forum](https://discuss.pynq.io).

## Script options

Most people won't need these.

| `flash_zu3.sh` (Ubuntu) | `flash_zu3.bat` (Windows) | What it does |
|---|---|---|
| `--variant 4gb` or `8gb` | `-Variant 4gb` or `8gb` | Skip the board question |
| `--device /dev/sdX` | `-DiskNumber N` | Skip the card list (safety checks and the `ERASE` confirmation still apply) |
| `--zip FILE` | `-Zip FILE` | Use an image you've already downloaded, such as one from a USB stick in the lab |
| `--no-verify` | `-NoVerify` | Skip reading the card back. It's faster, but won't detect a bad card |
| `--allow-large` | `-AllowLarge` | Allow disks over 256 GB, which are refused by default to protect external drives |
| `--lang en` or `zh` | `-Lang en` or `zh` | Skip the language question |

`serial_zu3` also accepts `--baud RATE` on Ubuntu or `-Baud RATE` on Windows, as well as the language option.

## About the image and tools

- **Image:** AUP-ZU3 PYNQ **v3.1.1**, from [pynq.io](https://www.pynq.io/). In November 2026, v4.0 was listed as "coming soon" for this board, so the scripts use v3.1.1.
- **Checksums:** AMD doesn't publish checksums for these files. The values below were calculated from AMD's download server on 3 November 2026, and the scripts check against them.

  | File | SHA-256 |
  |---|---|
  | `AUP-ZU3-3.1.1-4gb.zip` | `b21dd5daab6c835cfc43140180a5a267ac2b43697b51d3a02b9f6288e77ca3fb` |
  | `AUP-ZU3-3.1.1-8gb.zip` | `c995d48a1184452be1b18faaf492e8b46100cd29afa100cb83cf670662648b9f` |

- **COMTool:** [Neutree/COMTool](https://github.com/Neutree/COMTool) v3.4.1, licensed under LGPL-3.0. It's downloaded from its official releases when you first run the tool, and isn't included in this repository.
- **More about the board:** [AUP-ZU3 site](https://xilinx.github.io/AUP-ZU3/) and [Real Digital's board page](https://www.realdigital.org/hardware/aup-zu3), which has the reference manual and schematic.
