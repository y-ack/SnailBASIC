param(
    [Parameter(Mandatory=$true,ValueFromPipeline=$true,Position=0)][Alias("src")][String[]]$program,
    [Parameter(Mandatory=$false,Position=1)][Alias("out","o")][String]$outfile = "out",
    [Alias("nofile","p")][switch]$stdout
)

if($program.Length -eq 1)
{
    $program = $program -split "`n"
}

[int]$LabelCount = ($program -match "^@\d+").Count + 1
[string]$Output = ""
[System.Collections.Queue]$IfClosure = [System.Collections.Queue]::new()
[int]$PendingIfs = 0

$Output += "_$=`"`""

function Check-Separator(){if($Output[$Output.Length-1] -eq "_") {return ":"}else{return ""}}

$program | ForEach-Object {
    $Line = $Line -replace "[';].*",""
    $Line = $_.Trim()

    if ($IfClosure.Count -ne 0)
    {
        $PendingIfs++
    } else
    {
        $PendingIfs = 0
    }

    [string]$Instruction = [regex]::Match($_,"^[A-Za-z]+").Value.ToUpper()
    Switch ($Instruction)
    {
        "IF"
        {
            $Output += Check-Separator
            $VAR = [regex]::Match($Line,"(?<=IF )[A-Z]").Value
            $Output += "GOTO `"@" + "_"*$LabelCount + "`"+`"_`"*!!" + "_"*([byte][char]$VAR - 64)
            $Output += "@_" + "_"*$LabelCount + ":"
            $IfClosure.Enqueue(("@" + "_"*$LabelCount + ":"))
            $PendingIfs++
            $LabelCount += 2
        }
        "GOTO"
        {
            $Output += Check-Separator
            $Output += "GOTO@_" + "_"*[int]([regex]::Match($_,"\d+").Value)
        }
        "MOV"
        {
            $Output += Check-Separator
            $VAR = [regex]::Match($Line,"(?<=MOV )[A-Z]").Value
            $Output += "_"*([byte][char]$VAR - 64) + "="
            $Expression = $Line.Substring($Line.IndexOf(",")+1)
            $Expression = [regex]::Replace($Expression,"[A-Z]",{param($match)return "_"*([byte][char]$match.ToString() - 64)})
            $Expression = [regex]::Replace($Expression,"[1-9][0-9]*",{param($match)return "(!."+"+!."*([int]::Parse($match.ToString()) - 1) + ")" })
            $Expression = [regex]::Replace($Expression,"0+",{param($match)return "."})
            $Output += $Expression
        }
        "PRINT"
        {
            $VAR = [regex]::Match($Line,"(?<=PRINT )[A-Z]").Value
            $Output += "?" + "_"*([byte][char]$VAR - 64)
        }
        "SET"
        {
            $Output += Check-Separator
            $VAR = [regex]::Match($Line,"(?<=SET )[A-Z]").Value
            $Output += "GOTO `"@" + "_"*$LabelCount + "`"+`"_`"*!!_"
            $Output += "@" + "_"*$LabelCount + ":"
            $Output += "_$[" + "_"*([byte][char]$VAR - 64) + "]=`".`""
            $Output += "GOTO@__" + "_"*$LabelCount
            $Output += "@_" + "_"*$LabelCount + ":"
            $Output += "_$[" + "_"*([byte][char]$VAR - 64) + "]=`"_`""
            $Output += "@__" + "_"*$LabelCount
            $LabelCount += 3
        }
        "GET"
        {
            $Output += Check-Separator
            $VAR = [regex]::Match($Line,"(?<=GET )[A-Z]").Value
            $Output += "_=_$[" + "_"*([byte][char]$VAR - 64) + "]==`"_`""
        }
        "UNSHIFT"
        {
            $Output += Check-Separator
            $Output += "GOTO `"@" + "_"*$LabelCount + "`"+`"_`"*!!_"
            $Output += "@" + "_"*$LabelCount + ":"
            $Output += "_$=`".`"+_$"
            $Output += "GOTO@__" + "_"*$LabelCount
            $Output += "@_" + "_"*$LabelCount + ":"
            $Output += "_$=`"_`"+_$"
            $Output += "@__" + "_"*$LabelCount + ":"
            $Output += "_%=_%--!."
            $LabelCount += 3
        }
        "SHIFT"
        {
            $Output += Check-Separator
            $Output += "_=_$[.]==`"_`""
            $Output += "_$[.]=`"`""
            $Output += "_%=_%-!."
        }
        "PUSH"
        {
            $Output += Check-Separator
            $Output += "GOTO `"@" + "_"*$LabelCount + "`"+`"_`"*!!_"
            $Output += "@" + "_"*$LabelCount + ":"
            $Output += "_$=_$+`".`""
            $Output += "GOTO@__" + "_"*$LabelCount
            $Output += "@_" + "_"*$LabelCount + ":"
            $Output += "_$=_$+`"_`""
            $Output += "@__" + "_"*$LabelCount + ":"
            $Output += "_%=_%--!."
            $LabelCount += 3
        }
        "POP"
        {
            $Output += Check-Separator
            $Output += "_=_$[_%]==`"_`""
            $Output += "_$[_%]=`"`""
            $Output += "_%=_%-!."
        }
    }
    if ($Line -match "^@\d+")
    {
        $Output += "@_" + "_"*[int]([regex]::Match($_,"\d+").Value)
    }
    if ($IfClosure.Count -gt 0 -and $PendingIfs -gt 1)
    {
        $Output += $IfClosure.Dequeue()
    }
}

if ($stdout)
{
    $Output | Out-Default
} else
{
    $Output | Out-File $outfile
}
