# CloudWatch Logs Insights Queries

## Application Error Rate
```
fields @timestamp, @message
| filter level = "ERROR"
| stats count(*) as errorCount by bin(5m)
| sort @timestamp desc
```

## P99 Latency by Endpoint
```
fields @timestamp, endpoint, duration
| stats pct(duration, 99) as p99, avg(duration) as avg, count(*) as requests by endpoint
| sort p99 desc
```

## Top 10 Error Messages
```
fields @message
| filter level = "ERROR"
| stats count(*) as occurrences by errorMessage
| sort occurrences desc
| limit 10
```

## ECS Container Restarts (CloudTrail)
```
fields @timestamp, requestParameters.containers.0.name, responseElements.failures
| filter eventName = "RunTask"
| filter ispresent(responseElements.failures)
| sort @timestamp desc
```

## Slow Database Queries
```
fields @timestamp, query, duration_ms
| filter duration_ms > 1000
| stats count(*) as slowQueries, avg(duration_ms) as avgDuration by query
| sort slowQueries desc
```

## GuardDuty Finding Summary (Security)
```
fields @timestamp, detail.type, detail.severity, detail.description
| filter source = "aws.guardduty"
| stats count(*) by detail.type
| sort count(*) desc
```

## Failed Login Attempts (CloudTrail)
```
fields @timestamp, userIdentity.userName, sourceIPAddress, errorCode
| filter eventName = "ConsoleLogin" and errorCode = "Failed authentication"
| stats count(*) as failedAttempts by userIdentity.userName, sourceIPAddress
| sort failedAttempts desc
```

## CodeBuild Build Duration Trend
```
fields @timestamp, projectName, buildStatus, duration
| filter source = "aws.codebuild"
| stats avg(duration) as avgDuration, count(*) as builds by projectName, buildStatus
| sort avgDuration desc
```
