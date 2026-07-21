$B="http://127.0.0.1:8000"
$ah=@{Authorization="Bearer $((Invoke-RestMethod "$B/token" -Method POST -ContentType 'application/x-www-form-urlencoded' -Body 'username=admin&password=lumina2026').access_token)"}
$th=@{Authorization="Bearer $((Invoke-RestMethod "$B/token" -Method POST -ContentType 'application/x-www-form-urlencoded' -Body 'username=test_teacher&password=Test12345678').access_token)"}
$stok=(Invoke-RestMethod "$B/student/token" -Method POST -ContentType 'application/json' -Body '{"username":"test_student","password":"Test12345678"}').token
$sh=@{Authorization="Bearer $stok"}
$p=0;$f=0;$b=@()

function T($n,$c){try{&$c;$script:p++}catch{$script:f++;$script:b+="$n`: $($_.Exception.Message.Substring(0,[Math]::Min(200,$_.Exception.Message.Length)))"}}

T "Admin whoami" { $r=Invoke-RestMethod "$B/whoami" -Headers $ah; if($r.role-ne"admin"){throw $r.role} }
T "Teacher whoami" { $r=Invoke-RestMethod "$B/whoami" -Headers $th; if($r.role-ne"teacher"){throw $r.role} }
T "Student profile" { $r=Invoke-RestMethod "$B/student/profile" -Headers $sh; if(-not $r.scholar_id){throw} }
T "Wrong pwd 401" { try{Invoke-RestMethod "$B/token" -Method POST -ContentType 'application/x-www-form-urlencoded' -Body 'username=admin&password=wrong' -EA Stop;throw}catch{if($_.Exception.Response.StatusCode-ne401){throw} } }
T "Bad token 401" { try{Invoke-RestMethod "$B/whoami" -Headers @{Authorization="Bearer X"} -EA Stop;throw}catch{if($_.Exception.Response.StatusCode-ne401){throw} } }
T "Subjects" { $r=Invoke-RestMethod "$B/subjects" -Headers $ah; if($r.Count-lt1){throw} }
T "Grades" { $r=Invoke-RestMethod "$B/grades" -Headers $ah; if($r.Count-lt1){throw} }
T "Ping" { Invoke-RestMethod "$B/ping" | Out-Null }
T "Healthz" { $r=Invoke-RestMethod "$B/healthz"; if($r.status-ne"ok"){throw} }
T "Stats" { $r=Invoke-RestMethod "$B/stats" -Headers $ah; if(-not $r.scholars){throw} }
T "Teacher profile" { $r=Invoke-RestMethod "$B/teacher/me" -Headers $th; if($r.username-ne"test_teacher"){throw} }
T "Teacher scholars" { Invoke-RestMethod "$B/teacher/scholars" -Headers $th | Out-Null }
T "Teacher resource-topics" { Invoke-RestMethod "$B/teacher/resource-topics" -Headers $th | Out-Null }

# Course CRUD
$cid2=$null
T "Create course" { $r=Invoke-RestMethod "$B/api/teacher/courses" -Method POST -ContentType 'application/json' -Headers $th -Body '{"title":"E2E QA","subject":"General","grade":"8","language":"en"}'; $script:cid2=$r.id }
T "Get course" { $r=Invoke-RestMethod "$B/api/teacher/courses/$cid2" -Headers $th; if($r.title-ne"E2E QA"){throw} }
T "Update course" { Invoke-RestMethod "$B/api/teacher/courses/$cid2" -Method PUT -ContentType 'application/json' -Headers $th -Body '{"title":"E2E QA v2"}' | Out-Null }
T "Add topic" { $r=Invoke-RestMethod "$B/api/teacher/courses/$cid2/topics" -Method POST -ContentType 'application/json' -Headers $th -Body '{"title":"Ch1"}'; if(-not $r.id){throw} }
T "List topics" { $r=Invoke-RestMethod "$B/api/teacher/courses/$cid2/topics" -Headers $th; if($r.Count-lt1){throw} }
T "Add course quiz" { $q='{"title":"CQ","questions":[{"id":"q1","type":"mcq","question":"Q1?","options":["A","B"],"correct_answer":0}],"time_limit_minutes":5,"pass_threshold":50}'; Invoke-RestMethod "$B/api/teacher/courses/$cid2/quiz" -Method POST -ContentType 'application/json' -Headers $th -Body $q | Out-Null }
T "Publish course" { Invoke-RestMethod "$B/api/teacher/courses/$cid2/publish" -Method POST -Headers $th | Out-Null }

