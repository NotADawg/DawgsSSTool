[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string] $Path = "$env:APPDATA\.minecraft\mods"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:Indicators = @(
    'AimAssist', 'AutoClicker', 'AutoCrystal', 'AutoTotem', 'AutoAnchor',
    'TriggerBot', 'SilentAim', 'PingSpoof', 'FakeLag', 'Velocity',
    'ChestSteal', 'Reach', 'KillAura', 'SelfDestruct'
)
$script:FlagGuide = @(
    [PSCustomObject]@{ Flag = 'AimAssist'; Meaning = 'May relate to automated aiming or target correction.'; FalseFlags = 'Aim-related names in a library, documentation, compatibility code, or an unrelated feature can match.' }
    [PSCustomObject]@{ Flag = 'AutoClicker'; Meaning = 'May relate to automated attack clicking.'; FalseFlags = 'Click automation utilities, UI tests, accessibility helpers, or references in bundled libraries can match.' }
    [PSCustomObject]@{ Flag = 'AutoCrystal'; Meaning = 'May relate to automated crystal placement or attacks.'; FalseFlags = 'Crystal item names, guides, or unrelated game logic can match.' }
    [PSCustomObject]@{ Flag = 'AutoTotem'; Meaning = 'May relate to automatic offhand totem handling.'; FalseFlags = 'Inventory helpers or ordinary totem features can match.' }
    [PSCustomObject]@{ Flag = 'AutoAnchor'; Meaning = 'May relate to automated respawn-anchor use.'; FalseFlags = 'Anchor item handling or unrelated automation code can match.' }
    [PSCustomObject]@{ Flag = 'TriggerBot'; Meaning = 'May relate to automatic attacks when a target is under the crosshair.'; FalseFlags = 'The term in docs, examples, libraries, or compatibility code can match.' }
    [PSCustomObject]@{ Flag = 'SilentAim'; Meaning = "May relate to aim changes hidden from the player's view."; FalseFlags = 'Text-only references or unrelated targeting helpers can match.' }
    [PSCustomObject]@{ Flag = 'PingSpoof'; Meaning = 'May relate to altered network-latency reporting.'; FalseFlags = 'Network diagnostics, test fixtures, or latency utilities can match.' }
    [PSCustomObject]@{ Flag = 'FakeLag'; Meaning = 'May relate to intentional network delay.'; FalseFlags = 'Networking tests or lag-compensation code can use similar names.' }
    [PSCustomObject]@{ Flag = 'Velocity'; Meaning = 'May relate to changing knockback or movement response.'; FalseFlags = 'Ordinary movement, physics, or vector code commonly uses this word.' }
    [PSCustomObject]@{ Flag = 'ChestSteal'; Meaning = 'May relate to automated container looting.'; FalseFlags = 'Inventory utilities, container screens, or unrelated examples can match.' }
    [PSCustomObject]@{ Flag = 'Reach'; Meaning = 'May relate to changing interaction or attack distance.'; FalseFlags = 'Reachability, UI layout, or other ordinary uses of the word can match.' }
    [PSCustomObject]@{ Flag = 'KillAura'; Meaning = 'May relate to automated attacks against nearby entities.'; FalseFlags = 'The name in a detector, list, or documentation can match without implementing it.' }
    [PSCustomObject]@{ Flag = 'SelfDestruct'; Meaning = 'May relate to a feature that attempts to remove or hide itself.'; FalseFlags = 'Installers, cleanup utilities, and unrelated lifecycle code may use this term.' }
)
$script:AllResults = @()

