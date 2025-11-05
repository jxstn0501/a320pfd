<#
    MediaSorter.ps1
    -----------------
    Dieses Skript sortiert Medieninhalte aus einem unsortierten Quellordner in
    vordefinierte Zielstrukturen für Filme und Serien. Die Erkennung kann rein
    lokal anhand des Dateinamens oder optional über die TMDb-API erfolgen.

    Voraussetzungen:
    * PowerShell 7.x
    * Keine externen Module notwendig

    Hauptfunktionen:
    * Menügestützte Ausführung (Dry Run, Normal, AutoYes, Konfiguration)
    * Ausführliches Logging in UTF-8 (MediaSorter.log im Skriptverzeichnis)
    * Sichere Dateioperationen mit Bestätigung bei Konflikten
    * Lokale Mustererkennung (SxxEyy, 1x02, Season 2 Episode 5, ...)
    * Optionale TMDb-Integration mit persistentem API-Key
    * Automatisches Löschen leerer Quellordner

    Alle Funktionen sind deutschsprachig kommentiert, um eine leichte
    Erweiterbarkeit sicherzustellen.
#>

#region Allgemeine Initialisierung ---------------------------------------------------------

# Konsole auf UTF-8 stellen, damit Umlaute und Sonderzeichen korrekt ausgegeben werden.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Übergeordnete Scriptvariablen definieren.
$Script:ScriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
$Script:ScriptDirectory = Split-Path -Parent $Script:ScriptPath
$Script:LogFile = Join-Path -Path $Script:ScriptDirectory -ChildPath 'MediaSorter.log'
$Script:ConfigFile = Join-Path -Path $Script:ScriptDirectory -ChildPath 'MediaSorter.config.json'

# Standardkonfiguration festlegen.
$Script:DefaultConfig = [ordered]@{
    SourcePath = 'D:\JellyData\Finished\Unsorted'
    MoviesPath = 'D:\JellyData\Finished\movies'
    ShowsPath  = 'D:\JellyData\Finished\Shows'
    UseTMDb    = $false
}

# Globale Statusvariablen.
$Script:Config = $null
$Script:TmdbApiKey = $null
$Script:VideoExtensions = @('.mkv', '.mp4', '.avi', '.mov', '.m4v')
$Script:SupplementalExtensions = @('.nfo')
$Script:IgnoredExtensions = @('.rar')

# TLS 1.2 sicherstellen (für TMDb erforderlich).
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

#endregion Allgemeine Initialisierung ------------------------------------------------------

#region Hilfsfunktionen: Logging, Konfiguration, Bestätigungen ------------------------------

function Write-Log {
    <#
        .SYNOPSIS
        Schreibt eine Meldung sowohl auf die Konsole als auch in die Logdatei.

        .PARAMETER Message
        Text der protokolliert werden soll.

        .PARAMETER Level
        Optionale Kennzeichnung (INFO, WARN, ERROR, DEBUG).
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')]
        [string]$Level = 'INFO'
    )

    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $formatted = "[$timestamp][$Level] $Message"

    switch ($Level) {
        'INFO'  { Write-Host $formatted -ForegroundColor Cyan }
        'WARN'  { Write-Host $formatted -ForegroundColor Yellow }
        'ERROR' { Write-Host $formatted -ForegroundColor Red }
        'DEBUG' { Write-Host $formatted -ForegroundColor DarkGray }
    }

    try {
        $formatted | Out-File -FilePath $Script:LogFile -Encoding UTF8 -Append
    }
    catch {
        Write-Host "[WARN] Konnte Logdatei nicht schreiben: $_" -ForegroundColor Yellow
    }
}

function Initialize-Config {
    <#
        .SYNOPSIS
        Lädt die Konfiguration von Datenträger oder erstellt eine neue Datei.
    #>
    if (Test-Path -LiteralPath $Script:ConfigFile) {
        try {
            $json = Get-Content -LiteralPath $Script:ConfigFile -Raw -Encoding UTF8
            $Script:Config = $json | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            Write-Log -Message 'Konfigurationsdatei fehlerhaft – es wird eine neue Datei erstellt.' -Level 'WARN'
            $Script:Config = [pscustomobject]$Script:DefaultConfig
            Save-Config
        }
    }
    else {
        $Script:Config = [pscustomobject]$Script:DefaultConfig
        Save-Config
    }
}

function Save-Config {
    <#
        .SYNOPSIS
        Speichert die aktuelle Konfiguration als JSON-Datei.
    #>
    try {
        $json = $Script:Config | ConvertTo-Json -Depth 3
        $json | Out-File -FilePath $Script:ConfigFile -Encoding UTF8
        Write-Log -Message 'Konfiguration gespeichert.' -Level 'DEBUG'
    }
    catch {
        Write-Log -Message "Konfiguration konnte nicht gespeichert werden: $_" -Level 'ERROR'
    }
}

