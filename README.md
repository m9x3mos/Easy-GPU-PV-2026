# Easy-GPU-PV
A work-in-progress project dedicated to making GPU Paravirtualization on Windows Hyper-V easier!  

GPU-PV allows you to partition your systems dedicated or integrated GPU and assign it to several Hyper-V VMs.  It's the same technology that is used in WSL2, and Windows Sandbox.  

Easy-GPU-PV aims to make this easier by automating the steps required to get a GPU-PV VM up and running.  
Easy-GPU-PV does the following...  
1) Creates a VM of your choosing
2) Automatically Installs Windows to the VM
3) Partitions your GPU of choice and copies the required driver files to the VM
4) Runs a two-phase debloat (before the first logon and again at the first logon) that removes bloatware, blocks OneDrive/Outlook/Copilot, left-aligns the taskbar, and applies the dark theme  

After that, you should install a GPU accelerated remote desktop app / game streaming app as well as a virtual display driver to get the most out of the VM. Check the Issues tab on this repo to get recommendations.


### Prerequisites:
* Windows 10 20H1+ Pro, Enterprise or Education OR Windows 11 Pro, Enterprise or Education.  Windows 11 on host and VM is preferred due to better compatibility.  
* Matched Windows versions between the host and VM. Mismatches may cause compatibility issues, blue-screens, or other issues. (Win10 21H1 + Win10 21H1, or Win11 21H2 + Win11 21H2, for example)  
* Desktop Computer with dedicated NVIDIA/AMD GPU or Integrated Intel GPU - Laptops with NVIDIA GPUs are not supported at this time, but Intel integrated GPUs work on laptops.  GPU must support hardware video encoding (NVIDIA NVENC, Intel Quicksync or AMD AMF).  
* Latest GPU driver from Intel.com or NVIDIA.com, don't rely on Device manager or Windows update.  
* Latest Windows 10 ISO [downloaded from here](https://www.microsoft.com/en-gb/software-download/windows10ISO) / Windows 11 ISO [downloaded from here.](https://www.microsoft.com/en-us/software-download/windows11) - Do not use Media Creation Tool, if no direct ISO link is available, follow [this guide.](https://www.nextofwindows.com/downloading-windows-10-iso-images-using-rufus)
* Virtualisation enabled in the motherboard and [Hyper-V fully enabled](https://docs.microsoft.com/en-us/virtualization/hyper-v-on-windows/quick-start/enable-hyper-v) on the Windows 10/ 11 OS (requires reboot).  
* Allow Powershell scripts to run on your system - typically by running "Set-ExecutionPolicy unrestricted" in Powershell running as Administrator.  

### Instructions
1. Make sure your system meets the prerequisites.
2. [Download the Repo and extract.](https://github.com/jamesstringerparsec/Easy-GPU-PV/archive/refs/heads/main.zip)
3. Search your system for Powershell ISE and run as Administrator.
4. In the extracted folder you downloaded, open PreChecks.ps1 in Powershell ISE.  Run the files from within the extracted folder. Do not move them.
5. Open and Run PreChecks.ps1 in Powershell ISE using the green play button and copy the GPU Listed (or the warnings that you need to fix).
6. Open CopyFilesToVM.ps1 Powershell ISE and edit the params section at the top of the file, you need to be careful about how much ram, storage and hard drive you give it as your system needs to have that available.  On Windows 10 the GPUName must be left as "AUTO", In Windows 11 it can be either "AUTO" or the specific name of the GPU you want to partition exactly how it appears in PreChecks.ps1.  Additionally, you need to provide the path to the Windows 10/11 ISO file you downloaded.
7. Run CopyFilesToVM.ps1 with your changes to the params section - this may take 5-10 minutes.
8. Download a GPU based remote desktop / game streaming tool as well as a virtual display adapter driver (not included) to take full advantage of the GPU accelerated desktop.  The issues tab of this repo has lots of good ideas and advice about how to get the best out of your new VM.
9. You should be good to go!

### Latest updates

- `Update-VMGpuPartitionDriver.ps1` now handles Windows 11 24H2 hosts where a mounted VM disk has no drive letter: it tries to assign one, stops safely if that fails, and checks whether driver files were copied.
- `Add-VMGpuPartitionAdapterFiles.psm1` validates the destination drive letter before copying and reports driver-copy progress.
- The parameter values in `CopyFilesToVM.ps1` are machine-specific; review and set the VM name, ISO path, storage, memory, CPU, and GPU values for your own host before running it.
- `Fix-VMGpuPartitionAllocation.ps1` is available for VMs with GPU-PV allocation problems (for example, GPU workloads crashing during startup). See below before running it: it may forcibly stop a running VM.
- Optional WOL and suspend listeners can wake a VM from the LAN and suspend/save it when a remote gaming session ends. Setup instructions follow.
- The debloat (bundled app removal, Windows capability and optional-feature removal such as Recall, Fax, WordPad, and Media Player, OneDrive/Outlook/Copilot blocking, dark theme, and taskbar/Start layout) runs in two phases: a lightweight pre-first-logon pass during the Windows Setup specialize pass, and the heavy removal as a one-time elevated task at the VM's first logon. See the "One-time debloat" section below.
- `autounattend.xml` keeps the standard unattended configuration (regional settings, autologon, the GPU-P account, en-US and dark-theme base settings) and runs the pre-first-logon debloat during the specialize pass. The heavy capability and optional-feature removal still runs from the first-logon task.
- AMD OpenGL and Vulkan driver packages (`amdogl.inf_amd64*` and `amdvlk.inf_amd64*`) are now automatically copied into the VM's `HostDriverStore\FileRepository`, improving OpenGL and Vulkan game support on AMD GPUs.

### One-time debloat

Building a VM automatically runs the debloat in two phases. You do not need to trigger it yourself; it finishes with a single reboot.

**Phase 1 - before the first logon (`specialize` pass).** `autounattend.xml` runs `Debloater\PreFirstLogon.ps1` before the GPUVM profile exists. It removes the OneDrive setup binaries and shortcuts, removes the provisioned OneDrive, Copilot, and bundled app packages, applies machine policies that block OneDrive and Copilot, applies the default-profile settings, and sets the Start pins. This keeps those apps from ever installing into the new profile.

**Phase 2 - at the first logon.** The Group Policy logon script (`User\Install.ps1`) registers and starts an elevated, interactive scheduled task named `EasyGPU Debloat`. That task runs `Debloater\Run-Debloater.ps1`, which:

- Removes the bundled Windows Store bloatware apps (`Debloater\RemovePackages.ps1`). This includes News, Weather, Teams, To Do, Outlook, Phone Link, Solitaire, WhatsApp, Office (Microsoft 365 hub) and its helper packages, LinkedIn, Adobe Express, Mail and Calendar, Family, Clipchamp, the Windows Web Experience Pack (Widgets), OneDrive, and Copilot. The Xbox app is intentionally kept so it can still be installed from the Microsoft Store.
- Removes Windows capabilities and optional features, including the Recall preview, Fax, WordPad, and Media Player (`Debloater\RemoveCapabilities.ps1`, `Debloater\RemoveFeatures.ps1`).
- Applies machine policies that block OneDrive, Outlook, and Copilot setup, disable widgets (`AllowNewsAndInterests`), and harden Edge and RDP (`Debloater\Specialize.ps1`).
- Loads the default-profile hive (`C:\Users\Default\NTUSER.DAT`), applies the taskbar/Start layout settings, hides the Widgets taskbar button, switches the Start **All apps** view to the list layout, and unloads it (`Debloater\DefaultUser.ps1`).
- Removes the current user's Copilot, OneDrive, and bundled app packages (including the Windows Web Experience Pack), left-aligns the taskbar, clears all taskbar pins, hides the Widgets button, sets the Start **All apps** view to list, applies the dark theme, and restarts Explorer (`Debloater\UserOnce.ps1`, `Debloater\SetColorTheme.ps1`). The Start menu is pinned to Edge, File Explorer, and the Microsoft Store (`Debloater\SetStartPins.ps1`).
- Runs `Debloater\Test-Debloat.ps1` and logs PASS/FAIL for each check.
- Writes the completion flag and performs the one-time reboot.

How it works:

- The scripts live in `Debloater\`. At build time, `Setup-Install` (in `CopyFilesToVM.ps1`) copies them into the VHD: the script set goes to `C:\Windows\Setup\Scripts\` and the orchestrator to `C:\ProgramData\Easy-GPU-P\`.
- The pre-first-logon phase writes `C:\ProgramData\Easy-GPU-P\pre-first-logon.flag` so the first-logon log shows it ran.
- A completion flag (`C:\ProgramData\Easy-GPU-P\debloat-complete.flag`) is written before the reboot, so the debloat never runs a second time (no reboot loop).

If the debloat does not appear to have run, check that the `EasyGPU Debloat` task exists under **Task Scheduler** in the VM, then review these logs in the VM:

- `C:\Windows\Setup\Scripts\PreFirstLogon.log`
- `C:\Windows\Setup\Scripts\debloat.log`
- `C:\Windows\Setup\Scripts\Specialize.log`
- `C:\Windows\Setup\Scripts\DefaultUser.log`
- `C:\Windows\Setup\Scripts\UserOnce.log`
- `C:\Windows\Setup\Scripts\Test-Debloat.log`

To re-run the checks by hand, run `C:\Windows\Setup\Scripts\Test-Debloat.ps1` in an elevated PowerShell inside the VM. To re-run the whole chain, delete `C:\ProgramData\Easy-GPU-P\debloat-complete.flag` first.

### Fixing GPU partition allocation

If a VM has GPU-PV allocation problems, run this from an elevated PowerShell on the Hyper-V host, from the extracted repository folder:

```powershell
.\Fix-VMGpuPartitionAllocation.ps1 -VMName "YourVMName"
```

The VM must be off while its allocation is changed. If it is running, the script force-stops it and starts it again after applying the fix; save any guest work first. A VM that was already off remains off unless you add `-StartAfter`. The script also disables VM checkpoints, which are incompatible with GPU-PV.

### Optional: Wake-on-LAN and automatic suspend

The scripts in `WOL listener` run on the Hyper-V host. The WOL listener receives standard magic packets on UDP ports 7 and 9, matches the packet's target MAC address to a VM network adapter, and starts an Off or Saved VM (or resumes a Paused VM). The suspend listener accepts a request from a script in the guest and suspends or saves the configured VM.

#### Install the host listeners

1. Keep the extracted repository in a permanent local folder on the host. The scheduled tasks run as `SYSTEM` at startup, so do not put the scripts in a location that account cannot read.
2. Open **Windows PowerShell as Administrator** and change to the listener folder:

   ```powershell
   Set-Location "C:\path\to\Easy-GPU-PV\WOL listener"
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   ```

   The execution-policy change applies only to this PowerShell window.
3. If you want WOL, install its inbound firewall rule:

   ```powershell
   .\open_firewall_rule.ps1
   ```

4. To enable automatic suspend as well, first configure the shared secret and VM in `suspend-listener.ps1` (see below), then install its firewall rule:

   ```powershell
   .\open_firewall_rule_suspend_listener.ps1
   ```

   TCP port 5900 is used by default. Keep it limited to a trusted LAN; do not port-forward it to the internet.
5. Register both startup tasks:

   ```powershell
   .\register_scheduledtask.ps1
   ```

   This creates `HyperV-WOL-Listener` and `HyperV-Suspend-Listener`, which run as `SYSTEM` at startup. The task script now resolves listener paths relative to its own location, so the repository does not need to be installed at a particular path. Restart the host, or start the tasks from **Task Scheduler** to begin listening.

#### Send a wake packet

Find the VM adapter's MAC address on the host:

```powershell
Get-VMNetworkAdapter -VMName "YourVMName" | Select-Object VMName, Name, MacAddress
```

Configure your WOL app/device to send a standard magic packet to that MAC address on the host's LAN, using UDP port 7 or 9. The listener checks the virtual NIC MAC addresses of all VMs, so the packet can wake a matching VM even though that VM is off. Check `WOL listener\wol-listener.log` on the host if it does not wake.

#### Suspend the VM when a Sunshine session ends (optional)

1. On the host, edit the parameters near the top of `suspend-listener.ps1`: set `VMName` to the guest VM, choose a long, unique `Secret` instead of the default `changeme-shared-secret`, and select `Mode` as `Suspend` or `Save`. The default port is 5900.
2. Copy `suspend-trigger.ps1` into the guest. Edit its `HostIP` to the Hyper-V host's LAN IP and set `Secret` to exactly the same value as on the host. Keep the port the same on both scripts.
3. In Sunshine's application configuration, set this guest-side script to run as an **undo** prep command when the session disconnects. The guest script sends the request; the host listener performs the Hyper-V suspend/save operation.
4. Restart the `HyperV-Suspend-Listener` task (or restart the host) after changing the host listener parameters. Review `WOL listener\suspend-listener.log` on the host if requests are not handled.

The suspend listener uses a plain-text shared secret over TCP, not encrypted authentication. Use a unique secret and a trusted private network only. The firewall rule opens the selected port for inbound connections; restrict its scope in Windows Firewall if your network requires it.

### Upgrading GPU Drivers when you update the host GPU Drivers
It's important to update the VM GPU Drivers after you have updated the Host GPUs drivers. You can do this by...  
1. Reboot the host after updating GPU Drivers.  
2. Open Powershell as administrator and change directory (CD) to the path that CopyFilesToVM.ps1 and Update-VMGpuPartitionDriver.ps1 are located. 
3. Run ```Update-VMGpuPartitionDriver.ps1 -VMName "Name of your VM" -GPUName "Name of your GPU"```    (Windows 10 GPU name must be "AUTO")

### Values
  ```VMName = "GPUP"``` - Name of VM in Hyper-V and the computername / hostname  
  ```SourcePath = "C:\Users\james\Downloads\Win11_English_x64.iso"``` - path to Windows 10/ 11 ISO on your host   
  ```Edition    = 6``` - Leave as 6, this means Windows 10/11 Pro  
  ```VhdFormat  = "VHDX"``` - Leave this value alone  
  ```DiskLayout = "UEFI"``` - Leave this value alone  
  ```SizeBytes  = 40gb``` - Disk size, in this case 40GB, the minimum is 20GB  
  ```MemoryAmount = 8GB``` - Memory size, in this case 8GB  
  ```CPUCores = 4``` - CPU Cores you want to give VM, in this case 4   
  ```NetworkSwitch = "Default Switch"``` - Leave this alone unless you're not using the default Hyper-V Switch  
  ```VHDPath = "C:\Users\Public\Documents\Hyper-V\Virtual Hard Disks\"``` - Path to the folder you want the VM Disk to be stored in, it must already exist  
  ```UnattendPath = "$PSScriptRoot"+"\autounattend.xml"``` -Leave this value alone  
  ```GPUName = "AUTO"``` - AUTO selects the first available GPU. On Windows 11 you may also use the exact name of the GPU you want to share with the VM in multi GPU situations (GPU selection is not available in Windows 10 and must be set to AUTO)    
  ```GPUResourceAllocationPercentage = 50``` - Percentage of the GPU you want to share with the VM   
  ```Username = "GPUVM"``` - The VM Windows Username, do not include special characters, and must be different from the "VMName" value you set  
  ```Password = "CoolestPassword!"``` - The VM Windows Password, cannot be blank    
  ```Autologon = "true"```- If you want the VM to automatically login to the Windows Desktop


### Thanks to:  
- [mjarvisal](https://github.com/mjarvisal/Easy-GPU-PV_WOL) for the Wake-on-LAN and auto-suspend listener work used in the `WOL listener` folder.
- [Hyper-ConvertImage](https://github.com/tabs-not-spaces/Hyper-ConvertImage) for creating an updated version of [Convert-WindowsImage](https://github.com/MicrosoftDocs/Virtualization-Documentation/tree/master/hyperv-tools/Convert-WindowsImage) that is compatible with Windows 10 and 11.
- [gawainXX](https://github.com/gawainXX) for help testing and pointing out bugs and feature improvements.  


### Notes:    
- Always use a GPU accelerated remote desktop / game streaming app to connect to the VM.  Keep the Microsft Hyper-V Video adapter disabled. Using RDP and Hyper-V Enhanced Session mode will result in broken behaviour and black screens in your GPU accelerated remote desktop.  RDP and the Hyper-V video adapter only offer a maximum of 30FPS. Using GPU accelerated remote desktops + a virtual display driver will allow you to use up to 4k60 FPS.
- If you get "ERROR  : Cannot bind argument to parameter 'Path' because it is null." this probably means you used Media Creation Tool to download the ISO.  You unfortunately cannot use that, if you don't see a direct ISO download link at the Microsoft page, follow [this guide.](https://www.nextofwindows.com/downloading-windows-10-iso-images-using-rufus)  
- Your GPU on the host will have a Microsoft driver in device manager, rather than an nvidia/intel/amd driver. As long as it doesn't have a yellow triangle over top of the device in device manager, it's working correctly.  
- A powered on display / HDMI dummy dongle must be plugged into the GPU to allow your GPU accelerated remote desktop / game streaming app to capture the screen.  You only need one of these per host machine regardless of number of VM's.
- AMD OpenGL and Vulkan driver packages are now automatically copied into the VM, so OpenGL and Vulkan titles are more likely to run on AMD GPUs. On other GPUs the Vulkan renderer may still be unavailable and GL games may or may not work; [this](https://www.microsoft.com/en-us/p/opencl-and-opengl-compatibility-pack/9nqpsl29bfff?SilentAuth=1&wa=wsignin1.0#activetab=pivot:overviewtab) OpenCL/OpenGL compatibility pack may help with some OpenGL apps.  
- If you do not have administrator permissions on the machine it means you set the username and vmname to the same thing, these needs to be different.  
- AMD Polaris GPUS like the RX 580 do not support hardware video encoding via GPU Paravirtualization at this time.  
- To download Windows ISOs with Rufus, it must have "Check for updates" enabled.
