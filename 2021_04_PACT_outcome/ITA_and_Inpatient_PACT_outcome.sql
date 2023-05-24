/****************************************************************************************************************
*  	PACT Participant Pre-Post Outcomes					  														*
*	Response to BHRD-PME Data Request #B17																		*
*																												*
*	The following syntax and instructions query client data for PACT participants.								*
*	The data is used to assess outcome data for PACT participants based on available and reliable data sources.	*														*
*	Focus of analysis is ED visits, hospitalizations, jail bookings, and ITAs.		
*	The following part of the code is for hospitalizations and ITA only
*																												*
*	Created by: Tyler Corwin and Minh Phan																		*
*	Created date: 4/15/2021																						*
*																												*
****************************************************************************************************************/

USE hhs_analytics_workspace

/**PART1: Eligible PACT participants**/
---- Create temp table of eligible PACT participants ----
DROP TABLE IF EXISTS #PACT_Analytic_Sample
SELECT a.auth_no, a.agency_id, a.kcid, b.p1_id, a.status_code, a.status_reason,
		a.start_date, a.expire_date, Capped_EndDate = 0
INTO #PACT_Analytic_Sample
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
select * from #PACT_Analytic_Sample

---- Replace NULL end dates and CY2021 end dates with 12/31/2020 (capping analytic time frame) ----
UPDATE #PACT_Analytic_Sample
SET Capped_EndDate = 1
WHERE expire_date >= '2021-01-01' OR expire_date IS NULL

UPDATE #PACT_Analytic_Sample
SET expire_date = '2020-12-31'
WHERE expire_date >= '2021-01-01' OR expire_date IS NULL

/**PART2: Hospitalization**/
--Getting inpatient clients (including both acute and non-acute stays, excluding hospice stays)
DROP TABLE IF EXISTS ##PACT_inpatient
SELECT DISTINCT
ln.[id_mcaid]
,ln.[claim_header_id]
,hd.[admsn_date] AS [admit_date]
INTO ##PACT_inpatient
FROM [claims].[final_mcaid_claim_line] AS ln
INNER JOIN [bhrd].[ref_hedis_code_system] AS hed
ON [value_set_name] = 'Inpatient Stay'
AND hed.[code_system] = 'UBREV'
AND hed.[version] = '2020'
AND ln.[rev_code] = hed.[code]
AND ln.[id_mcaid] in (select distinct p1_id FROM #PACT_Analytic_Sample)
LEFT JOIN [claims].[final_mcaid_claim_header] hd
ON ln.[claim_header_id] = hd.[claim_header_id];
--3428 rows

--select * from ##PACT_inpatient
--select max(admit_date) from ##PACT_inpatient 2021-02-28
--select min(admit_date) from ##PACT_inpatient 2008-04-06

--copy the temp table to [bhrd] schema for Tyler
DROP TABLE IF EXISTS [bhrd].tmp_PACT_inpatient
SELECT DISTINCT
a.[id_mcaid] as p1_id
,b.KCID
,a.[claim_header_id]
,a.[admit_date]
INTO [bhrd].tmp_PACT_inpatient
FROM ##PACT_inpatient a
INNER join #PACT_Analytic_Sample b
ON a.[id_mcaid]=b.P1_ID 
--(3438 rows affected)

--select * from [bhrd].tmp_PACT_inpatient

/**PART3: ITA**/
--get all relevant CC intakes 
DROP TABLE IF EXISTS ##ITA_line
SELECT
 cc.[intake_no] as ITA_auth_no
,cc.[kcid]
,cc.[call_stamp]
,cast(dateadd(month,datediff(month,0, cc.[call_stamp]),0) as date) as [call_month]
,cc.[disposition]
,disp.[description]
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
 AND cc.[kcid] in (SELECT DISTINCT kcid from #PACT_Analytic_Sample)
 (--4525 rows)

 --SELECT * FROM ##ITA_line

 --select * FROM [bhrd].[ref_ita_disposition] 

 /*Notes for Tyler for different ITA metrics*/

 --Metric: Total number of CCS (Crisis and Commitment Services) intakes resulting in a DCR investigation for ITA
 SELECT * from ##ITA_line where [investigation] =1

 --Metric: Total number of CCS intakes resulting in detentions
 SELECT * from ##ITA_line where [detained] =1

 --Metric: Total number of CCS intakes resulting in a voluntary inpatient treatment
 SELECT * from ##ITA_line where [voluntary] =1