function Ensure-Directory {
    <#
        .SYNOPSIS
        Stellt sicher, dass ein Verzeichnis existiert und gibt den Pfad zurück.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        try {
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
            Write-Log -Message "Verzeichnis erstellt: $Path" -Level 'DEBUG'
        }
        catch {
            Write-Log -Message "Verzeichnis konnte nicht erstellt werden: $Path -> $_" -Level 'ERROR'
        }
    }

    return $Path
}

function Confirm-Action {
    <#
        .SYNOPSIS
        Fragt den Benutzer um Bestätigung, sofern AutoYes nicht aktiv ist.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [bool]$AutoYes = $false
    )

    if ($AutoYes) {
        return $true
    }

    do {
        $response = Read-Host "$Message (j/n)"
    } while ($response -notmatch '^[jnJN]$')

    return $response -match '^[jJ]$'
}

function Move-ItemSafe {
    <#
        .SYNOPSIS
        Verschiebt Dateien oder Ordner mit Konfliktprüfung und Logging.
    #>
    param(
        [Parameter(Mandatory)]
        [System.IO.FileSystemInfo]$Source,

        [Parameter(Mandatory)]
        [string]$DestinationPath,

        [bool]$DryRun = $false,

        [bool]$AutoYes = $false
    )

    if ($Source.PSIsContainer) {
        Move-DirectorySafe -Source $Source -DestinationPath $DestinationPath -DryRun:$DryRun -AutoYes:$AutoYes
        return
    }

    $destinationDir = Split-Path -Parent $DestinationPath
    Ensure-Directory -Path $destinationDir | Out-Null

    if (Test-Path -LiteralPath $DestinationPath) {
        Write-Log -Message "Zieldatei existiert bereits: $DestinationPath" -Level 'WARN'
        if (-not (Confirm-Action -Message 'Datei überschreiben?' -AutoYes:$AutoYes)) {
            Write-Log -Message "Überspringe Datei wegen bestehendem Ziel: $($Source.FullName)" -Level 'INFO'
            return
        }
    }

    if ($DryRun) {
        Write-Log -Message "[DryRun] Datei würde verschoben: $($Source.FullName) -> $DestinationPath" -Level 'INFO'
    }
    else {
        try {
            Move-Item -LiteralPath $Source.FullName -Destination $DestinationPath -Force
            Write-Log -Message "Datei verschoben: $($Source.FullName) -> $DestinationPath" -Level 'INFO'
        }
        catch {
            Write-Log -Message "Fehler beim Verschieben: $($Source.FullName) -> $DestinationPath :: $_" -Level 'ERROR'
        }
    }
}

function Move-DirectorySafe {
    <#
        .SYNOPSIS
        Verschiebt Verzeichnisse unter Beachtung bestehender Zielordner.
    #>
    param(
        [Parameter(Mandatory)]
        [System.IO.DirectoryInfo]$Source,

        [Parameter(Mandatory)]
        [string]$DestinationPath,

        [bool]$DryRun = $false,

        [bool]$AutoYes = $false
    )

    $destinationParent = Split-Path -Parent $DestinationPath
    Ensure-Directory -Path $destinationParent | Out-Null

    if (Test-Path -LiteralPath $DestinationPath) {
        Write-Log -Message "Zielordner existiert bereits – Inhalte werden zusammengeführt: $DestinationPath" -Level 'WARN'

        foreach ($child in Get-ChildItem -LiteralPath $Source.FullName -Force) {
            $targetChildPath = Join-Path -Path $DestinationPath -ChildPath $child.Name
            Move-ItemSafe -Source $child -DestinationPath $targetChildPath -DryRun:$DryRun -AutoYes:$AutoYes
        }

        if (-not $DryRun) {
            Remove-EmptyDirectory -Directory $Source
        }
        return
    }

    if ($DryRun) {
        Write-Log -Message "[DryRun] Ordner würde verschoben: $($Source.FullName) -> $DestinationPath" -Level 'INFO'
    }
    else {
        try {
            Move-Item -LiteralPath $Source.FullName -Destination $DestinationPath
            Write-Log -Message "Ordner verschoben: $($Source.FullName) -> $DestinationPath" -Level 'INFO'
        }
        catch {
            Write-Log -Message "Fehler beim Ordner-Verschieben: $($Source.FullName) -> $DestinationPath :: $_" -Level 'ERROR'
        }
    }
}

function Remove-EmptyDirectory {
    <#
        .SYNOPSIS
        Löscht leere Verzeichnisse, falls keine Dateien mehr enthalten sind.
    #>
    param(
        [Parameter(Mandatory)]
        [System.IO.DirectoryInfo]$Directory
    )

    try {
        if ((Get-ChildItem -LiteralPath $Directory.FullName -Force | Measure-Object).Count -eq 0) {
            Remove-Item -LiteralPath $Directory.FullName -Force
            Write-Log -Message "Leeren Ordner gelöscht: $($Directory.FullName)" -Level 'DEBUG'
        }
    }
    catch {
        Write-Log -Message "Konnte leeren Ordner nicht löschen: $($Directory.FullName) :: $_" -Level 'WARN'
    }
}

#endregion Hilfsfunktionen ---------------------------------------------------------------

#region Namensanalyse & Normalisierung -----------------------------------------------------

function Clean-TitleString {
    <#
        .SYNOPSIS
        Entfernt unerwünschte Zeichen und wandelt Trennzeichen in Leerzeichen um.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$InputString
    )

    $value = $InputString
    $value = $value -replace '[._]', ' '
    $value = $value -replace '\s+', ' '
    $value = $value.Trim()
    return $value
}

function Sanitize-PathSegment {
    <#
        .SYNOPSIS
        Entfernt ungültige Zeichen aus Dateipfaden (z. B. ":<>|?").
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $invalid = [System.IO.Path]::GetInvalidFileNameChars()
    $builder = New-Object -TypeName System.Text.StringBuilder
    foreach ($char in $Name.ToCharArray()) {
        if ($invalid -contains $char) {
            $null = $builder.Append('-')
        }
        else {
            $null = $builder.Append($char)
        }
    }

    return $builder.ToString().Trim()
}

function Get-YearFromName {
    <#
        .SYNOPSIS
        Extrahiert ein Jahr (1900-2099) aus einem Dateinamen.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $match = [Regex]::Match($Name, '(?<!\d)((19|20)\d{2})(?!\d)')
    if ($match.Success) {
        return [int]$match.Groups[1].Value
    }

    return $null
}

function Title-ContainsYearToken {
    <#
        .SYNOPSIS
        Prüft, ob ein Titel bereits eine Jahresangabe enthält.

        .DESCRIPTION
        Erkennt Jahreszahlen in Klammern ("(2022)") oder nach Unterstrich
        ("_2022" bzw. "_1999"), um doppelte Ergänzungen zu vermeiden.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $false
    }

    return [Regex]::IsMatch($Name, '(?i)(\(\d{4}\)|_(19|20)\d{2}|\b(19|20)\d{2}\b)')
}

function Get-SeriesInfoFromName {
    <#
        .SYNOPSIS
        Erkennt gängige Serienmuster im Namen und liefert Serieninformationen.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $patterns = @(
        '^(?<show>.+?)[ ._-]*[Ss](?<season>\d{1,2})[ ._-]*[Ee](?<episode>\d{1,2})',
        '^(?<show>.+?)[ ._-]*(?<season>\d{1,2})x(?<episode>\d{1,2})',
        '^(?<show>.+?)[ ._-]*Season[ ._-]*(?<season>\d{1,2})[ ._-]*(Episode|Ep)[ ._-]*(?<episode>\d{1,2})'
    )

    foreach ($pattern in $patterns) {
        $match = [Regex]::Match($Name, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($match.Success) {
            $showName = Clean-TitleString -InputString $match.Groups['show'].Value
            $season = [int]$match.Groups['season'].Value
            $episode = [int]$match.Groups['episode'].Value

            return [pscustomobject]@{
                Name    = $showName
                Season  = $season
                Episode = $episode
            }
        }
    }

    return $null
}

function Derive-TitleFromFileSystemInfo {
    <#
        .SYNOPSIS
        Leitet einen Titel aus Datei- oder Ordnernamen ab.
    #>
    param(
        [Parameter(Mandatory)]
        [System.IO.FileSystemInfo]$Item
    )

    $name = if ($Item.PSIsContainer) { $Item.Name } else { [System.IO.Path]::GetFileNameWithoutExtension($Item.Name) }
    return Clean-TitleString -InputString $name
}

function Resolve-SeriesRoot {
    <#
        .SYNOPSIS
        Ermittelt den Zielordner einer Serie unter Berücksichtigung bestehender Strukturen.

        .DESCRIPTION
        Verhindert die Anlage doppelter Serien-Ordner, indem zunächst nach vorhandenen
        Ordnern mit identischem Namen (inklusive Jahreszusatz) gesucht wird. Wird kein
        passender Ordner gefunden, wird der gewünschte Zielordner vorgeschlagen.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$SeriesBaseName,

        [Nullable[int]]$Year
    )

    $showsPath = $Script:Config.ShowsPath
    $existingDir = $null
    $resolvedYear = $Year

    if (Test-Path -LiteralPath $showsPath) {
        $directories = Get-ChildItem -LiteralPath $showsPath -Directory -ErrorAction SilentlyContinue
        $candidateNames = @()

        if ($Year) {
            $candidateNames += "{0} ({1})" -f $SeriesBaseName, $Year
        }

        $candidateNames += $SeriesBaseName

        foreach ($candidate in $candidateNames) {
            $existingDir = $directories | Where-Object { $_.Name -ieq $candidate } | Select-Object -First 1
            if ($existingDir) {
                break
            }
        }

        if (-not $existingDir) {
            $escaped = [Regex]::Escape($SeriesBaseName)
            $existingDir = $directories | Where-Object { $_.Name -match "^(?i)$escaped\s*\((19|20)\d{2}\)$" } | Select-Object -First 1
            if ($existingDir) {
                $yearMatch = [Regex]::Match($existingDir.Name, '(19|20)\d{2}')
                if ($yearMatch.Success) {
                    $resolvedYear = [int]$yearMatch.Value
                }
            }
        }
    }

    if ($existingDir) {
        return [pscustomobject]@{
            Name   = $existingDir.Name
            Path   = $existingDir.FullName
            Exists = $true
            Year   = $resolvedYear
        }
    }

    $folderName = if ($Year) { "{0} ({1})" -f $SeriesBaseName, $Year } else { $SeriesBaseName }
    return [pscustomobject]@{
        Name   = $folderName
        Path   = Join-Path -Path $showsPath -ChildPath $folderName
        Exists = $false
        Year   = $Year
    }
}

