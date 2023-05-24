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


