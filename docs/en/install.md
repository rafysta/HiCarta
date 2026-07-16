# Installation

HiCarta is an app that runs on your own computer. No server or account sign-up is required.

On Windows, you can get it running in just the following 3 steps.

## 1. Install R

Open <https://cran.r-project.org> and download and install R for Windows (4.1 or later). Just clicking "Next" through the installer is usually all it takes.

!!! note "RStudio is not required"
    Only base R is needed. It's fine if you also have RStudio installed.

## 2. Download and unzip HiCarta

Open the GitHub page <https://github.com/rafysta/HiCarta>, then click the green **"Code"** button → **"Download ZIP"**.

![](../images/download.png){ width="400" }

Right-click the downloaded ZIP file and choose "Extract All" to unzip it. You can extract it anywhere (somewhere easy to find, like the Desktop, is recommended).

## 3. Double-click `run_windows.bat`

Inside the unzipped folder, double-click **`run_windows.bat`**.

Only on the first launch, the required components (R packages) are installed automatically, which can take a few minutes. Once ready, a browser tab opens automatically and shows HiCarta (the address is `http://127.0.0.1:7788`).

From the second time on, it starts right away. To quit the app, close the black launcher window (Command Prompt).

---

That's it. For how to use HiCarta, see **[Usage](usage.md)**; for what each on-screen item means, see **[Screens & controls](interface.md)**.

If it doesn't start, or if you're on a Mac, or want to install manually, see **[Setup details & troubleshooting](setup-details.md)**.
