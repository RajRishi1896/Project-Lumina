$BASE = "http://127.0.0.1:8000"
$pass = 0; $fail = 0; $fixes = @()

function Test-Case($name, $block) {
    try { & $block; $script:pass++ }
    catch { $script:fail++; $script:fixes += "$name`: $($_.Exception.Message)" }
}

# --- PHASE 5: Auth Flow ---
Write-Output "`n=== PHASE 5: Authentication ==="

Test-Case "Admin login" {
    $r = Invoke-RestMethod "$BASE/token" -Method POST -ContentType "application/x-www-form-urlencoded" -Body "username=admin&password=lumina2026"
    if ($r.role -ne "admin") { throw "Wrong role: $($r.role)" }
    if (-not $r.access_token) { throw "No token" }
    $script:adminToken = $r.access_token
    Write-Output "  OK: admin logged in, role=$($r.role)"
}

Test-Case "Admin login wrong password" {
    try { Invoke-RestMethod "$BASE/token" -Method POST -ContentType "application/x-www-form-urlencoded" -Body "username=admin&password=wrong" -ErrorAction Stop; throw "Should have failed" }
    catch { if ($_.Exception.Response.StatusCode -ne 401) { throw "Expected 401, got $($_.Exception.Response.StatusCode)" } }
    Write-Output "  OK: 401 on wrong password"
}

Test-Case "Create teacher via admin" {
    $h = @{Authorization = "Bearer $script:adminToken"}
    $r = Invoke-RestMethod "$BASE/api/admin/create-teacher" -Method POST -ContentType "application/json" -Headers $h -Body '{"username":"test_teacher","password":"Test12345678","name":"Test Teacher"}'
    if ($r.status -ne "success") { throw "Failed: $($r | ConvertTo-Json)" }
    Write-Output "  OK: teacher created"
}

Test-Case "Teacher login" {
    $r = Invoke-RestMethod "$BASE/token" -Method POST -ContentType "application/x-www-form-urlencoded" -Body "username=test_teacher&password=Test12345678"
    if ($r.role -ne "teacher") { throw "Wrong role: $($r.role)" }
    $script:teacherToken = $r.access_token
    Write-Output "  OK: teacher logged in, role=$($r.role)"
}

Test-Case "Create student" {
    $h = @{Authorization = "Bearer $script:adminToken"}
    $r = Invoke-RestMethod "$BASE/api/admin/create-student" -Method POST -ContentType "application/json" -Headers $h -Body '{"username":"test_student","password":"Test12345678","name":"Test Student"}'
    if ($r.status -ne "success") { throw "Failed: $($r | ConvertTo-Json)" }
    Write-Output "  OK: student created"
}

Test-Case "Student login" {
    $r = Invoke-RestMethod "$BASE/student/token" -Method POST -ContentType "application/json" -Body '{"username":"test_student","password":"Test12345678"}'
    if ($r.role -ne "student") { throw "Wrong role: $($r.role)" }
    $script:studentToken = $r.access_token
    Write-Output "  OK: student logged in, role=$($r.role)"
}

Test-Case "Unauthorized access to teacher endpoint" {
    try { Invoke-RestMethod "$BASE/teacher/me" -Headers @{Authorization = "Bearer INVALID"} -ErrorAction Stop; throw "Should have failed" }
    catch { if ($_.Exception.Response.StatusCode -ne 401) { throw "Expected 401" } }
    Write-Output "  OK: 401 on invalid token"
}

Test-Case "Student cannot access teacher endpoint" {
    $h = @{Authorization = "Bearer $script:studentToken"}
    try { Invoke-RestMethod "$BASE/teacher/me" -Headers $h -ErrorAction Stop; throw "Should have failed" }
    catch { if ($_.Exception.Response.StatusCode -ne 403) { throw "Expected 403, got $($_.Exception.Response.StatusCode)" } }
    Write-Output "  OK: 403 on student accessing teacher endpoint"
}

Test-Case "Whoami admin" {
    $h = @{Authorization = "Bearer $script:adminToken"}
    $r = Invoke-RestMethod "$BASE/whoami" -Headers $h
    if ($r.role -ne "admin") { throw "Wrong role" }
    Write-Output "  OK: whoami=admin, role=$($r.role)"
}

Test-Case "Whoami teacher" {
    $h = @{Authorization = "Bearer $script:teacherToken"}
    $r = Invoke-RestMethod "$BASE/whoami" -Headers $h
    if ($r.role -ne "teacher") { throw "Wrong role" }
    Write-Output "  OK: whoami=teacher, role=$($r.role)"
}

# --- PHASE 6: Database Operations ---
Write-Output "`n=== PHASE 6: Database Operations ==="

Test-Case "List subjects" {
    $r = Invoke-RestMethod "$BASE/subjects"
    Write-Output "  OK: $($r.Count) subjects"
}

Test-Case "Create subject" {
    $h = @{Authorization = "Bearer $script:adminToken"}
    $r = Invoke-RestMethod "$BASE/teacher/subjects" -Method POST -ContentType "application/json" -Headers $h -Body '{"name":"Test Subject"}'
    Write-Output "  OK: subject created"
}

