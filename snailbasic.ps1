param(
    [Parameter(Mandatory=$true,ValueFromPipeline=$true,Position=0)][Alias("src","f")][String]$file,
    [Parameter(Mandatory=$false,Position=1)][Alias("out","o")][String]$outfile = "out",
    [Alias("nofile","p")][switch]$stdout,
    [Alias("notape")][switch]$noheader
)

if (-not (Test-Path $file -PathType Leaf))
{
    Write-Error "$file not found"
} else
{
    [String[]]$program = Get-Content $file     
}

if($program.Length -eq 1)
{
    $program = $program -split "`n"
}

[int]$LabelCount = ($program -match "^@\d+").Count + 1
[string]$Output = ""
[System.Collections.Queue]$IfClosure = [System.Collections.Queue]::new()
[int]$PendingIfs = 0

$Output += "_$=`"`""

$program | ForEach-Object {
    $Line = $_ -replace "[';].*",""
    $Line = $Line.Trim()

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
            $Output += "@_" + "_"*$LabelCount
            $IfClosure.Enqueue(("@" + "_"*$LabelCount))
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
            #call numeric optimizer on ints
            $Expression = [regex]::Replace($Expression,"[1-9][0-9]*",{
                param($match)return "(" + (Convert-IntToShiftForm ([int]::Parse($match.ToString()))) + ")" 
                })
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


#
#Supporting Functions
#

#Checks if a colon separator is needed after the last statement and returns the string necessary
function Check-Separator(){if($Output[$Output.Length-1] -eq "_") {return ":"}else{return ""}}

#Reduce the size of numeric literals by using bit shifts
function Convert-IntToShiftForm
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True,Position=1,ValueFromPipeline=$true)][int]$n
    )

    #negatives should be inverse of the positive.
    [bool]$isNegative = $false

    if ($n -ge 0)
    {
        [string]$ResultString = ""
    } 
    else
    {
        [string]$ResultString = "-("
        $n = [Math]::Abs($n)
        $isNegative = $True
    }


    if ($n -eq 0)
    { #special 0 case
        $ResultString = "."
    } 
    else
    { #loop through an int32
        for ([int]$BitIndex = 0; $BitIndex -lt 32; $BitIndex++)
        {
            [int]$Repeats = 0
            # find groups of three bits
            while ($n -band (1 -shl $BitIndex) -and $BitIndex -lt 32)
            {
                $Repeats++;$BitIndex++
            }

            if ($BitIndex -eq $Repeats -and $Repeats -ne 0 -and $Repeats -le 3)
            {
                $ResultString += [string](1 -shl $Repeats) - 1
            } 
            elseif ($Repeats -gt 0 -and $Repeats -le 3)
            {
                $group = [string](1 -shl $Repeats) - 1
                $position = $BitIndex - $Repeats
                $ResultString += "+($group<<$position)"
            } 
            elseif ($Repeats -gt 3)
            {
                $position = $BitIndex - $Repeats
                $ResultString += "+((1<<$Repeats)-1<<$position)"
            }
        }
    }

    # remove leading +
    $ResultString = [regex]::Replace($ResultString,"^\+","")
    # typical snailbasic conversions
    $ResultString = [regex]::Replace($ResultString,"[1-9][0-9]*",{param($match)return "!."+"+!."*([int]::Parse($match.ToString()) - 1) })
    $ResultString = [regex]::Replace($ResultString,"0",".")
    
    if ($isNegative -eq $True)
    {
        $ResultString += ")"
        $n = -$n
    }

    $PowershellVerifiable = [scriptblock]::Create(($ResultString -replace '!\.','1' -replace '\.','0' -replace '<<','-shl'))
    $ResultValue = (Invoke-Command $PowershellVerifiable)
    if ($n -ne $ResultValue)
    {
        Write-Error "Conversion failed: $n != $ResultValue : $ResultString"
    }

    $Difference = [Math]::Abs(($n*3 - 1)) - [Math]::Abs($ResultString.Length)
    if ($Difference -ge 0)
    {
        Write-Verbose "Optimized construction SUCCESS"
        Write-Verbose "$n beat standard construction by $Difference"
    }
    else
    {
        Write-Debug "$n optimization failed"
        Write-Verbose "Standard construction wins by $Difference"
    }
    return $ResultString
}

function Test-Optimization([int]$n = 512)
{

    for ($BitIndex = 0; $BitIndex -lt $n; $BitIndex++)
    {
        Convert-IntToShiftForm $BitIndex -Verbose
    }
}