# Student LMS
T "Student browse" { $r=Invoke-RestMethod "$B/api/courses" -Headers $sh; if($r.total-lt1){throw "0 courses"} }
T "Student enroll" { $c2=(Invoke-RestMethod "$B/api/courses" -Headers $sh).items[0].id; Invoke-RestMethod "$B/api/courses/$c2/enroll" -Method POST -Headers $sh | Out-Null }
T "Student progress" { $c2=(Invoke-RestMethod "$B/api/courses" -Headers $sh).items[0].id; Invoke-RestMethod "$B/api/courses/$c2/progress" -Headers $sh | Out-Null }
T "Student analytics" { Invoke-RestMethod "$B/student/analytics" -Headers $sh | Out-Null }
T "Student weekly" { Invoke-RestMethod "$B/student/weekly-breakdown" -Headers $sh | Out-Null }

# Upload
T "Upload quiz" { $r=Invoke-RestMethod "$B/teacher/upload-quiz" -Method POST -ContentType 'application/json' -Headers $th -Body '{"title":"E2E Quiz","time_limit_minutes":10,"pass_threshold":60,"questions":[{"type":"mcq","text":"Q?","options":["A","B"],"correct_answer":0}]}'; if($r.status-ne"success"){throw $r.status} }
T "List resources" { $r=Invoke-RestMethod "$B/resources" -Headers $th; if($r.Count-lt1){throw} }

# Localization
foreach($lang in @("en","hi","kn","fr")){T "Lang $lang" { $raw=(Invoke-WebRequest "$B/static/lang/$lang.json" -UseBasicParsing).Content; $obj=$raw|ConvertFrom-Json; $count=($obj.PSObject.Properties|Measure-Object).Count; if($count-lt100){throw "$count keys"} }}

# Static pages
$cookie=$null; try{$lr=Invoke-WebRequest "$B/token" -Method POST -ContentType 'application/x-www-form-urlencoded' -Body 'username=admin&password=lumina2026' -SessionVariable sess}catch{}
foreach($pg in @("index","courses","students","manage-content","manage-danger","manage-settings","welcome")){T "Page $pg" { $r=Invoke-WebRequest "$B/static/$pg.html" -UseBasicParsing -WebSession $sess -TimeoutSec 5; if($r.StatusCode-ne200){throw $r.StatusCode} }}

# Security
T "SQL injection" { try{Invoke-RestMethod "$B/token" -Method POST -ContentType 'application/x-www-form-urlencoded' -Body "username=admin'OR'1'='1&password=x" -EA Stop;throw}catch{if($_.Exception.Response.StatusCode-ne401){throw} } }
T "Student->teacher 403" { try{Invoke-RestMethod "$B/teacher/me" -Headers $sh -EA Stop;throw}catch{if($_.Exception.Response.StatusCode-ne403){throw $_.Exception.Response.StatusCode} } }
T "Teacher->admin 403" { try{Invoke-RestMethod "$B/admin/log" -Headers $th -EA Stop;throw}catch{ $c=$_.Exception.Response.StatusCode; if($c-ne403 -and $c-ne401){throw $c} } }

Write-Output "`n========================================"
Write-Output "PASS: $p | FAIL: $f"
if($b.Count -gt 0){Write-Output "`nBUGS:"; $b | ForEach-Object{Write-Output "  [!] $_"}}
Write-Output "========================================"
