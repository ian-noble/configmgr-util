$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
. "$here\$sut"

Describe "Wait-FileContent" {
    It "It waits for one or more regex patterns to appear in a file and supports file rotation." {
        $path = "$here\tests\assets\sample-data\log.log"
        $search = @{'FinalRelease' = 'Completed'}
        $scriptblock = [scriptblock]::Create('$null = Add-Content $path "FinalRelease"')
        Wait-FileContent -path $path -regexpatterns $search -script $scriptblock | Should Be 'Completed'
    }
}