#endregion Namensanalyse -----------------------------------------------------------------

#region TMDb-Integration -------------------------------------------------------------------

function Get-TmdbKeyFilePath {
    <#
        .SYNOPSIS
        Liefert den vollständigen Pfad zur Datei mit dem TMDb-API-Key.
    #>
    $appData = [Environment]::GetFolderPath('ApplicationData')
    return Join-Path -Path $appData -ChildPath 'MediaSorter\tmdb.key'
}

function Load-TmdbApiKey {
    <#
        .SYNOPSIS
        Lädt den TMDb-API-Key aus der gespeicherten Datei oder fordert ihn an.
    #>
    $keyFile = Get-TmdbKeyFilePath
    if (Test-Path -LiteralPath $keyFile) {
        try {
            $Script:TmdbApiKey = (Get-Content -LiteralPath $keyFile -Raw).Trim()
        }
        catch {
            Write-Log -Message "TMDb-Key konnte nicht gelesen werden: $_" -Level 'WARN'
            $Script:TmdbApiKey = $null
        }
    }
    else {
        Write-Log -Message 'TMDb-API-Key nicht gefunden. Er wird bei Bedarf abgefragt.' -Level 'DEBUG'
    }
}

function Prompt-TmdbApiKey {
    <#
        .SYNOPSIS
        Fordert den Benutzer zur Eingabe eines TMDb-API-Keys auf und speichert ihn.
    #>
    $keyFile = Get-TmdbKeyFilePath
    $directory = Split-Path -Parent $keyFile
    Ensure-Directory -Path $directory | Out-Null

    $input = Read-Host 'Bitte TMDb-API-Key eingeben'
    if ([string]::IsNullOrWhiteSpace($input)) {
        Write-Log -Message 'Kein API-Key eingegeben. TMDb bleibt deaktiviert.' -Level 'WARN'
        return
    }

    try {
        $input.Trim() | Out-File -FilePath $keyFile -Encoding ASCII -Force
        $Script:TmdbApiKey = $input.Trim()
        Write-Log -Message "TMDb-API-Key gespeichert unter $keyFile" -Level 'INFO'
    }
    catch {
        Write-Log -Message "TMDb-API-Key konnte nicht gespeichert werden: $_" -Level 'ERROR'
    }
}

