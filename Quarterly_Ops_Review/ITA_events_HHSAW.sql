/****** Script for SelectTopNRows command from SSMS  ******/
---Get relevant call data
DROP TABLE IF EXISTS ##ITA_line

SELECT
 cc.[intake_no] as ITA_auth_no
,cc.[kcid]
,cc.[call_stamp]
,cast(dateadd(month,datediff(month,0, cc.[call_stamp]),0) as date) as [call_month]
,cc.[disposition]
,disp.[description]
,CASE 
 WHEN cc.[statute_timeline_ind] = '6' THEN 'ER' 
 WHEN cc.[statute_timeline_ind] = '12' THEN 'Law Enforcement' 
 ELSE 'N/A'
 END AS [type]
,CASE 
 WHEN DATEPART(year,cc.[face_ref_stamp] ) = 1900 THEN NULL
 WHEN DATEDIFF(MINUTE, cc.[face_ref_stamp], cc.[disposition_stamp]) < 0 THEN NULL
 -- 43,200 minutes -> 720 hours -> 30 days
 WHEN DATEPART(year,[face_ref_stamp] ) <> 1900 AND DATEDIFF(MINUTE, cc.[face_ref_stamp], cc.[disposition_stamp]) > 43200 THEN 43200
 ELSE DATEDIFF(MINUTE, cc.[face_ref_stamp], cc.[disposition_stamp])
 END AS [response_time_min]
,CASE --CAST(a.[response_time_min] AS NUMERIC(9,2)) / 60 AS [response_time_hrs]
 WHEN DATEPART(year,cc.[face_ref_stamp] ) = 1900 THEN NULL
 WHEN DATEDIFF(MINUTE, cc.[face_ref_stamp], cc.[disposition_stamp]) < 0 THEN NULL
 WHEN DATEPART(year,cc.[face_ref_stamp] ) <> 1900 AND DATEDIFF(MINUTE, cc.[face_ref_stamp], cc.[disposition_stamp]) > 43200 THEN 720
 ELSE CAST(DATEDIFF(MINUTE, cc.[face_ref_stamp], cc.[disposition_stamp]) AS NUMERIC(9,2)) / 60 
 END AS [response_time_hrs]
,CASE WHEN disp.[investigation] = 'Y' then 1 else 0 END AS [investigation]
,CASE when disp.[detained] = 'Y' THEN 1 else 0 END AS [detained]
,CASE WHEN [detained] = 'Y' AND cc.[disposition] <> 'FR' THEN 1 ELSE 0 END AS [new_detained]
,CASE WHEN [detained] = 'Y' AND cc.[disposition] = 'FR' THEN 1 ELSE 0 END AS [revoked_detained]
,CASE when disp.voluntary = 'Y' then 1 else 0 END AS [voluntary]
,CASE when disp.discharge_referral = 'Y' then 1 else 0 END AS [discharge_referral]

INTO ##ITA_line
FROM [bhrd].[cc_intake] cc
LEFT JOIN [bhrd].[ref_ita_disposition] disp
on cc.disposition = disp.disposition
WHERE cc.[call_stamp] IS NOT NULL
 AND cc.[disposition] IS NOT NULL
 AND cc.call_stamp>='08/31/2018'

 select datepart(year,[call_month]) as year,
                        EOMONTH([call_month]) as report_date,
                        sum([investigation]) as count
                        from ##ITA_line
                        GROUP BY [call_month] 
                        ORDER BY [call_month]
Select distinct kcid, datepart(year,[call_month]) as year
from ##ITA_line
where call_stamp >'12/31/2018'
and investigation=1


 