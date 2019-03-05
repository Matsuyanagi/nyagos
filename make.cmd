@set args=%*
@powershell "iex((@('')*3+(cat '%~f0'|select -skip 3))-join[char]10)"
@exit /b %ERRORLEVEL%

$args = @( ([regex]'"([^"]*)"').Replace($env:args,{
        $args[0].Groups[1] -replace " ",[char]1
    }) -split " " | ForEach-Object{ $_ -replace [char]1," " })

Set-PSDebug -strict
$VerbosePreference = "Continue"
$env:GO111MODULE="on"
Write-Verbose "$ set GO111MODULE=$env:GO111MODULE"

function Do-Copy($src,$dst){
    Write-Verbose "$ copy '$src' '$dst'"
    Copy-Item $src $dst
}

function Do-Rename($old,$new){
    Write-Verbose "$ ren $old $new"
    Rename-Item -path $old -newname $new
}

function Do-Remove($file){
    if( Test-Path $file ){
        Write-Verbose "$ del '$file'"
        Remove-Item $file
    }
}

function Make-Dir($folder){
    if( -not (Test-Path $folder) ){
        Write-Verbose "$ mkdir '$folder'"
        New-Item $folder -type directory | Out-Null
    }
}

function Ask-Copy($src,$dst){
    $fname = (Join-Path $dst (Split-Path $src -Leaf))
    if( Test-Path $fname ){
        Write-Verbose "$fname already exists. Cancel to copy"
    }else{
        Do-Copy $src $dst
    }
}

function ForEach-GoDir{
    Get-ChildItem . -Recurse |
    Where-Object{ $_.Extension -eq '.go' } |
    ForEach-Object{ Split-Path $_.FullName -Parent } |
    Sort-Object |
    Get-Unique
}

function Go-Fmt{
    $status = $true
    git status -s | %{
        $fname = $_.Substring(3)
        $arrow = $fname.IndexOf(" -> ")
        if( $arrow -ge 0 ){
            $fname = $fname.Substring($arrow+4)
        }
        if( $fname -like "*.go" -and (Test-Path($fname)) ){
            $prop = Get-ItemProperty($fname)
            if( $prop.Mode -like "?a*" ){
                Write-Verbose "$ go fmt $fname"
                go fmt $fname
                if( $LastExitCode -ne 0 ){
                    $status = $false
                }else{
                    attrib -a $fname
                }
            }
        }
    }
    if( -not $status ){
        Write-Warning "Some of 'go fmt' failed."
    }
    return $status
}