function Invoke-TmdbSearch {
    <#
        .SYNOPSIS
        Ruft die TMDb-Suche (search/multi) auf und liefert das Resultat.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Query,

        [int]$Year
    )

    if (-not $Script:TmdbApiKey) {
        Prompt-TmdbApiKey
        if (-not $Script:TmdbApiKey) {
            return $null
        }
    }

    $encodedQuery = [System.Uri]::EscapeDataString($Query)
    $uriBuilder = [System.Text.StringBuilder]::new("https://api.themoviedb.org/3/search/multi?api_key=$($Script:TmdbApiKey)&query=$encodedQuery")

    if ($Year) {
        $null = $uriBuilder.Append("&year=$Year&first_air_date_year=$Year")
    }

    $uri = $uriBuilder.ToString()

    try {
        Write-Log -Message "TMDb-Abfrage: $uri" -Level 'DEBUG'
        $response = Invoke-RestMethod -Method Get -Uri $uri -TimeoutSec 15
        if ($response && $response.results) {
            return $response.results | Select-Object -First 1
        }
        else {
            return $null
        }
    }
    catch {
        Write-Log -Message "TMDb-Abfrage fehlgeschlagen: $_" -Level 'WARN'
        return $null
    }
}

function Resolve-MediaUsingTmdb {
    <#
        .SYNOPSIS
        Bestimmt Film/Serie über TMDb. Rückgabe: PSCustomObject oder $null.
    #>
    param(
        [Parameter(Mandatory)]
        [System.IO.FileSystemInfo]$Item
    )

    if (-not $Script:Config.UseTMDb) {
        return $null
    }

    $title = Derive-TitleFromFileSystemInfo -Item $Item
    $year = Get-YearFromName -Name $title

    $result = Invoke-TmdbSearch -Query $title -Year $year
    if (-not $result) {
        return $null
    }

    switch ($result.media_type) {
        'tv' {
            $seasonNumber = 1
            if ($result.first_air_date) {
                $airDate = Get-Date $result.first_air_date -ErrorAction SilentlyContinue
                if ($airDate) {
                    $year = $airDate.Year
                }
            }

            return [pscustomobject]@{
                Type        = 'Series'
                Title       = $result.name
                Year        = $year
                Season      = $seasonNumber
                Description = 'Erkennung über TMDb (TV)'
            }
        }
        'movie' {
            $releaseYear = $null
            if ($result.release_date) {
                $date = Get-Date $result.release_date -ErrorAction SilentlyContinue
                if ($date) {
                    $releaseYear = $date.Year
                }
            }

            return [pscustomobject]@{
                Type        = 'Movie'
                Title       = $result.title
                Year        = $releaseYear
                Description = 'Erkennung über TMDb (Film)'
            }
        }
        Default {
            return $null
        }
    }
}

#endregion TMDb-Integration ---------------------------------------------------------------

#region Lokale Medienanalyse ---------------------------------------------------------------

function Determine-MediaLocally {
    <#
        .SYNOPSIS
        Bestimmt anhand von Dateinamen, ob es sich um Serie oder Film handelt.
    #>
    param(
        [Parameter(Mandatory)]
        [System.IO.FileSystemInfo]$Item
    )

    $title = Derive-TitleFromFileSystemInfo -Item $Item
    $seriesInfo = Get-SeriesInfoFromName -Name $title

    if (-not $seriesInfo -and $Item.PSIsContainer) {
        # Durchsuche enthaltene Dateien nach Serienmustern.
        foreach ($file in Get-ChildItem -LiteralPath $Item.FullName -Recurse -File -ErrorAction SilentlyContinue) {
            if ($Script:VideoExtensions -contains $file.Extension.ToLowerInvariant()) {
                $info = Get-SeriesInfoFromName -Name $file.BaseName
                if ($info) {
                    $seriesInfo = $info
                    break
                }
            }
        }
    }

    if ($seriesInfo) {
        $seriesYear = Get-YearFromName -Name $title
        return [pscustomobject]@{
            Type        = 'Series'
            Title       = $seriesInfo.Name
            Season      = $seriesInfo.Season
            Episode     = $seriesInfo.Episode
            Year        = $seriesYear
            Description = 'Lokale Serienerkennung'
        }
    }

    $year = Get-YearFromName -Name $title
    return [pscustomobject]@{
        Type        = 'Movie'
        Title       = $title
        Year        = $year
        Description = 'Lokale Filmerkennung'
    }
}

#endregion Lokale Medienanalyse -----------------------------------------------------------

#region Verarbeitung von Serien und Filmen -------------------------------------------------