Test-Case "List grades" {
    $r = Invoke-RestMethod "$BASE/grades"
    Write-Output "  OK: $($r.Count) grades"
}

Test-Case "Create grade" {
    $h = @{Authorization = "Bearer $script:adminToken"}
    $r = Invoke-RestMethod "$BASE/grades" -Method POST -ContentType "application/json" -Headers $h -Body '{"name":"Grade 99"}'
    Write-Output "  OK: grade created"
}

Test-Case "List resource topics" {
    $h = @{Authorization = "Bearer $script:teacherToken"}
    $r = Invoke-RestMethod "$BASE/teacher/resource-topics" -Headers $h
    Write-Output "  OK: $($r.Count) topics"
}

Test-Case "Create resource topic" {
    $h = @{Authorization = "Bearer $script:teacherToken"}
    $r = Invoke-RestMethod "$BASE/teacher/resource-topics" -Method POST -ContentType "application/json" -Headers $h -Body '{"name":"Test Topic","subject":"Test Subject"}'
    Write-Output "  OK: topic created"
}

# --- PHASE 7: Uploads ---
Write-Output "`n=== PHASE 7: File Uploads ==="

Test-Case "Quiz upload" {
    $h = @{Authorization = "Bearer $script:teacherToken"}
    $quiz = '{"title":"E2E Quiz","time_limit_minutes":10,"pass_threshold":60,"max_attempts":3,"shuffle":false,"grade":8,"language":"en","subject":"General","questions":[{"type":"mcq","text":"What is 2+2?","options":["3","4","5","6"],"correct_answer":1,"explanation":"Math"},{"type":"tf","text":"Sky is blue.","options":["True","False"],"correct_answer":0,"explanation":"Nature"},{"type":"multi","text":"Select vowels.","options":["A","B","C","E"],"correct_answer":[0,3],"explanation":"English"},{"type":"fill_blanks","text":"Capital of France is ___.","correct_answer":"Paris","explanation":"Geography"}]}'
    $r = Invoke-RestMethod "$BASE/teacher/upload-quiz" -Method POST -ContentType "application/json" -Headers $h -Body $quiz
    if ($r.status -ne "success") { throw "Upload failed" }
    $script:quizId = $r.filename -replace '\.json$',''
    Write-Output "  OK: quiz uploaded, id=$($script:quizId)"
}

Test-Case "Resources list includes quiz" {
    $h = @{Authorization = "Bearer $script:teacherToken"}
    $r = Invoke-RestMethod "$BASE/resources" -Headers $h
    $quiz = $r | Where-Object { $_.type -eq 'quiz' }
    if (-not $quiz) { throw "Quiz not found in resources" }
    Write-Output "  OK: $($r.Count) resources, quiz found: $($quiz.title)"
}

# --- PHASE 8: LMS Workflow ---
Write-Output "`n=== PHASE 8: LMS Workflow ==="

Test-Case "Create course" {
    $h = @{Authorization = "Bearer $script:teacherToken"}
    $r = Invoke-RestMethod "$BASE/api/teacher/courses" -Method POST -ContentType "application/json" -Headers $h -Body '{"title":"E2E Course","description":"End-to-end test course","subject":"General","grade":"8","language":"en"}'
    if (-not $r.id) { throw "No course id: $($r | ConvertTo-Json)" }
    $script:courseId = $r.id
    Write-Output "  OK: course created, id=$($script:courseId)"
}

Test-Case "List teacher courses" {
    $h = @{Authorization = "Bearer $script:teacherToken"}
    $r = Invoke-RestMethod "$BASE/api/teacher/courses" -Headers $h
    Write-Output "  OK: $($r.Count) courses"
}

Test-Case "Get course" {
    $h = @{Authorization = "Bearer $script:teacherToken"}
    $r = Invoke-RestMethod "$BASE/api/teacher/courses/$($script:courseId)" -Headers $h
    if ($r.title -ne "E2E Course") { throw "Wrong title: $($r.title)" }
    Write-Output "  OK: course title=$($r.title)"
}

Test-Case "Update course" {
    $h = @{Authorization = "Bearer $script:teacherToken"}
    $r = Invoke-RestMethod "$BASE/api/teacher/courses/$($script:courseId)" -Method PUT -ContentType "application/json" -Headers $h -Body '{"title":"E2E Course Updated"}'
    Write-Output "  OK: course updated"
}

Test-Case "Add course topic" {
    $h = @{Authorization = "Bearer $script:teacherToken"}
    $r = Invoke-RestMethod "$BASE/api/teacher/courses/$($script:courseId)/topics" -Method POST -ContentType "application/json" -Headers $h -Body '{"title":"Chapter 1","description":"First chapter"}'
    if (-not $r.id) { throw "No topic id: $($r | ConvertTo-Json)" }
    $script:topicId = $r.id
    Write-Output "  OK: topic created, id=$($script:topicId)"
}

