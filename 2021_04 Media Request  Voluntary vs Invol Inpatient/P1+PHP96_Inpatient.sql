DECLARE @StartDate  DATE;
DECLARE @EndDate    DATE;

SET @StartDate = '2019-01-01';
SET @EndDate   = '2020-12-31';

/**************************************/
/*Part 1:
Provider One database
MH Inpatient, Medicaid, Invol and Vol

Name: Hospitalization for Mental Illness, based on FUH

Logic:
Inpatient Stay Value set
INTERSECT
(
Mental Illness Value Set
UNION
Intentional Self-Harm Value Set
)
*/

/*SELECT 
version
,[value_set_name]
,[code_system]
,COUNT([code])
FROM [bhrd].[ref_hedis_code_system]
WHERE [value_set_name] IN
('Mental Illness'
,'Mental Health Diagnosis'
,'Inpatient Stay'
,'Nonacute Inpatient Stay'
,'Intentional Self-Harm')
GROUP BY version,[value_set_name], [code_system]
ORDER BY version, [value_set_name], [code_system];

version	value_set_name	code_system	(No column name)
2018	Inpatient Stay	UBREV	81
2018	Mental Health Diagnosis	ICD10CM	287
2018	Mental Illness	ICD10CM	150
2018	Nonacute Inpatient Stay	UBREV	27
2018	Nonacute Inpatient Stay	UBTOB	134
2020	Inpatient Stay	UBREV	81
2020	Intentional Self-Harm	ICD10CM	945
2020	Mental Health Diagnosis	ICD10CM	291
2020	Mental Health Diagnosis	SNOMED CT US Edition	1308
2020	Mental Illness	ICD10CM	153
2020	Mental Illness	SNOMED CT US Edition	588
2020	Nonacute Inpatient Stay	UBREV	27
2020	Nonacute Inpatient Stay	UBTOB	131
*/

--inpatient 
DROP TABLE IF EXISTS ##inpatient

SELECT DISTINCT
ln.[id_mcaid]
,ln.[claim_header_id]
,hd.[admsn_date] AS [admit_date]
--,hd.[first_service_date]
--,COALESCE(hd.[admsn_date],hd.[first_service_date]) as admit_date2
INTO ##inpatient
FROM [claims].[final_mcaid_claim_line] AS ln
INNER JOIN [bhrd].[ref_hedis_code_system] AS hed
ON [value_set_name] = 'Inpatient Stay'
AND hed.[code_system] = 'UBREV'
AND hed.[version] = '2020'
AND ln.[rev_code] = hed.[code]
LEFT JOIN [claims].[final_mcaid_claim_header] hd
ON ln.[claim_header_id] = hd.[claim_header_id]
AND 
(
(hd.[admsn_date] between @StartDate and @EndDate)
OR (hd.[admsn_date] is null and hd.[first_service_date] between @StartDate and @EndDate)
)
--(1,348,642 rows affected)

/*QA
select count(*) from ##inpatient where [admit_date2] is null --964,591
select count(*) from ##inpatient where [admit_date] is null --964,591
first service date isn't helpful when admit date is null
*/

--mental health
DROP TABLE IF EXISTS ##mentalhealth

SELECT DISTINCT
hd.[id_mcaid]
,hd.[claim_header_id]
,hd.[admsn_date] AS [admit_date]
--,COALESCE(hd.[admit_date],hd.[first_service_date]) as admit_date2
INTO ##mentalhealth
FROM [claims].[final_mcaid_claim_icdcm_header] AS dx
INNER JOIN [bhrd].[ref_hedis_code_system] AS hed
ON hed.[value_set_name] IN
('Mental Health Diagnosis'
,'Mental Illness'
,'Intentional Self-Harm')
AND hed.[code_system] = 'ICD10CM'
AND dx.[icdcm_version] = 10
-- Principal Diagnosis
AND dx.[icdcm_number] = '01'
AND dx.[icdcm_norm] = hed.[code]
LEFT JOIN [claims].[final_mcaid_claim_header] hd
ON dx.[claim_header_id] = hd.[claim_header_id]
AND hd.[admsn_date] between @StartDate and @EndDate
--(347,716 rows affected);

