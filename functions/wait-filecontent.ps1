#requires -version 3.0
function Wait-FileContent
{
    <#
            .SYNOPSIS
            Wait for content to appear in a file.
            .DESCRIPTION
            Supports file rollover, either by checking if the file content has reduced in
            size, or if files exist that match format originalfile-*.originalextension with a
            last write time later than when the routine last checked that file. e.g. if file
            was log.log, it would look for files matching log-*.log.
            -match is used for the comparision.
            .PARAMETER Path
            Path to file.
            .PARAMETER RegExPatterns
            Content to watch for in the file, One or more RegEx expressions in a hash table
            (multiple regex expressions supported).
            .PARAMETER Timeout
            How long to monitor the file before timing out. Default 15 minutes.
            .PARAMETER Script
            Script block to run prior to starting monitoring the file.
            .PARAMETER ScanInterval
            Time to pause in between file scans, in milliseconds. Default 500ms.
            .EXAMPLE
            $path = "$env:windir\ccm\logs\PolicyAgent.log"
            $RegExPatterns = @{
                'instance of CCM_PolicyAgent_AssignmentsRequested' = 'Completed'
                'Evaluation not required' = 'Not required'
            }
            $script = [scriptblock]::Create('$null = Invoke-WmiMethod -Namespace root\CCM -Class SMS_Client -Name TriggerSchedule "{00000000-0000-0000-0000-000000000021}"')

            Wait-FileContent -Path $path -RegExPatterns $RegExPatterns -Script $script -timeout 15
    #>
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path,

        [Parameter(Mandatory = $true, Position = 1)]
        [Hashtable]$RegExPatterns,

        [Parameter(Mandatory = $false, Position = 2)]
        [TimeSpan]$TimeOut = (New-TimeSpan -Minutes 15),

        [Parameter(Mandatory = $false, Position = 3)]
        [ScriptBlock]$ScriptBlock,

        [Parameter(Mandatory = $false, Position = 4)]
        [int32]$ScanInterval = 500
    )

    $FileJustRotated = $false
    $LastFilePos = 0
    $RotateTime = $StartTime = Get-Date

    # If the file already exists, get the current end of file position prior to running the script block.
    if (test-path -LiteralPath $Path)
    {
        $Reader = New-Object -TypeName System.IO.StreamReader -ArgumentList (New-Object -TypeName IO.FileStream -ArgumentList ($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([IO.FileShare]::Delete, ([IO.FileShare]::ReadWrite))))
        $LastFilePos = $Reader.BaseStream.Length
        $Reader.Close()
        $LastFileCreateTime = (Get-Item $Path).CreationTime
    }

    # Run the script.
    if ($ScriptBlock)
    {
        & $ScriptBlock
    }

    :Loop while ($true)
    {  
        if ((Get-Date) - $StartTime -ge $TimeOut)
        {
            'Timed Out'
            break
        }
        
        Start-Sleep -Milliseconds $ScanInterval

        # Does the file still exist?
        if (-not (test-path -LiteralPath $Path -ErrorAction SilentlyContinue))
        {
            continue 
        }

        if ($LastFileCreateTime)
        {
            $CurrentFileCreateTime = (Get-Item $Path).CreationTime 
            if ($CurrentFileCreateTime -ne $LastFileCreateTime)
            {
                $FileJustRotated = $true
                write-verbose -message "File creation time changed. Will scan entire file."
            }
        }

        # Has the file changed since the last pass?
        $Reader = New-Object -TypeName System.IO.StreamReader -ArgumentList (New-Object -TypeName IO.FileStream -ArgumentList ($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([IO.FileShare]::Delete, ([IO.FileShare]::ReadWrite))))
        $FileLength = $Reader.BaseStream.Length
        $Reader.Close()
        if (($FileLength -eq $LastFilePos) -and $FileJustRotated -eq $false)
        {
            continue
        }

        if ($FileLength -lt $LastFilePos)
        {
            $FileJustRotated = $true
            write-verbose -message "File content reduced in size, file may have been rotated. Will scan entire file."
        }              
                
        $RotatedFileMatch = $Path -replace '\.', '-*.' 
        $RotatedPath = Get-ChildItem -Path $RotatedFileMatch -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -gt $RotateTime }
                
        if ($RotatedPath) 
        {
            Write-Verbose -Message "Rotated file detected: $RotatedPath, scanning it from position $LastFilePos"
                    
            $RotatedReader = New-Object -TypeName System.IO.StreamReader -ArgumentList (New-Object -TypeName IO.FileStream -ArgumentList ($RotatedPath.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([IO.FileShare]::Delete, ([IO.FileShare]::ReadWrite))))
            $null = $RotatedReader.BaseStream.Seek($LastFilePos, [System.IO.SeekOrigin]::Begin)
                
            while (($Line = $RotatedReader.ReadLine()) -ne $null)
            {
                if (-not (test-path -LiteralPath $Path -ErrorAction SilentlyContinue))
                {
                    $RotatedReader.Close()
                    write-verbose -message "File renamed, moved or deleted, may have been rotated."
                    continue
                }

                Write-Verbose -Message $Line
                foreach ($RegExPattern in $RegExPatterns.Keys)
                {
                    if ($Line -match $RegExPattern)
                    {
                        $RegExPatterns[$RegExPattern]
                        $RotatedReader.Close()
                        break Loop
                    }
                }
                
            }
            $RotatedReader.Close()
            $RotateTime = $RotatedPath.LastWriteTime
        
            write-verbose -message "Setting scan position to 0 as file was rotated."
            $LastFilePos = 0
        }
        
        if ($FileJustRotated)
        {
            write-verbose -message "Setting scan position to 0 as file rotated."
            $LastFilePos = 0
            $FileJustRotated = $false
        }
                    
        $Reader = New-Object -TypeName System.IO.StreamReader -ArgumentList (New-Object -TypeName IO.FileStream -ArgumentList ($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([IO.FileShare]::Delete, ([IO.FileShare]::ReadWrite))))
        $null = $Reader.BaseStream.Seek($LastFilePos, [System.IO.SeekOrigin]::Begin)
                        
        while (($Line = $Reader.ReadLine()) -ne $null)
        {
            if (-not (test-path -LiteralPath $Path -ErrorAction SilentlyContinue))
            {        
                $RotatedReader.Close()
                write-verbose -message "File renamed, moved or deleted, may have been rotated."
                continue
            }

            Write-Verbose -Message $Line
            foreach ($RegExPattern in $RegExPatterns.Keys)
            {
                if ($Line -match $RegExPattern)
                {
                    $RegExPatterns[$RegExPattern]
                    $Reader.Close()
                    break Loop
                }
            }
        }
        $LastFilePos = $Reader.BaseStream.Position
        $Reader.Close()
        $LastFileCreateTime = (Get-Item $Path).CreationTime
    }
}