function Make-SysO($version) {
    $exepath = (Download-Exe "github.com/josephspurrier/goversioninfo/cmd/goversioninfo")
    Write-Verbose "Use $exepath"
    if( $version -match "^\d+[\._]\d+[\._]\d+[\._]\d+$" ){
        $v = $version.Split("[\._]")
    }else{
        $v = @(0,0,0,0)
        if( $version -eq $null -or $version -eq "" ){
            $version = "0.0.0_0"
        }
    }
    Write-Verbose "version=$version"

    & $exepath `
        "-file-version=$version" `
        "-product-version=$version" `
        "-icon=Etc\nyagos.ico" `
        ("-ver-major=" + $v[0]) `
        ("-ver-minor=" + $v[1]) `
        ("-ver-patch=" + $v[2]) `
        ("-ver-build=" + $v[3]) `
        ("-product-ver-major=" + $v[0]) `
        ("-product-ver-minor=" + $v[1]) `
        ("-product-ver-patch=" + $v[2]) `
        ("-product-ver-build=" + $v[3]) `
        "-o" nyagos.syso `
        Etc\versioninfo.json
}


function Download-Exe($url){
    $exename = $url.Split("/")[-1] + ".exe"
    $gobin = (Join-Path (go env GOPATH).Split(";")[0] "bin")
    Make-Dir $gobin
    $exepath = (Join-Path $gobin $exename)

    if( Test-Path $exepath ){
        Write-Verbose "Found $exepath"
        return $exepath
    }
    Write-Verbose "$exename not found."
    $private:GO111MODULE = $env:GO111MODULE
    $env:GO111MODULE = "off"
    Write-Verbose "$ go get $url"
    go get $url
    $env:GO111MODULE = $private:GO111MODULE
    return $exepath
}

function Build([string]$version="",[string]$tags="",[string]$target="") {
    if( $version -eq "" ){
        $version = (git describe --tags)
    }

    Write-Verbose "Build as version='$version' tags='$tags'"

    if( $tags -ne "" ){
        $tags = "-tags=$tags"
    }

    if( -not (Go-Fmt) ){
        return
    }
    $saveGOARCH = $env:GOARCH
    $env:GOARCH = (go env GOARCH)

    Make-Dir "cmd"
    $binDir = (Join-Path "cmd" $env:GOARCH)
    Make-Dir $binDir
    if ($target -eq "") {
        $target = (Join-Path $binDir "nyagos.exe")
    }

    Make-SysO $version

    Write-Verbose "$ go build -o '$target'"
    go build "-o" $target -ldflags "-s -w -X main.version=$version" $tags
    if( $LastExitCode -eq 0 ){
        Do-Copy $target (Join-Path "." ([System.IO.Path]::GetFileName($target)))
    }
    $env:GOARCH = $saveGOARCH
}

function Make-Package($arch){
    $zipname = ("nyagos-{0}.zip" -f (& "cmd\$arch\nyagos.exe" --show-version-only))
    Write-Verbose "$ zip -9 $zipname ...."
    if( Test-Path $zipname ){
        Do-Remove $zipname
    }
    zip -9j $zipname `
        "cmd\$arch\nyagos.exe" `
        .nyagos `
        _nyagos `
        makeicon.cmd `
        LICENSE `
        readme_ja.md `
        readme.md

    zip -9 $zipname `
        nyagos.d\*.lua `
        nyagos.d\catalog\*.lua `
        Doc\*.md
}

switch( $args[0] ){
    "" {
        Build
    }
    "386"{
        $private:save = $env:GOARCH
        $env:GOARCH = "386"
        Build
        $env:GOARCH = $save
    }
    "debug" {
        $private:save = $env:GOARCH
        if( $args[1] ){
            $env:GOARCH = $args[1]
        }
        Build -tags "debug"
        $env:GOARCH = $save
    }
    "vanilla" {
        Build -tags "vanilla"
    }
    "release" {
        $private:save = $env:GOARCH
        if( $args[1] ){
            $env:GOARCH = $args[1]
        }
        Build -version (Get-Content Etc\version.txt)
        $env:GOARCH = $save
    }
    "linux" {
        $private:os = $env:GOOS
        $private:arch = $env:GOARCH
        $env:GOOS="linux"
        $env:GOARCH="amd64"
        Build -target "Cmd\linux\nyagos" -version (Get-Content Etc\version.txt)
        $env:GOOS = $os
        $env:GOARCH=$arch
    }
    "clean" {
        foreach( $p in @(`
            "cmd\amd64\nyagos.exe",`
            "cmd\386\nyagos.exe",`
            "nyagos.exe",`
            "nyagos.syso",`
            "version.now",`
            "goversioninfo.exe") )
        {
            Do-Remove $p
        }
        ForEach-GoDir | %{
            Write-Verbose "$ go clean on $_"
            pushd $_
            go clean
            popd
        }
    }
    "package" {
        $private:ARCH = (go env GOARCH)
        $private:VER = (Get-Content Etc\version.txt)
        if( $args[1] -eq "linux" ){
            pushd ..
            tar -zcvf "nyagos/nyagos-$VER-linux-$ARCH.tar.gz" `
                nyagos/nyagos `
                nyagos/.nyagos `
                nyagos/_nyagos `
                nyagos/readme.md `
                nyagos/readme_ja.md `
                nyagos/nyagos.d `
                nyagos/Doc/*.md
            popd
        }else{
            Make-Package $ARCH
        }
    }
    "install" {
        $installDir = $args[1]
        if( $installDir -eq $null -or $installDir -eq "" ){
            $installDir = (
                Select-String 'INSTALLDIR=([^\)"]+)' Etc\version.cmd |
                ForEach-Object{ $_.Matches[0].Groups[1].Value }
            )
            if( -not $installDir ){
                Write-Warning "Usage: make.ps1 install INSTALLDIR"
                exit
            }
            if( -not (Test-Path $installDir) ){
                Write-Warning "$installDir not found."
                exit
            }
            Write-Verbose "installDir=$installDir"
        }
        Write-Output "@set `"INSTALLDIR=$installDir`"" |
            Out-File "Etc\version.cmd" -Encoding Default

        robocopy nyagos.d (Join-Path $installDir "nyagos.d") /E
        Write-Verbose "ERRORLEVEL=$LastExitCode"
        if( $LastExitCode -lt 8 ){
            Remove-Item Variable:LastExitCode
        }
        Ask-Copy "_nyagos" $installDir
        try{
            Do-Copy nyagos.exe $installDir
        }catch{
            $now = (Get-Date -Format "yyyyMMddHHmmss")
            try{
                $old = (Join-Path $installDir "nyagos.exe")
                Do-Rename $old ($old + "-" + $now)
                Do-Copy nyagos.exe $installDir
            }catch{
                Write-Host "Could not update installed nyagos.exe"
                Write-Host "Some processes holds nyagos.exe now"
            }
        }
    }
    "get" {
        go get -u
    }
    "fmt" {
        Go-Fmt | Out-Null
    }
    "help" {
        Write-Output @'
make                     build as snapshot
make debug   [386|amd64] build as debug version     (tagged as `debug`)
make release [386|amd64] build as release version
make clean               remove all work files
make package [386|amd64] make `nyagos-(VERSION)-(ARCH).zip`
make install [FOLDER]    copy executables to FOLDER or last folder
make fmt                 `go fmt`
make help                show this
'@
    }
    default {
        Write-Warning ("{0} not supported." -f $args[0])
    }
}
if( Test-Path Variable:LastExitCode ){
    exit $LastExitCode
}

# vim:set ft=ps1:
