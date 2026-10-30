# Dawgs SS Tool

Dawgs SS Tool is a Windows PowerShell GUI for an offline, read-only review of
Minecraft mod JARs.

## Run it directly from GitHub

After the files have been pushed, this Command Prompt one-liner downloads and
opens the GUI from the public repository:

```cmd
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -Command "$scriptText = Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/NotADawg/DawgsSSTool/main/DawgsSSTool.ps1'; & ([scriptblock]::Create($scriptText))"
```

It uses the default `.minecraft\mods` folder. The GUI's Browse button lets you
select another folder.

## Run it as `dawgs-ss`

The `dawgs-ss.cmd` launcher fetches the latest script from GitHub each time. Put
the `.cmd` file in a folder on your user `Path`, then open a new Command Prompt:

```cmd
dawgs-ss "%APPDATA%\.minecraft\mods"
```

The folder argument is optional; the GUI starts with the default
`.minecraft\mods` folder. Use **Browse…**, **Scan folder**, and **Export CSV…**
in the window. Selecting a row shows the mod's SHA-256, size, full path, scan
status, and exact JAR entries where indicators appeared.

For example, clone this repository to `%LOCALAPPDATA%\Programs\DawgsSSTool`,
then add that folder to your user `Path` in Windows **Environment Variables**.
Open a new Command Prompt afterward.

## Publish this copy to GitHub

Create an empty GitHub repository named `DawgsSSTool` (do not pre-create a
README). This local folder already has its initial Git commit. From this folder,
replace `YOUR-USERNAME` and run:

```powershell
git remote add origin https://github.com/YOUR-USERNAME/DawgsSSTool.git
git push -u origin main
```

After publishing, clone the repository to the desired install folder and add
that folder to user `Path` as described above.

## How scanning works

The GUI checks top-level `.jar` files in the selected folder. It reads class
files and common metadata inside each JAR without extracting or executing them.
The indicator list is near the top of `DawgsSSTool.ps1` and can be edited.
Results are review leads: legitimate mods or bundled libraries can contain the
same strings, and a clean scan does not prove a mod is safe.

The tool does not inspect running processes, search other launcher folders,
make network requests, upload hashes, delete or quarantine files, or change
Microsoft Defender settings. Nested dependency JARs are not scanned.