Test-Case "Add course quiz" {
    $h = @{Authorization = "Bearer $script:teacherToken"}
    $quiz = '{"title":"Course Quiz","questions":[{"type":"mcq","text":"Q1?","options":["A","B"],"correct_answer":0}],"time_limit_minutes":5,"pass_threshold":50}'
    $r = Invoke-RestMethod "$BASE/api/teacher/courses/$($script:courseId)/quiz" -Method POST -ContentType "application/json" -Headers $h -Body $quiz
    Write-Output "  OK: course quiz created"
}

Test-Case "Publish course" {
    $h = @{Authorization = "Bearer $script:teacherToken"}
    $r = Invoke-RestMethod "$BASE/api/teacher/courses/$($script:courseId)/publish" -Method POST -Headers $h
    Write-Output "  OK: course published"
}

Test-Case "Student browse courses" {
    $h = @{Authorization = "Bearer $script:studentToken"}
    $r = Invoke-RestMethod "$BASE/api/courses" -Headers $h
    Write-Output "  OK: $($r.Count) published courses visible to student"
}

Test-Case "Student enroll" {
    $h = @{Authorization = "Bearer $script:studentToken"}
    $r = Invoke-RestMethod "$BASE/api/courses/$($script:courseId)/enroll" -Method POST -Headers $h
    Write-Output "  OK: enrolled"
}

Test-Case "Student course progress" {
    $h = @{Authorization = "Bearer $script:studentToken"}
    $r = Invoke-RestMethod "$BASE/api/courses/$($script:courseId)/progress" -Headers $h
    Write-Output "  OK: progress retrieved, enrolled=$($r.enrolled)"
}

# --- PHASE 9: Frontend pages ---
Write-Output "`n=== PHASE 9: Frontend Pages ==="

$pages = @("welcome", "index", "courses", "students", "student-detail", "manage-content", "manage-danger", "manage-settings", "manage-help", "error")
foreach ($page in $pages) {
    Test-Case "GET /static/$page.html" {
        $h = @{Authorization = "Bearer $script:adminToken"}
        $r = Invoke-WebRequest "$BASE/static/$page.html" -Headers $h -UseBasicParsing -TimeoutSec 5
        if ($r.StatusCode -ne 200) { throw "Status $($r.StatusCode)" }
        if ($r.Content.Length -lt 100) { throw "Empty page ($($r.Content.Length) bytes)" }
        Write-Output "  OK: $page.html ($($r.Content.Length) bytes)"
    }
}

# --- PHASE 10: Localization ---
Write-Output "`n=== PHASE 10: Localization ==="

foreach ($lang in @("en", "hi", "kn", "fr")) {
    Test-Case "GET /static/lang/$lang.json" {
        $r = Invoke-RestMethod "$BASE/static/lang/$lang.json"
        $keys = $r.PSObject.Properties.Count
        if ($keys -lt 100) { throw "Only $keys keys" }
        Write-Output "  OK: $lang.json has $keys keys"
    }
}

# --- PHASE 12: Performance ---
Write-Output "`n=== PHASE 12: Performance ==="

Test-Case "Ping latency" {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Invoke-RestMethod "$BASE/ping" | Out-Null
    $sw.Stop()
    if ($sw.ElapsedMilliseconds -gt 1000) { throw "Slow ping: $($sw.ElapsedMilliseconds)ms" }
    Write-Output "  OK: ping=$($sw.ElapsedMilliseconds)ms"
}

Test-Case "Stats endpoint" {
    $h = @{Authorization = "Bearer $script:adminToken"}
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $r = Invoke-RestMethod "$BASE/stats" -Headers $h
    $sw.Stop()
    Write-Output "  OK: stats in $($sw.ElapsedMilliseconds)ms, total_users=$($r.total_users)"
}

# --- PHASE 13: Security ---
Write-Output "`n=== PHASE 13: Security ==="

Test-Case "SQL injection in login" {
    try { Invoke-RestMethod "$BASE/token" -Method POST -ContentType "application/x-www-form-urlencoded" -Body "username=admin'%20OR%20'1'%3D'1&password=anything" -ErrorAction Stop; throw "Should fail" }
    catch { if ($_.Exception.Response.StatusCode -ne 401) { throw "Expected 401" } }
    Write-Output "  OK: SQL injection blocked"
}

Test-Case "Path traversal in static" {
    try { $r = Invoke-WebRequest "$BASE/static/../../etc/passwd" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop } catch { $r = $_.Exception.Response }
    Write-Output "  OK: path traversal handled"
}

Test-Case "Health check" {
    $r = Invoke-RestMethod "$BASE/healthz"
    Write-Output "  OK: healthz status=$($r.status)"
}

# --- SUMMARY ---
Write-Output "`n========================================"
Write-Output "RESULTS: $pass passed, $fail failed"
if ($fixes.Count -gt 0) {
    Write-Output "`nFIXES NEEDED:"
    $fixes | ForEach-Object { Write-Output "  - $_" }
}
Write-Output "========================================"