--combine both
DROP TABLE IF EXISTS ##inpatient_mh

select *
into ##inpatient_mh 
from ##inpatient
intersect
select * from ##mentalhealth
--(208,523 rows affected)


/**************************************/

/*Part 2:
PHP96 db
MH Inpatient, 
Medicaid and Non-Medicaid: Involuntary
*/
--Note: Admission count is based on unique client-admitdate-agency date combo, for every admit date, for every agency. 
--If client was discharged from 613 went to 664 and came back to 613 within a day, we will treat it as one admission but this was not the case. 
--This is why it's not neccessary to look at discharge date in this case.
DROP TABLE IF EXISTS ##invol
SELECT DISTINCT 
am.[auth_no]
,am.[kcid]
,af.[admit_date]
,1 AS invol_flag
--,am.[program]
--,af.[discharge_date]
,af.[agency_id]
INTO ##invol
FROM [bhrd].[au_master] am
INNER JOIN  [bhrd].[au_facility_stay] af
ON am.[auth_no]=af.[auth_no]
INNER JOIN [bhrd].[ip_invol] invol
ON am.[auth_no]=invol.[auth_no]

WHERE am.[status_code] in ('TM', 'AA')
AND af.[admit_date] between @StartDate and @EndDate
--select * from ##invol order by [kcid],[admit_date]

--output result
Select 
DATEPART (YEAR,[admit_date]) AS admit_year
,sum(invol_flag) as count_inpatient_stay
,count(distinct KCID) as count_unique_mbr
from ##invol
group by DATEPART (YEAR,[admit_date])
order by DATEPART (YEAR,[admit_date])

/*The following code is to prepare for part 3*/

--determine Medicaid Elig
DROP TABLE IF EXISTS ##KCID_LIST
SELECT DISTINCT [kcid], [admit_date] as [elig_day] 
INTO ##KCID_LIST
FROM ##invol

