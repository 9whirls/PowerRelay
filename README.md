# PowerRelay
Run relay jobs, parallel and sequential combined together, in Powershell

To install this module from PSGallery, run the command below
```
Install-Module -Name PowerRelay
```

Motivation
===============
It's common to handle a large number of objects in a Powershell script. It is also usually very very time consuming. Let's have a look at the following example. The `$work` variable is a script block which does one simple job which is to retrieve all DLL files in C:\Windows\System32. Though super easy, it does require some time to run, especially on my outdated laptop at home.
```
$work = { gci c:\windows\system32\*.dll -recurse -ea silentlycontinue }
(1..10) | % { icm $work }
```
It takes almost 3 minutes to repeat the same work for totally 10 times in line. This is too annoying. I definitely want to make it run faster. And the solution looks obvious. That is to do the job in parallel but not in line.

Investigation
===============
Powershell provides 2 builtin methods for running tasks in parallel, `Start-Job` and `Foreach -Parallel` of Workflow. Let's see how they look like respectively.
```
(1..10) | % {
  start-job $work
}
while (get-job -hasmoredata $true) { get-job | receive-job }
get-job | remove-job

workflow test-workflow10 {
  param($work)
  foreach -parallel -throttlelimit 10 ($d in (1..10))
  {
    InlineScript {
      $s = [scriptblock]::create($using:work)
      icm $s
    }
  }
}
test-workflow10 $work
```
Both methods shorten the execution time to about 1 minute, Start-Job is slightly better than Workflow. Not ideal but already improved a lot. Although they look of similar efficiency, there is a significant difference.

`Start-Job` literally creates 10 concurrent Powershell processes to run the job. While Workflow only creates 6 processes on my laptop despite I define `-throttlelimit 10`. Based on my observation, the number won't go up no matter what value I give to `throttlelimit`. I suspect that Microsoft adds some protect here to prevent CPU over-commit. But it also make users unable to control how many CPU they want to utilize. I believe that's also why it's a bit slower than Start-Job. Start-Job wins +1 here.

Now, let's have more fun by increasing the total number of `$work` to 100.
```
(1..100) | % {
  start-job $work
}
while (get-job -hasmoredata $true) { get-job | receive-job }
get-job | remove-job

workflow test-workflow100 {
  param($work)
  foreach -parallel -throttlelimit 10 ($d in (1..100))
  {
    InlineScript {
      $s = [scriptblock]::create($using:work)
      icm $s
    }
  }
}
test-workflow100 $work
```
This time `Start-Job` creates 100 concurrent Powershell processes which eventually causes my laptop out of memory. On the other side, `Workflow` still runs the heavy load steadily with 6 concurrent processes and uses a moderate amount of memory. In fact neither one does what I expect. What I need is a way to keep the machine running with the highest computing power to get the job done ASAP. 

Solution
===============
The ideal method should not only allow customizing the total number of concurrent jobs, but also allow customizing the amount of workload in a job.

For instance, let's say I have 10000 objects to handle. I want limit the concurrent jobs to 20 and limit number of objects per job to 100. So I totally need 100 (10000 / 100) jobs. Instead of making 100 jobs up and running together, I start 20 jobs initially and then monitor their status. Whenever a job completes, output its result and start a new job to keep 20 running jobs till no more new job is required. The whole procedure is like a relay race.

This project, PowerRelay, is a simple Powershell function supporting this logic.

Example
==============
```
# A simple example
$script = { (1..$($args[0].count)) | % { gci c:\windows\system32\a*.exe -ea silentlycontinue } }
Start-RelayJob -target (1..10) -script $script -batch 3 -job 5 -verbose

# Another example
$dll = gci c:\windows\system32\*.dll -ea silentlycontinue | select fullname
$script = { get-filehash $args[0].fullname }
Start-RelayJob -target $dll -script $script -batch 1000 -verbose
```