function Get-JarReview {
    param([System.IO.FileInfo] $File)

    $matchesFound = [System.Collections.Generic.List[object]]::new()
    $scanError = $null
    $archive = $null
    try {
        $archive = [System.IO.Compression.ZipFile]::OpenRead($File.FullName)
        $entryCount = 0
        foreach ($entry in $archive.Entries) {
            $entryCount++
            if ($entryCount -gt 5000) {
                $scanError = 'Entry limit reached (5000); archive scan stopped.'
                break
            }
            if ($entry.Length -gt 8MB) { continue }
            if ($entry.FullName -notmatch '\.(class|json|mf|toml|properties|accesswidener)$') { continue }

            $stream = $null
            $memory = $null
            try {
                $stream = $entry.Open()
                $memory = [System.IO.MemoryStream]::new()
                $stream.CopyTo($memory)
                $content = [System.Text.Encoding]::UTF8.GetString($memory.ToArray())
                foreach ($indicator in $script:Indicators) {
                    if ($content.IndexOf($indicator, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                        $matchesFound.Add([PSCustomObject]@{
                            Indicator = $indicator
                            Entry     = $entry.FullName
                        })
                    }
                }
            }
            finally {
                if ($memory) { $memory.Dispose() }
                if ($stream) { $stream.Dispose() }
            }
        }
    }
    catch {
        $scanError = $_.Exception.Message
    }
    finally {
        if ($archive) { $archive.Dispose() }
    }

    $hash = $null
    try { $hash = (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash }
    catch { if (-not $scanError) { $scanError = "Could not calculate SHA-256: $($_.Exception.Message)" } }

    $uniqueIndicators = @($matchesFound | Select-Object -ExpandProperty Indicator -Unique)
    $result = if ($scanError) { 'Could not fully scan' }
              elseif ($uniqueIndicators.Count -gt 0) { 'Review indicators found' }
              else { 'No indicators found' }

    [PSCustomObject]@{
        FileName   = $File.Name
        FullPath   = $File.FullName
        SizeBytes  = $File.Length
        SHA256     = $hash
        Result     = $result
        FlagCount  = $uniqueIndicators.Count
        Indicators = @($matchesFound)
        ScanNote   = $scanError
    }
}

function Format-Size([long] $Bytes) {
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N2} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N1} KB' -f ($Bytes / 1KB)) }
    return "$Bytes bytes"
}

