# LFCS Local Lab

A local simulation environment to prepare for the LFCS exam. The exercise instructions and a Linux terminal run side by side in your browser. Each exercise gets its own Ubuntu VM with the required starting state. After you finish, the lab checks the VM's actual system state and reports whether the task passed.

## Prerequisites

- Windows with the Multipass HCS driver enabled
- [Multipass](https://canonical.com/multipass) version 1.17 or later
- Docker Desktop with the Linux container engine enabled (used for task 8's Virtio disk devices)
- [Node.js](https://nodejs.org/) for the local web server
- Internet access during initial VM setup to download Ubuntu images and required packages
- Enough free disk space for five base VMs and temporary exercise VMs

The base VMs run Ubuntu 22.04. Multipass must use the HCS driver; the setup script enables it if needed:

```powershell
& 'C:\Program Files\Multipass\bin\multipass.exe' get local.driver
```

## Quickstart

Open PowerShell in the project directory:

1. Clone and cd into the repo

   ```powershell
   git clone https://github.com/FlyingChris1/Ace-LFCS.git
   cd Ace-LFCS
   ```

2. Configure the Multipass service port. Run this once from an **Administrator PowerShell**:

   ```powershell
   .\configure-multipass-port.ps1
   ```

   The script keeps a backup of the previous service command, saves the CLI endpoint system-wide, and refuses to use a port already occupied or reserved by Windows.

3. Prepare the base VMs. Run this once before the first use; it may take a few minutes:

   ```powershell
   .\prepare-vms.ps1
   ```

4. Install the web app dependencies:

   ```powershell
   npm install
   ```

5. Start the web app:

   ```powershell
   .\start.ps1
   ```

6. Open the URL printed by `start.ps1` in your browser. The app uses port 8765 when available and automatically selects another free localhost port if Windows has reserved it.

   Usually this is [http://localhost:8765](http://localhost:8765).

## Usage

1. Select an exercise. Its instructions appear on the left.
2. Click **Start / Reset** to create the exercise VM with the correct starting state. Exercises involving multiple servers start all required VMs.
3. Work in the terminal on the right. It runs an interactive Linux shell inside the exercise VM, with normal terminal input, arrow keys, command history, Tab completion, Ctrl+C, and full-screen programs such as `vim` and `nano`. To move to another server, use `ssh servername` (for example, `ssh data-001`).
4. Click **Check Solution**. The grader checks the configuration and system state inside the VM.
5. Click **Start / Reset** again at any time to restore the exercise to its original state.

### Management

```powershell
.\stop.ps1        # Stop the web server and exercise VMs
.\reset-labs.ps1  # Delete exercise VMs; keep the base VMs
```

The base VMs are `lfcs-terminal`, `data-001`, `data-002`, `app-srv1`, and `web-srv1`. Exercise VMs are created as separate clones when needed. Exercises involving multiple servers use an isolated network between their VMs.

Task 8 runs in a small QEMU VM managed by Docker Desktop. It uses real Virtio block devices (`/dev/vdb` through `/dev/vdf`), so `lsblk`, `fdisk`, `mkfs`, and mount commands show the same device names as the source exercise. The first start builds the local QEMU image and downloads Ubuntu; later starts reuse the image and reset the task VM state.
# Ace-LFCS