drop table if exists ##KCID_MEDICAID
SELECT DISTINCT 
[kcid]
,(year([start_date]) * 100) + month([start_date]) as census_month
,'Medicaid'  as coverage_plan
INTO ##KCID_MEDICAID
FROM [bhrd].[ep_coverage_mco]
WHERE [plan] = 'F19'
and (year([start_date]) * 100) + month([start_date]) - ((year([end_date]) * 100) + month([end_date])) = 0
and KCID in (SELECT DISTINCT [KCID] from ##KCID_LIST)

--Join w ##invol to get Medicaid eli
DROP TABLE IF EXISTS ##invol_mc_elig
SELECT DISTINCT 
a.[auth_no]
,a.[kcid]
,a.[admit_date]
,a.[agency_id]
,CASE WHEN mcaid.coverage_plan = 'Medicaid' THEN 1 else 0 end as Medicaid_flag
,a.invol_flag
INTO ##invol_mc_elig
FROM (SELECT DISTINCT *, 
		(year([admit_date]) * 100) + month([admit_date]) as census_month 
		from ##invol) a
LEFT JOIN ##KCID_MEDICAID mcaid
on a.[kcid]=mcaid.[kcid] 
and a.census_month=mcaid.census_month 
--(20,501 rows affected)
--select * from ##invol_mc_elig
-- Create a list of P1ID table to join

DROP TABLE IF EXISTS ##CTE
SELECT 
 [kcid]
,[p1_id]
,ROW_NUMBER() OVER(PARTITION BY [p1_id] ORDER BY [post_stamp] ASC) AS [row_num]
INTO ##CTE
FROM [bhrd].[g_p1_client]
WHERE kcid in (SELECT DISTINCT kcid FROM ##invol_mc_elig) 

DROP TABLE IF EXISTS ##P1ID_JOIN
SELECT
 [p1_id]
,[1] AS [kcid_1]
,[2] AS [kcid_2]
,[3] AS [kcid_3]
INTO ##P1ID_JOIN
FROM (SELECT * FROM ##CTE WHERE [row_num] <= 3) AS a
PIVOT(MAX([kcid]) FOR [row_num] IN ([1], [2], [3])) AS P
ORDER BY [p1_id];

--Join to get P1_ID
DROP TABLE IF EXISTS ##invol_w_p1
SELECT 
a.*
,p1.[p1_id]
INTO ##invol_w_p1
FROM ##invol_mc_elig a
LEFT JOIN ##P1ID_JOIN p1
ON a.[kcid] = p1.[kcid_1]
--(20,501 rows affected)
--select * from ##invol_w_p1 where [p1_id] IS NULL and Medicaid_flag = 1 (0 records. this means that all null P1_ID is for non-Medicaid members)

/**************************************/
/*Part 3: MH, Voluntary, both Medicaid and Non-Medicaid

There are 3 steps for this:
First, get MH, Voluntary, Non-medicaid
Second, get MH, Voluntary, Meicaid (using results from part 1 and part 2)
Last, combine step1 and step2
*/

/*Part 3.1: MH, voluntary, Non-Medicaid */
DROP TABLE IF EXISTS ##mh_vol_nonmcaid

SELECT DISTINCT 
am.[auth_no]
,am.[kcid]
,af.[admit_date]
,0 AS invol_flag
--,am.[program]
--,af.[discharge_date]
,af.[agency_id]
INTO ##mh_vol_nonmcaid
FROM [bhrd].[au_master] am
INNER JOIN  [bhrd].[au_facility_stay] af
ON am.[auth_no]=af.[auth_no]
INNER JOIN [bhrd].[ip_vol] invol
ON am.[auth_no]=invol.[auth_no]
WHERE am.[status_code] in ('TM', 'AA')
AND af.[admit_date] between @StartDate and @EndDate

/*Part 3.2: get MH, Voluntary, Medicaid
Logic: 
MH Medicaid (part 1) 
EXCEPT
MH Involuntary Medicaid (part 2)*/

DROP TABLE IF EXISTS ##mh_voluntary_mcaid
SELECT 
CTE.*
,0 as invol_flag
,1 as medicaid_flag
INTO ##mh_voluntary_mcaid
FROM 
(
SELECT DISTINCT id_mcaid as p1_id ,admit_date 
FROM ##inpatient_mh
EXCEPT
SELECT DISTINCT p1_id,admit_date 
FROM ##invol_w_p1 
where Medicaid_flag = 1
) CTE
--SELECT * FROM ##mh_voluntary_mcaid (6271 records)

/*Part 3.3: Combine 3.1 and 3.2, MH, Voluntary, both Medicaid and non-Medicaid */
DROP TABLE IF EXISTS ##mh_vol

SELECT DISTINCT
CAST(p1_id as VARCHAR(255)) as id
,admit_date
,invol_flag
,medicaid_flag
,1 as vol_flag
,CAST('P1' AS VARCHAR(3)) as id_type
INTO ##mh_vol
FROM ##mh_voluntary_mcaid

UNION
SELECT DISTINCT
CAST(kcid as VARCHAR(255)) as id
,admit_date
,invol_flag
,0 as medicaid_flag
,1 as vol_flag
,CAST('KC' AS VARCHAR(3)) as id_type
FROM ##mh_vol_nonmcaid

--output result
Select 
DATEPART (YEAR,[admit_date]) AS admit_year
,sum(vol_flag) as count_inpatient_stay
,count(distinct id) as count_unique_mbr
from ##mh_vol
group by DATEPART (YEAR,[admit_date])
order by DATEPART (YEAR,[admit_date])