function Get-OpenGameReview {
    $gameProcesses = @(Get-Process -Name 'javaw', 'java' -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowTitle -match '(?i)minecraft' })
    if ($gameProcesses.Count -eq 0) {
        return [PSCustomObject]@{ Summary = 'No open Minecraft game window was found.'; Details = @('Start the game and keep its window open, then try again.') }
    }

    $details = [System.Collections.Generic.List[string]]::new()
    $details.Add('READ-ONLY OPEN-GAME CHECK')
    $details.Add('This checks visible process command-line agent options and loaded native module paths. It does not read or alter game memory.')
    $details.Add('')
    foreach ($game in $gameProcesses) {
        $game.Refresh()
        $details.Add("GAME: $($game.MainWindowTitle)")
        $details.Add("Process ID: $($game.Id)    Process: $($game.ProcessName)")

        $commandLine = $null
        try {
            $wmiProcess = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $($game.Id)" -ErrorAction Stop
            $commandLine = $wmiProcess.CommandLine
        } catch {
            $details.Add("Command line: unavailable ($($_.Exception.Message))")
        }

        if ($commandLine) {
            $agentOptions = [regex]::Matches($commandLine, '(?i)(?:^|\s)(-javaagent:\S+|-agentlib:\S+|-agentpath:\S+|-Xbootclasspath\S*)') |
                ForEach-Object { $_.Groups[1].Value }
            if (@($agentOptions).Count -gt 0) {
                $details.Add('REVIEW: JVM agent or boot-classpath option is present:')
                foreach ($option in $agentOptions) { $details.Add("  $option") }
                $details.Add('Possible false positives: approved profilers, performance tools, monitoring software, or launcher features may use Java agents. Verify the file and its source.')
            } else {
                $details.Add('No Java agent or boot-classpath option was visible in the process command line.')
            }
        } else {
            $details.Add('Could not inspect the process command line, so Java agent options could not be checked.')
        }

        $modulePaths = [System.Collections.Generic.List[string]]::new()
        $moduleError = $null
        try {
            foreach ($module in $game.Modules) {
                if ($module.FileName) { $modulePaths.Add($module.FileName) }
            }
        } catch { $moduleError = $_.Exception.Message }

        if ($moduleError) {
            $details.Add("Native module list: unavailable ($moduleError)")
        } else {
            $windowsRoot = [IO.Path]::GetFullPath($env:WINDIR).TrimEnd('\') + '\'
            $javaRoot = $null
            try { $javaRoot = [IO.Path]::GetDirectoryName((Get-CimInstance Win32_Process -Filter "ProcessId = $($game.Id)").ExecutablePath) } catch {}
            $javaRootPrefix = if ($javaRoot) { [IO.Path]::GetFullPath($javaRoot).TrimEnd('\') + '\' } else { $null }
            $externalModules = @($modulePaths | Where-Object {
                $full = $_
                -not $full.StartsWith($windowsRoot, [StringComparison]::OrdinalIgnoreCase) -and
                (-not $javaRootPrefix -or -not $full.StartsWith($javaRootPrefix, [StringComparison]::OrdinalIgnoreCase))
            } | Select-Object -Unique)
            $details.Add("Loaded native modules: $($modulePaths.Count) total; $($externalModules.Count) outside Windows and the Java runtime folder.")
            if ($externalModules.Count -gt 0) {
                $details.Add('REVIEW PATHS (not proof of cheating; overlays, graphics/audio drivers, capture, accessibility, and input tools can load modules):')
                foreach ($path in ($externalModules | Select-Object -First 40)) { $details.Add("  $path") }
                if ($externalModules.Count -gt 40) { $details.Add("  ... and $($externalModules.Count - 40) more") }
            }
        }
        $details.Add('')
    }
    $details.Add('LIMITS: A clean result does not rule out modified Java classes, runtime injection, or other in-memory changes. A name or path match is only a review lead; validate with trusted tools and context.')
    [PSCustomObject]@{ Summary = "Checked $($gameProcesses.Count) open Minecraft process(es); results are heuristic."; Details = @($details) }
}

function Show-FlagGuide {
    $guideForm = New-Object System.Windows.Forms.Form
    $guideForm.Text = 'Dawgs SS Tool — Flag and false-positive guide'
    $guideForm.StartPosition = 'CenterParent'
    $guideForm.Size = New-Object System.Drawing.Size(1000, 620)
    $guideForm.MinimumSize = New-Object System.Drawing.Size(760, 440)
    $guideForm.BackColor = [System.Drawing.Color]::White
    $guide = New-Object System.Windows.Forms.DataGridView
    $guide.Dock = 'Fill'
    $guide.ReadOnly = $true
    $guide.AllowUserToAddRows = $false
    $guide.AllowUserToDeleteRows = $false
    $guide.RowHeadersVisible = $false
    $guide.AutoSizeColumnsMode = 'Fill'
    $guide.BackgroundColor = [System.Drawing.Color]::White
    $guide.EnableHeadersVisualStyles = $false
    $guide.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(235, 240, 245)
    [void]$guide.Columns.Add('Flag', 'Flag')
    [void]$guide.Columns.Add('Meaning', 'What it may indicate')
    [void]$guide.Columns.Add('FalseFlags', 'Possible false positives')
    $guide.Columns['Flag'].FillWeight = 27
    $guide.Columns['Meaning'].FillWeight = 35
    $guide.Columns['FalseFlags'].FillWeight = 58
    foreach ($item in $script:FlagGuide) { [void]$guide.Rows.Add($item.Flag, $item.Meaning, $item.FalseFlags) }
    $note = New-Object System.Windows.Forms.Label
    $note.Dock = 'Bottom'
    $note.Height = 48
    $note.Padding = New-Object System.Windows.Forms.Padding(10)
    $note.Text = 'These are keyword matches in JAR entries, not proof that a mod performs the behavior. A clean scan cannot prove a mod is safe. Verify the file, source, and context manually.'
    $note.ForeColor = [System.Drawing.Color]::FromArgb(55, 67, 82)
    $guideForm.Controls.Add($guide)
    $guideForm.Controls.Add($note)
    [void]$guideForm.ShowDialog($form)
    $guideForm.Dispose()
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Dawgs SS Tool — Minecraft Mod Scanner'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(1180, 760)
$form.MinimumSize = New-Object System.Drawing.Size(900, 600)
$form.BackColor = [System.Drawing.Color]::FromArgb(246, 248, 251)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

$header = New-Object System.Windows.Forms.Panel
$header.Dock = 'Top'
$header.Height = 142
$header.Padding = New-Object System.Windows.Forms.Padding(18, 12, 18, 10)
$header.BackColor = [System.Drawing.Color]::FromArgb(25, 39, 58)
$form.Controls.Add($header)

$title = New-Object System.Windows.Forms.Label
$title.Text = 'DAWGS SS TOOL'
$title.ForeColor = [System.Drawing.Color]::White
$title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 16)
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(18, 10)
$header.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = 'Offline, read-only mod folder scan'
$subtitle.ForeColor = [System.Drawing.Color]::FromArgb(191, 207, 225)
$subtitle.AutoSize = $true
$subtitle.Location = New-Object System.Drawing.Point(20, 42)
$header.Controls.Add($subtitle)

$pathBox = New-Object System.Windows.Forms.TextBox
$pathBox.Location = New-Object System.Drawing.Point(20, 70)
$pathBox.Size = New-Object System.Drawing.Size(750, 25)
$pathBox.Anchor = 'Top,Left,Right'
$pathBox.Text = $Path
$header.Controls.Add($pathBox)

$browseButton = New-Object System.Windows.Forms.Button
$browseButton.Text = 'Browse…'
$browseButton.Location = New-Object System.Drawing.Point(780, 68)
$browseButton.Size = New-Object System.Drawing.Size(88, 28)
$browseButton.Anchor = 'Top,Right'
$header.Controls.Add($browseButton)

$scanButton = New-Object System.Windows.Forms.Button
$scanButton.Text = 'Scan folder'
$scanButton.Location = New-Object System.Drawing.Point(20, 105)
$scanButton.Size = New-Object System.Drawing.Size(108, 28)
$scanButton.Anchor = 'Top,Right'
$scanButton.BackColor = [System.Drawing.Color]::FromArgb(76, 175, 128)
$scanButton.ForeColor = [System.Drawing.Color]::White
$scanButton.FlatStyle = 'Flat'
$header.Controls.Add($scanButton)

$exportButton = New-Object System.Windows.Forms.Button
$exportButton.Text = 'Export CSV…'
$exportButton.Location = New-Object System.Drawing.Point(136, 105)
$exportButton.Size = New-Object System.Drawing.Size(108, 28)
$exportButton.Anchor = 'Top,Right'
$exportButton.Enabled = $false
$header.Controls.Add($exportButton)

$gameScanButton = New-Object System.Windows.Forms.Button
$gameScanButton.Text = 'Scan open game'
$gameScanButton.Location = New-Object System.Drawing.Point(252, 105)
$gameScanButton.Size = New-Object System.Drawing.Size(112, 28)
$gameScanButton.BackColor = [System.Drawing.Color]::FromArgb(71, 126, 181)
$gameScanButton.ForeColor = [System.Drawing.Color]::White
$gameScanButton.FlatStyle = 'Flat'
$header.Controls.Add($gameScanButton)

$guideButton = New-Object System.Windows.Forms.Button
$guideButton.Text = 'Flags + false positives'
$guideButton.Location = New-Object System.Drawing.Point(372, 105)
$guideButton.Size = New-Object System.Drawing.Size(160, 28)
$header.Controls.Add($guideButton)

$filterBox = New-Object System.Windows.Forms.CheckBox
$filterBox.Text = 'Show only items needing review'
$filterBox.AutoSize = $true
$filterBox.Location = New-Object System.Drawing.Point(550, 111)
$filterBox.ForeColor = [System.Drawing.Color]::FromArgb(55, 67, 82)
$header.Controls.Add($filterBox)

$split = New-Object System.Windows.Forms.SplitContainer
$split.Dock = 'Fill'
$split.Orientation = 'Vertical'
$split.BackColor = [System.Drawing.Color]::FromArgb(221, 226, 232)
$split.Padding = New-Object System.Windows.Forms.Padding(12, 8, 12, 8)
$form.Controls.Add($split)
$split.BringToFront()

$grid = New-Object System.Windows.Forms.DataGridView
$grid.Dock = 'Fill'
$grid.ReadOnly = $true
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.AllowUserToResizeRows = $false
$grid.MultiSelect = $false
$grid.SelectionMode = 'FullRowSelect'
$grid.RowHeadersVisible = $false
$grid.AutoSizeColumnsMode = 'Fill'
$grid.BackgroundColor = [System.Drawing.Color]::White
$grid.BorderStyle = 'None'
$grid.EnableHeadersVisualStyles = $false
$grid.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(235, 240, 245)
$grid.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(46, 59, 74)
$grid.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
$grid.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(215, 235, 226)
$grid.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::FromArgb(25, 39, 58)
[void]$grid.Columns.Add('FileName', 'Mod file')
[void]$grid.Columns.Add('Result', 'Result')
[void]$grid.Columns.Add('Flags', 'Flags')
$grid.Columns['FileName'].FillWeight = 155
$grid.Columns['Result'].FillWeight = 125
$grid.Columns['Flags'].FillWeight = 45
$split.Panel1.Controls.Add($grid)

$detailsPanel = New-Object System.Windows.Forms.Panel
$detailsPanel.Dock = 'Fill'
$detailsPanel.BackColor = [System.Drawing.Color]::White
$split.Panel2.Controls.Add($detailsPanel)
$detailHeader = New-Object System.Windows.Forms.Label
$detailHeader.Text = 'MOD DETAILS'
$detailHeader.Dock = 'Top'
$detailHeader.Height = 34
$detailHeader.Padding = New-Object System.Windows.Forms.Padding(12, 9, 4, 4)
$detailHeader.ForeColor = [System.Drawing.Color]::FromArgb(42, 61, 80)
$detailHeader.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
$detailsPanel.Controls.Add($detailHeader)
$detailText = New-Object System.Windows.Forms.TextBox
$detailText.Dock = 'Fill'
$detailText.Multiline = $true
$detailText.ReadOnly = $true
$detailText.ScrollBars = 'Vertical'
$detailText.WordWrap = $true
$detailText.BorderStyle = 'None'
$detailText.BackColor = [System.Drawing.Color]::White
$detailText.ForeColor = [System.Drawing.Color]::FromArgb(50, 62, 76)
$detailText.Font = New-Object System.Drawing.Font('Consolas', 9)
$detailText.Text = "Choose a mod in the list to see its scan details, or use Scan open game for a read-only process review.`r`n`r`nThe mod scan checks configured strings in JAR class and metadata entries. Matches can be false positives and need human review."
$detailsPanel.Controls.Add($detailText)
$detailText.BringToFront()

$footer = New-Object System.Windows.Forms.StatusStrip
$footer.Dock = 'Bottom'
$statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLabel.Text = 'Choose a mods folder, then select Scan folder.'
$statusLabel.Spring = $true
$statusLabel.TextAlign = 'MiddleLeft'
[void]$footer.Items.Add($statusLabel)
$form.Controls.Add($footer)

# The Fill-docked split container has its real width only after the form lays
# out. Set its distance first using that width, then apply panel minimums.
$form.Add_Shown({
    $availableWidth = $split.ClientSize.Width
    $leftMin = 390
    $rightMin = 300
    if ($availableWidth -lt ($leftMin + $rightMin)) {
        $leftMin = [Math]::Max(25, [int][Math]::Floor($availableWidth * 0.55))
        $rightMin = [Math]::Max(25, $availableWidth - $leftMin)
    }
    $maxDistance = $availableWidth - $rightMin
    $distance = [Math]::Max($leftMin, [Math]::Min(660, $maxDistance))
    $split.SplitterDistance = $distance
    $split.Panel1MinSize = $leftMin
    $split.Panel2MinSize = $rightMin
})

function Update-Grid {
    $selectedPath = $null
    if ($grid.SelectedRows.Count -gt 0 -and $grid.SelectedRows[0].Tag) {
        $selectedPath = $grid.SelectedRows[0].Tag.FullPath
    }
    $grid.Rows.Clear()
    $visible = if ($filterBox.Checked) {
        @($script:AllResults | Where-Object { $_.Result -ne 'No indicators found' })
    } else { @($script:AllResults) }

    foreach ($item in $visible) {
        $rowIndex = $grid.Rows.Add($item.FileName, $item.Result, $item.FlagCount)
        $row = $grid.Rows[$rowIndex]
        $row.Tag = $item
        if ($item.Result -eq 'Review indicators found') {
            $row.DefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(154, 93, 24)
        } elseif ($item.Result -eq 'Could not fully scan') {
            $row.DefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(175, 52, 52)
        }
        if ($selectedPath -and $item.FullPath -eq $selectedPath) { $row.Selected = $true }
    }
    if ($grid.SelectedRows.Count -eq 0 -and $grid.Rows.Count -gt 0) { $grid.Rows[0].Selected = $true }
    if ($grid.SelectedRows.Count -gt 0) { Show-Details $grid.SelectedRows[0].Tag }
}

function Show-Details {
    param($Item)
    if (-not $Item) { return }
    $detailHeader.Text = 'MOD DETAILS'
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("FILE`r`n$($Item.FileName)")
    $lines.Add("`r`nRESULT`r`n$($Item.Result)")
    $lines.Add("`r`nINDICATOR COUNT`r`n$($Item.FlagCount) unique indicator(s)")
    $lines.Add("`r`nFILE SIZE`r`n$(Format-Size $Item.SizeBytes)")
    $lines.Add("`r`nSHA-256`r`n$($Item.SHA256)")
    $lines.Add("`r`nFULL PATH`r`n$($Item.FullPath)")
    $lines.Add("`r`nMATCH DETAILS")
    if ($Item.Indicators.Count -gt 0) {
        foreach ($match in $Item.Indicators) {
            $lines.Add("- $($match.Indicator)`r`n  Entry: $($match.Entry)")
        }
    } else {
        $lines.Add('No configured indicators were found.')
    }
    if ($Item.ScanNote) { $lines.Add("`r`nSCAN NOTE`r`n$($Item.ScanNote)") }
    $lines.Add("`r`nInterpretation`r`nA string match is only a review lead. Legitimate mods and bundled libraries can contain these terms; absence of a match does not prove a mod is safe.")
    $detailText.Text = $lines -join "`r`n"
}

$browseButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = 'Select the Minecraft mods folder to review'
    $dialog.SelectedPath = $pathBox.Text
    if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        $pathBox.Text = $dialog.SelectedPath
    }
    $dialog.Dispose()
})

