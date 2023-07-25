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

if ($downloadedFile) {
    # Erstellen des Extraktionsverzeichnisses, falls es nicht existiert
    if (-not (Test-Path -Path $extractedPath)) {
        New-Item -ItemType Directory -Path $extractedPath | Out-Null
    }

    # Extrahieren der heruntergeladenen Datei und verschieben der json-Datei
    Write-Host -NoNewline -ForegroundColor DarkGreen "Entpacken der heruntergeladenen Datei... "
    try {
        tar -xzf $downloadedFile.FullName -C $extractedPath adlist.json whitelist.exact.json
        Move-Item $localPath\uniqueDomains.json $extractedPath -Force
        Write-Host "OK"
    } catch {
        # Fehlerbehandlung, falls ein Fehler auftritt
        Write-Host $_.Exception.Message
    }

    # Löschen der ursprünglichen Datei
    Write-Host -NoNewline -ForegroundColor DarkGreen "Löschen der ursprünglichen Datei... "
    try {
        Remove-Item -Path $downloadedFile.FullName -Force
        Write-Host "OK"
    } catch {
        # Fehlerbehandlung, falls ein Fehler auftritt
        Write-Host $_.Exception.Message
    }

    # Jsonfile einlesen
    $jsonAdlist  = Get-Content -Path $extractedPath\adlist.json -Raw | ConvertFrom-Json

    # Listen erfassen, die 0 Domains haben und mit Invoke-WebRequest Domains zählen
    $zeroDomains = $jsonAdlist | Where-Object {$_.number -eq 0} | Select-Object -Property id,address

    # Aktuelle Liste 
    $step = 1

    Write-Host -ForegroundColor DarkGreen "Fehlerhafte AdLists: Domains nachträglich zählen... "

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
            Write-Host ("{0:D2}" -f$step + "/" + $zeroDomains.Count)  "AdList aktualisiert: $($targetObject.Number) Domains"
        } else {
            Write-Host "ID $($list.id) wurde nicht im JSON-Objekt gefunden."
        }

        $step++
    }

    # Initialisiere eine Variable zur Speicherung der Gesamtsumme der gesamten Anzahl der Domains (inkl. Redundanz)
    $domainsTotal = 0

    # Iteriere durch jedes JSON-Element und summiere die "Numbers"
    $jsonAdlist | ForEach-Object { $domainsTotal += $_.Number }

    # Unique Doamins aus json-File
    $uniqueDoamins = ((ConvertFrom-Json(Get-Content -Path $extractedPath\uniqueDomains.json -Raw)).domains_being_blocked).ToString("N0")

    # Sortiere das Array nach der Eigenschaft "comment" und dann nach der Anzahl absteigend
    $sortedAdlists = $jsonAdlist | Sort-Object -Property comment, number -Descending

    # Gruppiere das sortierte Array nach der Eigenschaft "comment" und führe die erste Sortierung durch
    $groupedAdlists = $sortedAdlists | Group-Object -Property comment | Sort-Object -Property Count -Descending

    $countAdlists = ($groupedAdlists | Measure-Object -Property Count -Sum).Sum
    $countCategories = $groupedAdlists.Count

    # Blocklist Readme.md erstellen
     $output = "# Pihole Blocklisten`n"
    $output += "zuletzt aktualisiert: $(Get-Date -Format "dd.MM.yyyy 'at' HH:mm")`n`n"
    $output += "$($domainsTotal.ToString("N0")) Domains ($($uniqueDoamins) Unique) in $($countAdlists) AdListen in $($countCategories) Kategorien.`n"
    $output += ">*Eigene Sammlung, großteils von [RPiList](https://github.com/RPiList/specials/blob/master/Blocklisten.md) (YT: [SemperVideo](https://www.youtube.com/@SemperVideo)) - Vielen Dank*"

    # Gib die sortierten Gruppen aus
    foreach ($group in $groupedAdlists) {

        $sortedGroup = $group.Group | Sort-Object -Property number -Descending
        $countDomains = ($sortedGroup | Measure-Object -Property number -Sum).Sum.ToString("N0")

        $output += "`n"
        $output += "## $($group.Name)`n"
        $output += "> $($group.Group.Count) $(If ($group.Group.Count -eq 1) { 'Liste' } Else { 'Listen' }) mit $($countDomains) Domains - [Copy & Paste Link](https://raw.githubusercontent.com/ErikSlevin/blocklists/blocklists)`n`n"
        $output += "|Domains|Adresse|`n"
        $output += "|--:|:--|"
        
        foreach ($adlist in $sortedGroup ) {
            if ($adlist.address.Length -gt 80) {
                $beschreibung = $adlist.address.Substring(0, 77) + "..."
            } else {
                $beschreibung = $adlist.address
            }

            $output += "`n|$($adlist.number.ToString("N0"))|[$beschreibung]($($adlist.address))|"
        }

    }
    $output | Out-File $env:USERPROFILE\Documents\GitHub\blocklists\README.md -Encoding UTF8
}

#    $title = "BLOCKLISTS INFO"
#    $headerBlock = @"
##
##  $title
##
##  Release Date: $(Get-Date -Format "dd.MM.yyyy 'at' HH:mm")
##
##  Total Domains: $($DomainsTotal.ToString("N0")) ($uniqueDoamins Unique) 
##  Total Adlists: $($jsonAdlist.Count)
##  Categories: $($groupedAdlists.Count)
##
##  GitHub: https://github.com/ErikSlevin
##  Repository: https://github.com/ErikSlevin/blocklists
##
##  Copyright (c) $(Get-Date -Format 'yyyy') Erik Slevin
##
#"@
#Clear-Host

#}
