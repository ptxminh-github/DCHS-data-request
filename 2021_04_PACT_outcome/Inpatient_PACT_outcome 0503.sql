/****************************************************************************************************************
*  	PACT Participant Pre-Post Outcomes					  														*
*	Response to BHRD-PME Data Request #B17																		*
*																												*
*	The following syntax and instructions query client data for PACT participants.								*
*	The data is used to assess outcome data for PACT participants based on available and reliable data sources.	*
*	The following code provides analyses for:																	*
*		-Involuntary inpatient for MH																			*
*		-ITA Length of Stay: ET vs Community Hospitals 															*
*		-Voluntary inpatient for SUD																			*
*																												*
*	Created by: Minh Phan (5/3/2021)																			*
*																												*
****************************************************************************************************************/

USE hhs_analytics_workspace

/**PART1: Eligible PACT participants - Tyler's code **/
---- Create temp table of eligible PACT participants ----
DROP TABLE IF EXISTS ##PACT_Analytic_Sample
SELECT a.auth_no, a.agency_id, a.kcid, b.p1_id, a.status_code, a.status_reason,
		a.start_date, a.expire_date, Capped_EndDate = 0
INTO ##PACT_Analytic_Sample
FROM [bhrd].[au_master] a
JOIN [bhrd].[g_p1_client] b										--Append P1 ID to PACT anlaytic sample
ON a.kcid=b.kcid
WHERE a.program = '58'											--Only PACT Enrollment (not Outreach and Engagement)
	AND YEAR(a.start_date) >= '2014'							--To allow 2-year look-back period for Medicaid claims (started 1/1/2012)
	AND a.start_date < '7/1/2020'								--To allow at least 6 months to observe "post" outcomes
	AND (DATEDIFF(d, a.start_date, a.expire_date) >= 180 		--Must be enrolled in PACT at least 180 days
		OR a.expire_date IS NULL)		
	AND a.status_code != 'CX'									--Exclude cancelled authorizations						
ORDER BY a.start_date

select * from ##PACT_Analytic_Sample

---- Replace NULL end dates and CY2021 end dates with 12/31/2020 (capping analytic time frame) ----
UPDATE ##PACT_Analytic_Sample
SET Capped_EndDate = 1
WHERE expire_date >= '2021-01-01' OR expire_date IS NULL

UPDATE ##PACT_Analytic_Sample
SET expire_date = '2020-12-31'
WHERE expire_date >= '2021-01-01' OR expire_date IS NULL

/**PART2: Involuntary inpatient for MH**/
DROP TABLE IF EXISTS ##pact_invol
SELECT DISTINCT 
am.[auth_no]
,am.[kcid]
,af.[admit_date]
,1 AS invol_flag
--,am.[program]
--,af.[discharge_date]
,af.[agency_id]
INTO ##pact_invol
FROM [bhrd].[au_master] am
INNER JOIN  [bhrd].[au_facility_stay] af
ON am.[auth_no]=af.[auth_no]
INNER JOIN [bhrd].[ip_invol] invol
ON am.[auth_no]=invol.[auth_no]
AND am.[program] = 'IP'
WHERE 1=1
--AND am.[status_code] in ('TM', 'AA')
AND am.status_code != 'CX'
AND am.[kcid] in (select distinct kcid FROM ##PACT_Analytic_Sample)I 
--Select * from ##pact_invol order by  [admit_date]

/**PART3: ITA Length of Stay: ET vs Community Hospitals**/
DROP TABLE IF EXISTS ##ITA_LOS
SELECT
b.[kcid]
,a.[auth_no]
,a.[admit_date]
,a.[discharge_date]
,DATEDIFF(DAY, a.[admit_date], a.[discharge_date]) AS [length_of_stay]
,CASE WHEN a.[agency_id] IN ('058','481','482','486','605', '781','947','948','961','968','991') 
		THEN 'ET' 
		ELSE 'OTHER' 
		END AS [facility_type]
INTO ##ITA_LOS
FROM [bhrd].[au_facility_stay] AS a
LEFT JOIN [bhrd].[au_master] AS b
ON a.[auth_no] = b.[auth_no]
LEFT JOIN [bhrd].[ip_master] AS c
ON a.[auth_no] = c.[auth_no]
LEFT JOIN [bhrd].[cc_facility_stay] AS f
ON a.[stay_no] = f.[stay_no]
where c.[ip_type] = 'I' 
AND f.[stay_no] IS NULL 
AND b.[status_code] = 'AA'
AND b.[kcid] in (select distinct kcid FROM ##PACT_Analytic_Sample)
--select * from  ##ITA_LOS

/**PART4: Voluntary inpatient for SUD (SUD Residential) - Count and Length of Stay**/
drop table if exists ##pact_sudres
SELECT distinct
a.[auth_no] 
,b.kcid
,b.[auth_type] 
,b.[program]
,a.[agency_id]
,[admit_date]
,[discharge_date]
,DATEDIFF(DAY, a.[admit_date], a.[discharge_date]) AS [length_of_stay]
,[stay_no]
INTO ##pact_sudres
FROM [bhrd].[au_facility_stay] a
LEFT JOIN [bhrd].[au_master] AS b
ON a.[auth_no] = b.[auth_no]
where [program] = 'SRS'  
and [auth_type] = 'IP' --when [program] = 'SRS', [auth_type] = 'IP' is also always TRUE
and status_code <> 'CX'
AND b.[kcid] in (select distinct kcid FROM ##PACT_Analytic_Sample)
--and (discharge_date between @StartDate and @EndDate or [admit_date] between @StartDate and @EndDate)
--and discharge_date is not NULL
order by auth_no

--Count of SUD Admission
SELECT 
year(admit_date) as admit_year
,COUNT([admit_date]) AS [count_sud]
FROM ##pact_sudres
GROUP BY year(admit_date)
ORDER BY year(admit_date)