function Handle-SeriesItem {
    <#
        .SYNOPSIS
        Verschiebt Episoden-Dateien und legt Serienstruktur an.
    #>
    param(
        [Parameter(Mandatory)]
        [System.IO.FileSystemInfo]$Item,

        [Parameter(Mandatory)]
        [pscustomobject]$Metadata,

        [bool]$DryRun = $false,

        [bool]$AutoYes = $false
    )

    $seriesTitle = Clean-TitleString -InputString $Metadata.Title
    $seriesName = Sanitize-PathSegment -Name $seriesTitle
    $season = if ($Metadata.Season) { $Metadata.Season } else { 1 }
    $seasonFolder = "Season {0:D2}" -f $season
    $seriesInfo = Resolve-SeriesRoot -SeriesBaseName $seriesName -Year $Metadata.Year

    if ($seriesInfo.Year -and $Metadata.PSObject.Properties['Year']) {
        $Metadata.Year = $seriesInfo.Year
    }
    elseif ($seriesInfo.Year -and -not $Metadata.PSObject.Properties['Year']) {
        $Metadata | Add-Member -NotePropertyName 'Year' -NotePropertyValue $seriesInfo.Year -Force
    }

    $seriesRoot = $seriesInfo.Path
    Ensure-Directory -Path $Script:Config.ShowsPath | Out-Null

    if ($seriesInfo.Exists) {
        Write-Log -Message "Bestehende Serie erkannt: $($seriesInfo.Name)" -Level 'INFO'
    }
    else {
        Write-Log -Message "Neue Serie wird angelegt: $($seriesInfo.Name)" -Level 'INFO'
    }

    Ensure-Directory -Path $seriesRoot | Out-Null
    $targetSeasonPath = Join-Path -Path $seriesRoot -ChildPath $seasonFolder

    if (Test-Path -LiteralPath $targetSeasonPath) {
        Write-Log -Message "Bestehende Staffel erkannt: $($seriesInfo.Name) -> $seasonFolder" -Level 'INFO'
    }
    else {
        Write-Log -Message "Neue Staffel wird angelegt: $($seriesInfo.Name) -> $seasonFolder" -Level 'INFO'
    }

    Ensure-Directory -Path $targetSeasonPath | Out-Null

    Write-Log -Message "Serie erkannt: $($seriesInfo.Name) (Season $season) :: $($Metadata.Description)" -Level 'INFO'

    $itemsToMove = @()

    if ($Item.PSIsContainer) {
        $itemsToMove = Get-ChildItem -LiteralPath $Item.FullName -Force
    }
    else {
        $itemsToMove = @($Item)
    }

    foreach ($child in $itemsToMove) {
        if ($child.PSIsContainer) {
            # Rekursiv Inhalte bearbeiten, Ordnerstruktur wird beibehalten.
            Handle-SeriesItem -Item $child -Metadata $Metadata -DryRun:$DryRun -AutoYes:$AutoYes
            if (-not $DryRun) {
                Remove-EmptyDirectory -Directory $child
            }
            continue
        }

        $extension = $child.Extension.ToLowerInvariant()
        if ($Script:IgnoredExtensions -contains $extension) {
            Write-Log -Message "Ignoriere Datei (ignored extension): $($child.FullName)" -Level 'DEBUG'
            continue
        }

        if (($Script:VideoExtensions + $Script:SupplementalExtensions) -notcontains $extension) {
            Write-Log -Message "Überspringe Datei (nicht relevant): $($child.FullName)" -Level 'DEBUG'
            continue
        }

        $destination = Join-Path -Path $targetSeasonPath -ChildPath $child.Name
        Move-ItemSafe -Source $child -DestinationPath $destination -DryRun:$DryRun -AutoYes:$AutoYes
    }

    if ($Item.PSIsContainer -and -not $DryRun) {
        Remove-EmptyDirectory -Directory $Item
    }
}

function Handle-MovieItem {
    <#
        .SYNOPSIS
        Verschiebt Filme (Dateien oder Ordner) in die Zielstruktur.
    #>
    param(
        [Parameter(Mandatory)]
        [System.IO.FileSystemInfo]$Item,

        [Parameter(Mandatory)]
        [pscustomobject]$Metadata,

        [bool]$DryRun = $false,

        [bool]$AutoYes = $false
    )

    $cleanTitle = Clean-TitleString -InputString $Metadata.Title
    $title = Sanitize-PathSegment -Name $cleanTitle
    $hasYearToken = Title-ContainsYearToken -Name $title
    $folderName = if ($Metadata.Year -and -not $hasYearToken) { "$title ($($Metadata.Year))" } else { $title }
    $destinationPath = Join-Path -Path $Script:Config.MoviesPath -ChildPath $folderName

    Write-Log -Message "Film erkannt: $folderName :: $($Metadata.Description)" -Level 'INFO'

    if ($Item.PSIsContainer) {
        if (Test-Path -LiteralPath $destinationPath) {
            $message = if ($DryRun) {
                "[DryRun] Filmordner bereits vorhanden – würde übersprungen: $destinationPath"
            }
            else {
                "Filmordner übersprungen (bereits vorhanden): $destinationPath"
            }

            Write-Log -Message $message -Level 'INFO'
            return
        }

        Move-DirectorySafe -Source $Item -DestinationPath $destinationPath -DryRun:$DryRun -AutoYes:$AutoYes
    }
    else {
        $targetFolder = Ensure-Directory -Path $destinationPath
        $destination = Join-Path -Path $targetFolder -ChildPath $Item.Name
        Move-ItemSafe -Source $Item -DestinationPath $destination -DryRun:$DryRun -AutoYes:$AutoYes
    }
}

