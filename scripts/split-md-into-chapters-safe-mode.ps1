# compute band string in a PowerShell-friendly way
$frontBandValue = if ([string]::IsNullOrEmpty($bandNum)) { "" } else { "Band " + $bandNum }

$date = (Get-Date).ToString("yyyy-MM-dd")
$frontmatter = @"
---
title: "$($c.Title -replace '"','''')"
slug: "$slug"
band: "$frontBandValue"
order: $order
date: $date
description: ""
---
"@