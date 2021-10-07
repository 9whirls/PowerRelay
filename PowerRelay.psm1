Function Get-NumberOfCpu {
  return (gwmi Win32_ComputerSystem).NumberOfLogicalProcessors
}

Function Get-MemoryMB {
  return (gwmi Win32_PhysicalMemory | measure -Property Capacity -Sum).sum / 1MB
}

Function Start-RelayJob {
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
    $job = ( (Get-NumberOfCpu) - 1),
    
    [parameter(
      HelpMessage="Number of objects to be handled in a single job"
    )]
    [int] $batch = ($target.count / $job)
  )
  $total = $target.count
  
  if ($total % $batch) {
    $totaljob = [math]::floor($total / $batch) + 1
  } else {
    $totaljob = $total / $batch
  }

  $prop = [ordered]@{
    TotalObjects = $total
    ObjectsInOneJob = $batch
    TotalJobs = $totaljob
    ConcurrentJob = $job
  } 
  
  $info = New-Object PSObject -Property $prop
  $info | ft | out-string | write-verbose

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
  "Execution ends at $endTime" | write-verbose
  
  $duration = $endTime - $startTime
  $TotalAvailableCPUTime = [math]::round($duration.totalseconds * (Get-NumberOfCpu), 2)
  $TotalUsedCPUTime = [math]::round(($childProc | measure-object -sum cpu).sum, 2)
  $CPUUsage = [math]::round($TotalUsedCPUTime / $TotalAvailableCPUTime * 100, 2)
  $TotalMemory = Get-MemoryMB
  $TotalUsedMemory = [math]::round(($childProc | measure-object -sum workingset).sum / 1MB, 2)
  $MemoryUsage = [math]::round($TotalUsedMemory / $TotalMemory * 100, 2)
  
  $prop += [ordered]@{
    'TotalExecTime    (s)' = $duration.totalseconds
    'TotalCPUTime     (s)' = $TotalAvailableCPUTime
    'TotalUsedCPUTime (s)' = $TotalUsedCPUTime
    'CpuUsage         (%)' = $CPUUsage
    'TotalMemory     (MB)' = $TotalMemory
    'TotalUsedMemory (MB)' = $TotalUsedMemory
    'MemoryUsage      (%)' = $MemoryUsage
  }

  $info = New-Object PSObject -Property $prop
  $info | fl | out-string | write-verbose
}
