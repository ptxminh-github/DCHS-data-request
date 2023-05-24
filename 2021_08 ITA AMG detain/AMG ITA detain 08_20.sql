/****** Script for SelectTopNRows command from SSMS  ******/
DECLARE @StartDate DATE;
DECLARE @EndDate DATE;
SELECT @StartDate = '2019-01-01'; 
SELECT @EndDate = '2020-12-31'; 

DROP TABLE IF EXISTS ##ITA_line

SELECT distinct
 cc.[intake_no] 
,cc.[kcid]
,cc.[call_stamp]
,left(cast(cc.[call_stamp] as varchar(50)),7) as call_month
,year(cc.[call_stamp]) as call_yr
,CASE when mco.MCO ='AGP' then 1 else 0 end as AGP
INTO ##ITA_line
FROM [bhrd].[cc_intake] cc
LEFT JOIN [bhrd].[ref_ita_disposition] disp
on cc.disposition = disp.disposition 
LEFT JOIN (Select kcid, census_month, MCO FROM [bhrd].[tbl_Monthly_Coverage_Since_2018] ) mco 
on cc.kcid=mco.kcid
and mco.census_month = left(cast(cc.[call_stamp] as varchar(50)),7)
WHERE cc.[call_stamp] IS NOT NULL
 AND cc.[disposition] IS NOT NULL
 AND cc.call_stamp >= @StartDate 
 AND cc.call_stamp  <= @EndDate
 AND disp.[detained] = 'Y' and disp.version = '2021'

 --select * from ##ITA_line

 Select a.call_month, AMG_count, total_count
 from 
 (select call_year, call_month, count(intake_no) as AMG_count  
 from ##ITA_line
 where AGP = 1
 group by call_month) a
 inner join 
 (select call_month, count(intake_no) as total_count
 from ##ITA_line
 group by call_month) t
 on a.census_month=t.census_month
 order by census_month