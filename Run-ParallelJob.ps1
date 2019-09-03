Function Get-NumberOfCpu {
  return (gwmi Win32_ComputerSystem).NumberOfProcessors
}

Function Run-ParallelJob {
  [CmdletBinding()]
  param(
    [parameter(
      Mandatory=$true,
      HelpMessage="An array of objects to handle"
    )]
    $target,
    
    [parameter(
      Mandatory=$true,
      HelpMessage="A script for handling the objects"
    )]
    $script,
    
    [parameter(
      HelpMessage="Maximum number of concurrent jobs"
    )]
    $job = ( (Get-NumberOfCpu) * 2 - 1),
    
    [parameter(
      HelpMessage="Number of objects to be handled in a single job"
    )]
    [int] $batch = ($target.count / $job)
  )
  $total = $target.count
  "Total objects to handle: $total" | write-verbose
  "Number of objects handled in a single job: $batch" | write-verbose
  if ($total % $batch) {
    $totaljob = [math]::floor($total / $batch) + 1
  } else {
    $totaljob = $total / $batch
  }
  "Total jobs to run: $totaljob" | write-verbose
  "Maximum number of concurrent jobs: $job" | write-verbose
  $startTime = get-date
  "Execution starts at $startTime" | write-verbose
  $i = 0
  $childProc = @()
  while ($i -lt $totaljob) {
    while ((get-job -state running).count -lt $job -and $i * $batch -lt $total) {
      $start = $i * $batch
      $end = ( $i + 1 ) * $batch - 1
      $end = ($end, $total | measure -minimum).minimum
      start-job -scriptblock $script -argumentlist (,$target[$start..$end]) -name "job-$i" | 
        out-null
      $i += 1  
    }
	$p = Get-WmiObject -Class win32_process -Filter "ParentProcessID = '$PID'"
	foreach ($id in $p.processid) {if ( $childProc.id -notcontains $id ) { $childProc += get-process -id $id }}
    get-job -hasmoredata $true | receive-job
  }
  while (get-job -hasmoredata $true) { get-job | receive-job }
  get-job | remove-job
  $endtime = get-date
  $duration = $endTime - $startTime
  $TotalAvailableCPUTime = [math]::round($duration.totalseconds * (Get-NumberOfCpu), 2)
  $TotalUsedCPUTime = [math]::round(($childProc | measure-object -sum cpu).sum, 2)
  $CPUEfficiency = [math]::round($TotalUsedCPUTime / $TotalAvailableCPUTime * 100, 2)
  "Execution ends at $endTime" | write-verbose
  "Total execution time $duration" | write-verbose 
  "Total availabe CPU time $TotalAvailableCPUTime seconds" | write-verbose
  "Total used CPU time $TotalUsedCPUTime seconds" | write-verbose
  "CPU efficiency $CPUEfficiency %" | write-verbose
}

# A simple example
$script = { (1..$($args[0].count)) | % { gci c:\windows\system32\a*.exe -ea silentlycontinue } }
Run-ParallelJob -target (1..10) -script $script -batch 3 -job 5 -verbose

# Another example
$dll = gci c:\windows\system32\*.dll -ea silentlycontinue | select fullname
$script = { get-filehash $args[0].fullname }
Run-ParallelJob -target $dll -script $script -batch 100 -verbose
