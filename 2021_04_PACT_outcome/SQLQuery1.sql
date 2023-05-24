/****** Script for SelectTopNRows command from SSMS  ******/
SELECT TOP (1000) [version]
      ,[value_set_name]
      ,[code_system]
      ,[code]
      ,[definition]
      ,[value_set_version]
      ,[code_system_version]
      ,[value_set_oid]
      ,[code_system_oid]
  FROM [bhrd].[ref_hedis_code_system]

  /****************************************************************************************************************
*  	PACT Participant Pre-Post Outcomes					  														*
*	Response to BHRD-PME Data Request #B17																		*
*																												*
*	The following syntax and instructions query client data for PACT participants.								*
*	The data is used to assess outcome data for PACT participants based on available and reliable data sources.	*														*
*	Focus of analysis is ED visits, hospitalizations, jail bookings, and ITAs.									*
*																												*
*	Created by: Tyler Corwin and Minh Phan																		*
*	Created date: 4/5/2021																						*
*																												*
****************************************************************************************************************/

USE hhs_analytics_workspace

---- Create temp table of eligible PACT participants ----
DROP TABLE #PACT_Analytic_Sample
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

SELECT * FROM #PACT_Analytic_Sample
-------------------------------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS ##PACT_inpatient
SELECT DISTINCT
--TOP(1000)
-- 'HEDIS' AS [value_set_group]
--,hed.[value_set_name]
--,NULL AS [data_source_type]
--,NULL AS [sub_group]
--,hed.[code_system]
--,NULL AS [primary_dx_only]
ln.[id_mcaid]
,ln.[claim_header_id]
,hd.[admsn_date] AS [admit_date]
,hd.[dschrg_date] AS [discharge_date]
,hd.[last_service_date]
,ln.[first_service_date] as ln_first_svcdate
,ln.[last_service_date] as ln_last_svcdate
INTO ##PACT_inpatient
FROM [claims].[final_mcaid_claim_line] AS ln
INNER JOIN [bhrd].[ref_hedis_code_system] AS hed
ON [value_set_name] IN 
('Inpatient Stay')
AND hed.[code_system] IN ('UBREV')
AND hed.[version] = '2020'
AND ln.[rev_code] = hed.[code]
AND ln.[id_mcaid] in (select distinct p1_id FROM #PACT_Analytic_Sample)
LEFT JOIN [claims].[final_mcaid_claim_header] hd
ON ln.[claim_header_id] = hd.[claim_header_id];
--(3438 rows affected)

--checking if there are differences in these
select * from ##PACT_inpatient
where [discharge_date] <> ln_last_svcdate --0rows

--checking if there are differences in last service date in claim line and claim header
select * from ##PACT_inpatient
where [last_service_date] <> ln_last_svcdate --0rows

select * from ##PACT_inpatient
where [first_service_date] <> ln_first_svcdate --0rows

select * from ##PACT_inpatient
where [first_service_date] <> ln_last_svcdate

select distinct
null_dis
,count(distinct claim_header_id) as cnt
from (select distinct case when discharge_date is null then 1 else 0 end as null_dis, claim_header_id from ##PACT_inpatient)  a
group by null_dis
null_dis	cnt
0	1242
1	2196

select distinct
null_dis
,count(distinct claim_header_id) as cnt
from (select distinct case when [last_service_date]  is null then 1 else 0 end as null_dis, claim_header_id from ##PACT_inpatient)  a
group by null_dis
--all not null

select max([last_service_date]) from ##PACT_inpatient
where discharge_date is null 
--2021-02-28

select min([last_service_date]) from ##PACT_inpatient
where discharge_date is null
--2013-10-24

select distinct [last_service_date] from ##PACT_inpatient
where discharge_date is null
order by  [last_service_date] 

--conclusion: use admit date and last_service_date. maybe just use admit_date


select a.p1_id, isnull(b.flag,0) as flag
into ##test
from #PACT_Analytic_Sample a
left join (select distinct id_mcaid, 1 as flag from ##PACT_inpatient) b
on b.id_mcaid=a.p1_id
select count (distinct id_mcaid)  from ##PACT_inpatient