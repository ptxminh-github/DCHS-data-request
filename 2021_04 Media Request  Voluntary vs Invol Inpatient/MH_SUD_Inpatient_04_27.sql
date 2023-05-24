DECLARE @StartDate  DATE;
DECLARE @EndDate    DATE;

SET @StartDate = '2019-01-01';
SET @EndDate   = '2020-12-31';



/**************************************/

/*Part 1:
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
AND am.[program] = 'IP'
WHERE 1=1
--AND am.[status_code] in ('TM', 'AA')
AND am.status_code != 'CX'
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

Select 
 admit_year
,admit_time
,sum(invol_flag) as count_inpatient_stay
,count(distinct [kcid]) as count_unique_mbr
from 
(SELECT
DATEPART (YEAR,[admit_date]) AS admit_year
,CASE WHEN DATEPART (MONTH,[admit_date]) IN ('1','2','3','4','5','6') THEN 'Q1-Q2'
		WHEN DATEPART (MONTH,[admit_date]) IN ('7','8','9','10','11','12') THEN 'Q3-Q4'
		else 'What'
		end as admit_time
,invol_flag
,[kcid]
from ##invol) a
group by  admit_year ,admit_time
order by admit_year ,admit_time

/**************************************/
/*Part 3: MH, Voluntary, both Medicaid and Non-Medicaid

There are 3 steps for this:
First, get MH, Voluntary, Non-medicaid
Second, get MH, Voluntary, Meicaid (using results from part 1 and part 2)
Last, combine step1 and step2
*/
DECLARE @StartDate  DATE;
DECLARE @EndDate    DATE;

SET @StartDate = '2019-01-01';
SET @EndDate   = '2020-12-31';
/*Part 3.1: MH, voluntary, Non-Medicaid */
DROP TABLE IF EXISTS ##mh_vol_nonmcaid

SELECT DISTINCT 
--am.[auth_no]
am.[kcid]
,af.[admit_date]
--,0 AS invol_flag
,1 AS vol_flag
--,am.[program]
--,af.[discharge_date]
,af.[agency_id]
--,am.status_code
INTO ##mh_vol_nonmcaid
FROM [bhrd].[au_master] am
INNER JOIN  [bhrd].[au_facility_stay] af
ON am.[auth_no]=af.[auth_no]
INNER JOIN [bhrd].[ip_vol] vol
ON am.[auth_no]=vol.[auth_no]
WHERE 1=1
--AND am.[status_code] in ('TM', 'AA')
AND am.status_code != 'CX'
AND am.[program] = 'IP'  
AND af.[admit_date] between @StartDate and @EndDate

select * from ##mh_vol_nonmcaid

select status_code, sum(vol_flag)
from ##mh_vol_nonmcaid
group by status_code

Select 
DATEPART (YEAR,[admit_date]) AS admit_year
,sum(vol_flag) as count_inpatient_stay
,count(distinct [kcid]) as count_unique_mbr
from ##mh_vol_nonmcaid
group by DATEPART (YEAR,[admit_date])
order by DATEPART (YEAR,[admit_date])


Select 
 admit_year
,admit_time
,sum(vol_flag) as count_inpatient_stay
,count(distinct [kcid]) as count_unique_mbr
from 
(SELECT
DATEPART (YEAR,[admit_date]) AS admit_year
,CASE WHEN DATEPART (MONTH,[admit_date]) IN ('1','2','3','4','5','6') THEN 'Q1-Q2'
		WHEN DATEPART (MONTH,[admit_date]) IN ('7','8','9','10','11','12') THEN 'Q3-Q4'
		else 'What'
		end as admit_time
,vol_flag
,[kcid]
from ##mh_vol_nonmcaid) a
group by  admit_year ,admit_time
order by admit_year ,admit_time


/****************************/
/*Part 4: SUD - Voluntary Admission*/
DECLARE @StartDate  DATE;
DECLARE @EndDate    DATE;

SET @StartDate = '2019-01-01';
SET @EndDate   = '2020-12-31';
drop table if exists ##sud_voluntary

SELECT distinct
au.[auth_no] 
,au.kcid
,af.[agency_id]
,af.[admit_date]
,1 as flag
INTO ##sud_voluntary
FROM [bhrd].[au_master] AS au
INNER JOIN [bhrd].[au_facility_stay] af
ON au.[auth_no] = af.[auth_no]
where au.[program] = 'SRS'  
and au.[auth_type] = 'IP' --when [program] = 'SRS', [auth_type] = 'IP' is also always TRUE
and au.status_code <> 'CX'
and af.[admit_date] between @StartDate and @EndDate
order by auth_no
--(2,848 rows affected)

--output result
Select 
DATEPART (YEAR,[admit_date]) AS admit_year
,sum(flag) as count_inpatient_stay
,count(distinct kcid) as count_unique_mbr
from ##sud_voluntary
group by DATEPART (YEAR,[admit_date])
order by DATEPART (YEAR,[admit_date])

Select 
 admit_year
,admit_time
,sum(flag) as count_inpatient_stay
,count(distinct [kcid]) as count_unique_mbr
from 
(SELECT
DATEPART (YEAR,[admit_date]) AS admit_year
,CASE WHEN DATEPART (MONTH,[admit_date]) IN ('1','2','3','4','5','6') THEN 'Q1-Q2'
		WHEN DATEPART (MONTH,[admit_date]) IN ('7','8','9','10','11','12') THEN 'Q3-Q4'
		else 'What'
		end as admit_time
,flag
,[kcid]
from ##sud_voluntary) a
group by  admit_year ,admit_time
order by admit_year ,admit_time