#endregion Verarbeitung ------------------------------------------------------------------

#region Kernlogik -------------------------------------------------------------------------

function Determine-MediaMetadata {
    <#
        .SYNOPSIS
        Kombiniert TMDb- und lokale Erkennung zu einem Ergebnisobjekt.
    #>
    param(
        [Parameter(Mandatory)]
        [System.IO.FileSystemInfo]$Item
    )

    $metadata = Resolve-MediaUsingTmdb -Item $Item
    if ($metadata) {
        return $metadata
    }

    return Determine-MediaLocally -Item $Item
}

function Process-MediaItem {
    <#
        .SYNOPSIS
        Verarbeitet einen Eintrag aus dem Quellordner basierend auf den Metadaten.
    #>
    param(
        [Parameter(Mandatory)]
        [System.IO.FileSystemInfo]$Item,

        [bool]$DryRun = $false,

        [bool]$AutoYes = $false
    )

    if ($Script:IgnoredExtensions -contains $Item.Extension.ToLowerInvariant()) {
        Write-Log -Message "Ignoriere Eintrag (RAR): $($Item.FullName)" -Level 'DEBUG'
        return
    }

    $metadata = Determine-MediaMetadata -Item $Item

    if (-not $metadata) {
        Write-Log -Message "Konnte Typ nicht bestimmen, überspringe: $($Item.FullName)" -Level 'WARN'
        return
    }

    switch ($metadata.Type) {
        'Series' { Handle-SeriesItem -Item $Item -Metadata $metadata -DryRun:$DryRun -AutoYes:$AutoYes }
        'Movie'  { Handle-MovieItem  -Item $Item -Metadata $metadata -DryRun:$DryRun -AutoYes:$AutoYes }
        Default  { Write-Log -Message "Unbekannter Metadatentyp, überspringe: $($Item.FullName)" -Level 'WARN' }
    }
}

function Execute-MediaSort {
    <#
        .SYNOPSIS
        Führt die Sortierung für alle Elemente des Quellordners aus.
    #>
    param(
        [bool]$DryRun = $false,

        [bool]$AutoYes = $false
    )

    if (-not (Test-Path -LiteralPath $Script:Config.SourcePath)) {
        Write-Log -Message "Quellordner existiert nicht: $($Script:Config.SourcePath)" -Level 'ERROR'
        return
    }

    $items = Get-ChildItem -LiteralPath $Script:Config.SourcePath -Force
    if (-not $items) {
        Write-Log -Message 'Keine Elemente im Quellordner gefunden.' -Level 'INFO'
        return
    }

    foreach ($item in $items) {
        Process-MediaItem -Item $item -DryRun:$DryRun -AutoYes:$AutoYes
    }

    Write-Log -Message 'Verarbeitung abgeschlossen.' -Level 'INFO'
}

#endregion Kernlogik ---------------------------------------------------------------------

#region Menüsystem ------------------------------------------------------------------------

function Show-Menu {
    <#
        .SYNOPSIS
        Zeigt das Hauptmenü an und gibt die Auswahl zurück.
    #>
    Write-Host ''
    Write-Host '==========================================' -ForegroundColor DarkCyan
    Write-Host ' MediaSorter - Hauptmenü' -ForegroundColor Cyan
    Write-Host '==========================================' -ForegroundColor DarkCyan
    Write-Host ''
    Write-Host "Quellordner : $($Script:Config.SourcePath)"
    Write-Host "Filme       : $($Script:Config.MoviesPath)"
    Write-Host "Serien      : $($Script:Config.ShowsPath)"
    Write-Host "TMDb-Modus  : $(if ($Script:Config.UseTMDb) { 'Aktiv' } else { 'Deaktiviert' })"
    Write-Host ''
    Write-Host '1) Dry Run (nur anzeigen)'
    Write-Host '2) Normaler Lauf (Konflikte nachfragen)'
    Write-Host '3) AutoYes Lauf (Konflikte automatisch bestätigen)'
    Write-Host '4) Pfade ändern'
    Write-Host '5) Logdatei öffnen'
    Write-Host '6) TMDb-Modus umschalten'
    Write-Host '0) Beenden'
    Write-Host ''

    $choice = Read-Host 'Auswahl'
    return $choice
}