$filterBox.Add_CheckedChanged({ Update-Grid })
$guideButton.Add_Click({ Show-FlagGuide })
$gameScanButton.Add_Click({
    try {
        $gameScanButton.Enabled = $false
        $statusLabel.Text = 'Checking the open Minecraft process (read-only)…'
        [System.Windows.Forms.Application]::DoEvents()
        $review = Get-OpenGameReview
        $detailHeader.Text = 'OPEN GAME REVIEW'
        $detailText.Text = @($review.Details) -join "`r`n"
        $statusLabel.Text = $review.Summary
    } catch {
        [void][System.Windows.Forms.MessageBox]::Show(
            "The open-game review could not finish:`r`n$($_.Exception.Message)",
            'Game review error', 'OK', 'Warning'
        )
        $statusLabel.Text = 'Open-game review could not finish.'
    } finally {
        $gameScanButton.Enabled = $true
    }
})
$grid.Add_SelectionChanged({
    if ($grid.SelectedRows.Count -gt 0) { Show-Details $grid.SelectedRows[0].Tag }
})

$scanButton.Add_Click({
    $folder = $pathBox.Text.Trim()
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
        [void][System.Windows.Forms.MessageBox]::Show(
            "That folder does not exist or cannot be accessed:`r`n$folder",
            'Folder not found', 'OK', 'Warning'
        )
        return
    }
    try {
        $scanButton.Enabled = $false
        $browseButton.Enabled = $false
        $exportButton.Enabled = $false
        $grid.Rows.Clear()
        $detailText.Text = ''
        $script:AllResults = @()
        $files = @(Get-ChildItem -LiteralPath $folder -File -Filter '*.jar' | Sort-Object Name)
        if ($files.Count -eq 0) {
            $statusLabel.Text = 'No .jar files found in the selected folder.'
            $detailText.Text = 'No JAR files were found.'
            return
        }
        $scanned = 0
        foreach ($file in $files) {
            $scanned++
            $statusLabel.Text = "Scanning $scanned of $($files.Count): $($file.Name)"
            [System.Windows.Forms.Application]::DoEvents()
            $script:AllResults += Get-JarReview -File $file
        }
        Update-Grid
        $flagged = @($script:AllResults | Where-Object { $_.Result -ne 'No indicators found' }).Count
        $statusLabel.Text = "Scanned $($script:AllResults.Count) JAR(s); $flagged item(s) need review; local, read-only scan"
        $exportButton.Enabled = $true
    }
    catch {
        [void][System.Windows.Forms.MessageBox]::Show(
            "The scan could not continue:`r`n$($_.Exception.Message)",
            'Scan error', 'OK', 'Error'
        )
        $statusLabel.Text = 'Scan stopped because of an error.'
    }
    finally {
        $scanButton.Enabled = $true
        $browseButton.Enabled = $true
    }
})

$exportButton.Add_Click({
    if ($script:AllResults.Count -eq 0) { return }
    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.Title = 'Export scan results'
    $dialog.Filter = 'CSV files (*.csv)|*.csv'
    $dialog.FileName = 'mod-review.csv'
    if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:AllResults | ForEach-Object {
            [PSCustomObject]@{
                FileName   = $_.FileName
                FullPath   = $_.FullPath
                SizeBytes  = $_.SizeBytes
                SHA256     = $_.SHA256
                Result     = $_.Result
                FlagCount  = $_.FlagCount
                Indicators = (($_.Indicators | ForEach-Object { "$($_.Indicator) @ $($_.Entry)" }) -join '; ')
                ScanNote   = $_.ScanNote
            }
        } | Export-Csv -LiteralPath $dialog.FileName -NoTypeInformation -Encoding UTF8
        $statusLabel.Text = "CSV report saved: $($dialog.FileName)"
    }
    $dialog.Dispose()
})

if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    $pathBox.Text = "$env:APPDATA\.minecraft\mods"
}
[void]$form.ShowDialog()
$form.Dispose()
