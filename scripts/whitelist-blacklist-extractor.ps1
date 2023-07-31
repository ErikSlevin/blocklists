# SSH Verbindung
$serverName = "Docker-Pi-1"
$remotePath = "/home/erik/backup/"
$sourcePath = "$serverName`:$remotePath\{*pihole-backup.tar.gz,*.json}"

# Entpackungsverzeichnis
$localPath = "$env:USERPROFILE\Downloads"
$extractedPath = "$localPath\extracted\"

# Herunterladen der Datei mit SCP
scp $sourcePath $localPath 

# Suchen der heruntergeladenen Datei mit Wildcard
$downloadedFile = Get-ChildItem -Path $localPath -Filter "*pihole-backup.tar.gz" | Select-Object -First 1

# Schrittzahl initieren
$step = 1

# Console clearen
Clear-Host

if ($downloadedFile) {
    # Erstellen des Extraktionsverzeichnisses, falls es nicht existiert
    if (-not (Test-Path -Path $extractedPath)) {
        New-Item -ItemType Directory -Path $extractedPath | Out-Null
    }

    # Extrahieren der heruntergeladenen Datei und verschieben der json-Datei
    try {
        Write-Host -NoNewline "Schritt $($step): "
        Write-Host -NoNewline -ForegroundColor DarkGreen "Entpacken der heruntergeladenen Datei... "
        tar -xzf $downloadedFile.FullName -C $extractedPath adlist.json whitelist.exact.json
        Move-Item $localPath\uniqueDomains.json $extractedPath -Force
        Write-Host "OK"
        $step++
    } catch {
        # Fehlerbehandlung, falls ein Fehler auftritt
        Write-Host $_.Exception.Message
    }

    # Löschen der ursprünglichen Datei
    try {
        Write-Host -NoNewline "Schritt $($step): "
        Write-Host -NoNewline -ForegroundColor DarkGreen "Löschen der ursprünglichen Datei... "
        Remove-Item -Path $downloadedFile.FullName -Force
        Write-Host "OK"
        $step++
    } catch {
        # Fehlerbehandlung, falls ein Fehler auftritt
        Write-Host $_.Exception.Message
    }

    # Jsonfile einlesen
    $jsonAdlist  = Get-Content -Path $extractedPath\adlist.json -Raw | ConvertFrom-Json

    # Listen erfassen, die 0 Domains haben und mit Invoke-WebRequest Domains zählen
    $zeroDomains = $jsonAdlist | Where-Object {$_.number -eq 0} | Select-Object -Property id,address

    # Aktuelle Liste 
    $listnumber = 1

    try {
        Write-Host -NoNewline "Schritt $($step): "
        Write-Host -NoNewline -ForegroundColor DarkGreen "Fehlerhafte AdLists: Domains nachträglich zählen "

        # Initialisiere den Fortschritt
        $listnumber = 0
        $totalLists = $zeroDomains.Count
        Write-Host -NoNewline "0%"

        foreach ($list in $zeroDomains) {
            # Content Einlesen
            $fileContent = Invoke-WebRequest -Uri $list.address | Select-Object -ExpandProperty Content

            # Domains zählen
            $countDomains = ($fileContent -split '\r?\n' | Where-Object { $_ -match '^\s*(?!#|$)' }).Count

            # json PS-Objekt manipulieren 
            $targetObject = $jsonAdlist | Where-Object { $_.ID -eq $list.id}

            # Überprüfe, ob das Objekt gefunden wurde
            if ($targetObject) {
                $targetObject.Number = $countDomains
                # Write-Host ("{0:D2}" -f$$listnumber + "/" + $zeroDomains.Count)  "AdList aktualisiert: $($targetObject.Number) Domains"
            } else {
                Write-Host "ID $($list.id) wurde nicht im JSON-Objekt gefunden."
            }

            # Durchgelaufende Liste erhöhen
            $listnumber++

            # Fortschritt anzeigen für 0/20/40/60/80/100%
            if ($listnumber % ($totalLists / 5) -eq 0) {
                $progress = ($listnumber / $totalLists) * 100
                Write-Host -NoNewline "$progress%"
            } else {
                Write-Host -NoNewline "."
            }
        }
        $step++
        Write-Host "  OK"
    } catch {
        # Fehlerbehandlung, falls ein Fehler auftritt
        Write-Host $_.Exception.Message
    }

    # Initialisiere eine Variable zur Speicherung der Gesamtsumme der gesamten Anzahl der Domains (inkl. Redundanz)
    $domainsTotal = 0

    # Iteriere durch jedes JSON-Element und summiere die "Numbers"
    $jsonAdlist | ForEach-Object { $domainsTotal += $_.Number }

    # Unique Doamins aus json-File
    $uniqueDoamins = ((ConvertFrom-Json(Get-Content -Path $extractedPath\uniqueDomains.json -Raw)).domains_being_blocked).ToString("N0")

    # Sortiere das Array nach der Eigenschaft "comment" und dann nach der Anzahl absteigend
    $sortedAdlists = $jsonAdlist | Where-Object { $_.comment -notlike "Local Mirror*" } | Sort-Object -Property comment, number -Descending

    # Gruppiere das sortierte Array nach der Eigenschaft "comment" und führe die erste Sortierung durch
    $groupedAdlists = $sortedAdlists | Where-Object { $_.comment -notlike "Local Mirror*" } | Group-Object -Property comment | Sort-Object -Property Count -Descending

    # Wieviele AdListen insgesamt
    $countAdlists = ($groupedAdlists | Measure-Object -Property Count -Sum).Sum

    # Wieviele Kategorien insgesamt
    $countCategories = $groupedAdlists.Count

    # Blocklist Readme.md erstellen
    $outputREADME = "# Pihole Blocklisten`n"
    $outputREADME += "zuletzt aktualisiert: $(Get-Date -Format "dd.MM.yyyy 'at' HH:mm")`n`n"
    $outputREADME += "$($domainsTotal.ToString("N0")) Domains ($($uniqueDoamins) Unique) in $($countAdlists) AdListen in $($countCategories) Kategorien.`n"
    $outputREADME += ">*Eigene Sammlung, großteils von [RPiList](https://github.com/RPiList/specials/blob/master/Blocklisten.md) (YT: [SemperVideo](https://www.youtube.com/@SemperVideo)) - Vielen Dank*"

    # Blocklistfile HEADER
    $outputBLOCKLISTS =  "####################################################################################################`n"
    $outputBLOCKLISTS += "#### BLOCKLISTS ####################################################################################`n"
    $outputBLOCKLISTS += "#### Released: $(Get-Date -Format "dd.MM.yyyy 'at' HH:mm")`n"
    $outputBLOCKLISTS += "####`n"
    $outputBLOCKLISTS += "#### $($domainsTotal.ToString("N0")) Domains ($($uniqueDoamins) Unique) in $($countAdlists) AdListen in $($countCategories) Kategorien.`n"
    $outputBLOCKLISTS += "####`n"
    $outputBLOCKLISTS += "#### GitHub: https://github.com/ErikSlevin`n"
    $outputBLOCKLISTS += "#### Repository: https://github.com/ErikSlevin/blocklists`n"
    $outputBLOCKLISTS += "####`n"
    $outputBLOCKLISTS += "#### Copyright Erik Slevin #########################################################################`n"
    $outputBLOCKLISTS += "####################################################################################################"

    # Gib die sortierten Gruppen aus
    foreach ($group in $groupedAdlists) {

        # Liste nach Domains absteigend sortieren
        $sortedGroup = $group.Group | Sort-Object -Property number -Descending

        # Anzahl der Domains in der Liste
        $countDomains = ($sortedGroup | Measure-Object -Property number -Sum).Sum.ToString("N0")

        # Ueberschriften für die Blocklists (einheitliche Breite)
        $headline1 = "$($group.Name.Replace("&amp; ", "& ").ToUpper())"
        $paddingLength1 = 100 - $headline1.Length - 6
        $padding1 = "#" * $paddingLength1

        # Ueberschriften für die Blocklists (einheitliche Breite)
        $headline2 = "$($countDomains) Domains"
        $paddingLength2 = 100 - $headline2.Length - 6
        $padding2 = "#" * $paddingLength2

        # Gruppenueberschrift fuer die Blocklists hinzufügen
        $outputBLOCKLISTS +=  "`n`n`n#### $headline1 $padding1`n"
        $outputBLOCKLISTS +=  "#### $headline2 $padding2 `n`n"

        # Blocklist Readme.md ergänzen // Hier Kategorieweise!
        $outputREADME += "`n"
        $outputREADME += "## $($group.Name)`n"
        $copyPasteLink = "[Copy & Paste Link](/blocklists#L$(($outputBLOCKLISTS | Measure-Object -Line).Lines+1)-L$(($outputBLOCKLISTS | Measure-Object -Line).Lines+$group.count))"
        $outputREADME += "> $($group.Group.Count) $(If ($group.Group.Count -eq 1) { 'Liste' } Else { 'Listen' }) mit $($countDomains) Domains - $($copyPasteLink)`n`n"
        $outputREADME += "|Domains|Adresse|`n"
        $outputREADME += "|--:|:--|"
        
        # Blocklist Readme.md ergänzen // Hier je URL!
        foreach ($adlist in $sortedGroup ) {

            # URL kürzen wenn nötig
            $beschreibung = ($adlist.address.Length -gt 80) ? ($adlist.address.Substring(0, 77) + "...") : $adlist.address

            # URLs für die README.md hinzufuegen
            $outputREADME += "`n|$($adlist.number.ToString("N0"))|[$beschreibung]($($adlist.address))|"

            # URLS für die Blocklists hinzufuegen
            $outputBLOCKLISTS += "$($adlist.address)`n"
        }

    }

    # README.md File schreiben
    Write-Host -NoNewline "Schritt $($step): "
    Write-Host -NoNewline -ForegroundColor DarkGreen "README.md File schreiben... "
    $outputREADME | Out-File $env:USERPROFILE\Documents\GitHub\blocklists\README.md -Encoding UTF8
    Write-Host "OK"
    $step++

    # Blocklists schreiben
    Write-Host -NoNewline "Schritt $($step): "
    Write-Host -NoNewline -ForegroundColor DarkGreen "Blocklists File schreiben... "
    $outputBLOCKLISTS | Out-File $env:USERPROFILE\Documents\GitHub\blocklists\blocklists -Encoding UTF8
    Write-Host "OK"
    $step++

    # GitHub aktualisieren
    try {
        Write-Host -NoNewline "Schritt $($step): "
        Write-Host -NoNewline -ForegroundColor DarkGreen "GitHub aktualieren... "

        # Git initialisieren
        Set-Location $env:USERPROFILE\Documents\GitHub\blocklists\
        git init >$null 2>&1

        # Änderungen hinzufügen
        git add README.md blocklists >$null 2>&1

        # Commit durchführen
        git commit -m "Update blocklists and README.md" >$null 2>&1

        # Änderungen pushen
        git push origin main >$null 2>&1

        Write-Host "OK"
        $step++
    } catch {
        # Fehlerbehandlung, falls ein Fehler auftritt
        Write-Host $_.Exception.Message
    }

    # Löschen des Entpackungsverzeichnisses
    Write-Host -NoNewline "Schritt $($step): "
    Write-Host -NoNewline -ForegroundColor DarkGreen "Löschen des Entpackungsverzeichnisses... "
    try {
        if (Test-Path -Path $extractedPath) {
            Remove-Item -Path $extractedPath -Force -Recurse
            Write-Host "OK"
        } else {
            Write-Host "Verzeichnis nicht gefunden."
        }
    } catch {
        # Fehlerbehandlung, falls ein Fehler auftritt
        Write-Host $_.Exception.Message
    }
}