function Update-Paths {
    <#
        .SYNOPSIS
        Ermöglicht dem Benutzer, Quell- und Zielpfade anzupassen.
    #>
    Write-Host ''
    Write-Host '--- Pfade konfigurieren ---' -ForegroundColor Cyan

    $newSource = Read-Host "Neuer Quellordner [`$($Script:Config.SourcePath)`]"
    if (-not [string]::IsNullOrWhiteSpace($newSource)) {
        $Script:Config.SourcePath = $newSource.Trim()
    }

    $newMovies = Read-Host "Neuer Filmordner [`$($Script:Config.MoviesPath)`]"
    if (-not [string]::IsNullOrWhiteSpace($newMovies)) {
        $Script:Config.MoviesPath = $newMovies.Trim()
    }

    $newShows = Read-Host "Neuer Serienordner [`$($Script:Config.ShowsPath)`]"
    if (-not [string]::IsNullOrWhiteSpace($newShows)) {
        $Script:Config.ShowsPath = $newShows.Trim()
    }

    Save-Config
}

function Open-LogFile {
    <#
        .SYNOPSIS
        Öffnet die Logdatei im Standardeditor (Notepad).
    #>
    if (-not (Test-Path -LiteralPath $Script:LogFile)) {
        Write-Log -Message 'Logdatei existiert noch nicht.' -Level 'INFO'
        return
    }

    try {
        Start-Process -FilePath 'notepad.exe' -ArgumentList $Script:LogFile
    }
    catch {
        Write-Log -Message "Konnte Logdatei nicht öffnen: $_" -Level 'ERROR'
    }
}

function Toggle-TmdbMode {
    <#
        .SYNOPSIS
        Schaltet den TMDb-Modus um und speichert die Konfiguration.
    #>
    $Script:Config.UseTMDb = -not $Script:Config.UseTMDb
    if ($Script:Config.UseTMDb) {
        Load-TmdbApiKey
        if (-not $Script:TmdbApiKey) {
            Prompt-TmdbApiKey
        }
    }
    Save-Config
    Write-Log -Message "TMDb-Modus ist nun: $(if ($Script:Config.UseTMDb) { 'Aktiv' } else { 'Deaktiviert' })" -Level 'INFO'
}

function Run-MenuLoop {
    <#
        .SYNOPSIS
        Führt das Menü so lange aus, bis der Benutzer beendet.
    #>
    do {
        $choice = Show-Menu
        switch ($choice) {
            '1' { Execute-MediaSort -DryRun:$true  -AutoYes:$false }
            '2' { Execute-MediaSort -DryRun:$false -AutoYes:$false }
            '3' { Execute-MediaSort -DryRun:$false -AutoYes:$true  }
            '4' { Update-Paths }
            '5' { Open-LogFile }
            '6' { Toggle-TmdbMode }
            '0' { Write-Host 'Beende MediaSorter...' -ForegroundColor Cyan }
            Default { Write-Host 'Ungültige Auswahl, bitte erneut versuchen.' -ForegroundColor Yellow }
        }
    } while ($choice -ne '0')
}

#endregion Menüsystem ---------------------------------------------------------------------

#region Startlogik ------------------------------------------------------------------------

function Detect-DoubleClickLaunch {
    <#
        .SYNOPSIS
        Versucht zu erkennen, ob das Skript per Doppelklick (Explorer) gestartet wurde.
    #>
    try {
        $current = Get-CimInstance Win32_Process -Filter "ProcessId=$PID"
        if ($current) {
            $parent = Get-CimInstance Win32_Process -Filter "ProcessId=$($current.ParentProcessId)"
            if ($parent -and $parent.Name -match 'explorer') {
                return $true
            }
        }
    }
    catch {
        Write-Log -Message "Konnte Startmodus nicht ermitteln: $_" -Level 'DEBUG'
    }

    return $false
}

function Initialize-MediaSorter {
    <#
        .SYNOPSIS
        Führt alle Initialisierungsschritte aus.
    #>
    if (-not (Test-Path -LiteralPath $Script:LogFile)) {
        New-Item -ItemType File -Path $Script:LogFile -Force | Out-Null
    }

    Initialize-Config
    Load-TmdbApiKey
}

Initialize-MediaSorter
$Script:WasDoubleClicked = Detect-DoubleClickLaunch

Run-MenuLoop

if ($Script:WasDoubleClicked) {
    Write-Host ''
    Read-Host 'Skript beendet. Weiter mit Enter'
}

#endregion Startlogik --------------------------------------------------------------------
