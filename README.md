# LFCS Local Lab

A local simulation environment to prepare for the LFCS exam. The exercise instructions and a Linux terminal run side by side in your browser. Each exercise gets its own Ubuntu VM with the required starting state. After you finish, the lab checks the VM's actual system state and reports whether the task passed.

## Prerequisites

- Windows with the Multipass HCS driver enabled
- [Multipass](https://canonical.com/multipass) version 1.17 or later
- [Node.js](https://nodejs.org/) for the local web server
- Internet access during initial VM setup to download Ubuntu and required packages
- Enough free disk space for five base VMs and temporary exercise VMs

The base VMs run Ubuntu 22.04. Multipass must use the HCS driver; the setup script enables it if needed:

```powershell
& 'C:\Program Files\Multipass\bin\multipass.exe' get local.driver
```

## Quickstart

Open PowerShell in the project directory:

```powershell
cd C:\Users\chris\Desktop\LFCS\LAB
```

1. Prepare the base VMs. Run this once before the first use; it may take a few minutes:

   ```powershell
   .\prepare-vms.ps1
   ```

2. Start the web app:

   ```powershell
   .\start.ps1
   ```

3. Open the lab in your browser:

   [http://localhost:8765](http://localhost:8765)

## Usage

1. Select an exercise. Its instructions appear on the left.
2. Click **Start / Reset** to create the exercise VM with the correct starting state. Exercises involving multiple servers start all required VMs.
3. Work in the terminal on the right. Multi-line commands and here-documents are supported. Full-screen terminal editors such as `vim` are not supported in this browser terminal.
4. Click **Check Solution**. The grader checks the configuration and system state inside the VM.
5. Click **Start / Reset** again at any time to restore the exercise to its original state.

### Management

```powershell
.\stop.ps1        # Stop the web server and exercise VMs
.\reset-labs.ps1  # Delete exercise VMs; keep the base VMs
```

The base VMs are `lfcs-terminal`, `data-001`, `data-002`, `app-srv1`, and `web-srv1`. Exercise VMs are created as separate clones when needed. Exercises involving multiple servers use an isolated network between their VMs.
# Ace-LFCS
