param($installPath, $toolsPath, $package, $project)

$ErrorActionPreference = "Stop";

try {
    # Avoid race conditions when multiple instances try to install the Wizard at the same time.
    $mutex = New-Object System.Threading.Mutex($false, "Global\WTL_AppWizInstaller");
    $mutex.WaitOne() | Out-Null;

    # Try to retrieve the Visual Studio version and edition from the DTE object.
    $vsVersion = "";
    $vsEdition = "";
    try {
        $vsVersion = $dte."Version";   # e.g. "10.0", "11.0", "12.0", "14.0", "15.0", "16.0", "17.0"
        $vsEdition = $dte."Edition";   # e.g. "Professional", "Community", "Enterprise", "Desktop Express", etc.
    }
    catch [Exception] {
    }

    # If the above approach fails, try using the DTE2 interface.
    if ($vsVersion -eq "" -or $vsEdition -eq "") {
        try {
            $dte2 = Get-Interface $dte ([EnvDTE80.DTE2]);
            $vsVersion = $dte2."Version";
            $vsEdition = $dte2."Edition";
        }
        catch [Exception] {
        }
    }

    # If we still can't retrieve version info, exit.
    if ($vsVersion -eq "" -or $vsEdition -eq "") {
        echo "install.ps1: Failed to determine the Visual Studio version.";
        exit;
    }

    # Decide which Registry path and sub-folder to use, based on edition (Express vs. others).
    $regPath = ""
    $vszDir  = ""
    $jsParam = ""

    if ($vsEdition.Contains("Express")) {
        # Express/Community might be labeled differently, but historically Express used these settings.
        $regPath = "Microsoft\VCExpress\" + $vsVersion + "\Setup\VC"
        $vszDir  = "vcprojects_WDExpress"
        # For Express, append an "E" to the version, e.g. "/ver:10E"
        $jsParam = "/ver:" + $vsVersion.Substring(0, 2) + "E"
    }
    else {
        # Professional, Community, Enterprise, etc.
        $regPath = "Microsoft\VisualStudio\" + $vsVersion + "\Setup\VC"
        $vszDir  = "vcprojects"
        # E.g. "/ver:10", "/ver:11", "/ver:12", "/ver:14", "/ver:15", "/ver:16", "/ver:17"
        $jsParam = "/ver:" + $vsVersion.Substring(0, 2)
    }
    # Append extra parameter "/copyfiles" to pass to setup.js
    $jsParam += " /copyfiles";

    # Retrieve the VC installation path (ProductDir) from the registry.
    $vcDir = ""
    try {
        $regItem = Get-ItemProperty ("HKLM:Software\" + $regPath);
        $vcDir = $regItem."ProductDir";
    }
    catch [Exception] {
        try {
            $regItem = Get-ItemProperty ("HKLM:Software\Wow6432Node\" + $regPath);
            $vcDir = $regItem."ProductDir";
        }
        catch [Exception] {
        }
    }
    if ($vcDir -eq "") {
        echo "install.ps1: Failed to determine the VC installation path.";
        exit;
    }

    # Check if the WTL AppWizard is already installed by looking for its .vsz file.
    $vszFile = Join-Path $vcDir $vszDir
    $vszFile = Join-Path $vszFile "WTLAppWiz.vsz"
    if (Test-Path $vszFile) {
        echo "install.ps1: The WTL AppWizard is already installed.";
        exit;
    }

    # Determine a user-friendly version title to display in the message box.
    $verTitle = ""
    switch ($vsVersion) {
        "10.0" { $verTitle = "2010" }
        "11.0" { $verTitle = "2012" }
        "12.0" { $verTitle = "2013" }
        "14.0" { $verTitle = "2015" }
        "15.0" { $verTitle = "2017" }
        "16.0" { $verTitle = "2019" }
        "17.0" { $verTitle = "2022" }
        default {
            echo "install.ps1: Unsupported or unrecognized Visual Studio version: $($vsVersion)."
            exit;
        }
    }

    # If the edition contains "Express", append " Express" to the title.
    if ($vsEdition.Contains("Express")) {
        $verTitle += " Express"
    }

    # Use Windows.Forms to show a message box, asking the user whether to install.
    [Void][Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms");
    $ret = [System.Windows.Forms.MessageBox]::Show(
        "WTL AppWizard for Visual Studio " + $verTitle + " is not found.`r`nDo you want to install?",
        "NuGet Package for WTL",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )
    if ($ret -eq 'No') {
        exit;
    }

    # Execute the setup.js script to install the WTL AppWizard for the current VS version.
    Start-Process wscript.exe ("""$toolsPath\AppWiz\setup.js""", $jsParam) -Wait;
}
finally {
    # Release the mutex to allow other instances to proceed.
    $mutex.ReleaseMutex();
    $mutex.Close();
}
