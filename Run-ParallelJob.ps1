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
      HelpMessage="Number of objects to be handled in a single job"
    )]
    $batch = 10,
    
    [parameter(
      HelpMessage="Maximum number of concurrent jobs"
    )]
    $job = 10
  )
  $total = $targets.count
  "Total objects to handle: $total" | write-verbose
  "Number of objects handled in a single job: $batch" | write-verbose
  if ($total % $batch) {
    $totaljob = [math]::floor($total / $batch) + 1
  } else {
    $totaljob = $total / $batch
  }
  "Total jobs to run: $totaljob" | write-verbose
  "Maximum number of concurrent jobs: $job" | write-verbose
  $i = 0
  while ($i -lt $totaljob) {
    while ((get-job -state running).count -lt $job -and $i * $batch -lt $total) {
      $start = $i * $batch + 1
      $end = ( $i + 1 ) * $batch
      $end = ($end, $total | measure -minimum).minimum
      start-job -scriptblock $script -argumentlist (,$targets[$start..$end]) -name "job-$i" | 
        out-string | write-verbose
      $i += 1
    }
    get-job -hasmoredata $true | receive-job
  }
  while (get-job -hasmoredata $true) { get-job | receive-job }
  get-job | remove-job
}

# A simple example
$script = { (1..$($args[0].count)) | % { gci c:\windows\system32\a*.exe -ea silentlycontinue } }
Run-ParallelJob -target (1..10) -script $script -batch 3 -job 5 -verbose

# Another example
$dll = gci c:\windows\system32\*.dll -ea silentlycontinue | select fullname
$script = { get-filehash $args[0].fullname }
Run-ParallelJob -target $dll -script $script -batch 100 -verbose
