/****** Script for SelectTopNRows command from SSMS  ******/
DECLARE @StartDate DATE;
DECLARE @EndDate DATE;

SELECT @StartDate = '2015-01-01'; 
SELECT @EndDate = '2021-06-30'; 


   DROP TABLE IF EXISTS ##ITA_line

SELECT distinct
 cc.[intake_no] 
,cc.[kcid]
,cc.[call_stamp]
,count(intake_no) OVER (PARTITION by kcid ORDER BY kcid, call_stamp asc) as cnt 
INTO ##ITA_line
FROM [bhrd].[cc_intake] cc
LEFT JOIN [bhrd].[ref_ita_disposition] disp
on cc.disposition = disp.disposition
WHERE cc.[call_stamp] IS NOT NULL
 AND cc.[disposition] IS NOT NULL
 AND cc.call_stamp >= @StartDate 
 AND cc.call_stamp  <= @EndDate
 AND disp.[detained] = 'Y'
 and disp.version = '2021'
 group by cc.[intake_no] 
,cc.[kcid]
,cc.[call_stamp]

 select *
 ,CASE WHEN cnt <> 1 then lag(call_stamp) OVER (PARTITION by kcid ORDER BY kcid, call_stamp asc) ELSE null end as prev_call 
 ,CASE WHEN cnt <> 1 then DATEDIFF(DAY,lag(call_stamp) OVER (PARTITION by kcid ORDER BY kcid, call_stamp asc),call_stamp) ELSE null end as diff
 from ##ITA_line order by kcid, intake_no 

 --how many have repeated ITA detentions?
 drop table if exists ##ita_repeat
 select kcid, max(cnt) as max_ita
 into ##ita_repeat
 from ##ITA_line group by kcid
 --SELECT distinct kcid, CAST(call_stamp as DATE) as call_date FROM ##ITA_line  where kcid in (select distinct KCID from ##ita_repeat where max_ita > 1) and cnt = 1 order by kcid
 select max_ita, count(kcid) as count
 from 
 ##ita_repeat
 group by max_ita
 order by max_ita

 drop table if exists ##average_time
 select kcid, AVG(diff) as av 
 into ##average_time
 from
 (
 select *
 ,CASE WHEN cnt <> 1 then lag(call_stamp) OVER (PARTITION by kcid ORDER BY kcid, call_stamp asc) ELSE null end as prev_call 
 ,CASE WHEN cnt <> 1 then DATEDIFF(DAY,lag(call_stamp) OVER (PARTITION by kcid ORDER BY kcid, call_stamp asc),call_stamp) ELSE null end as diff
 from ##ITA_line 
 ) a
 where cnt > 1
 group by kcid
 order by kcid
 
 select r.*, t.av
 , case when max_ita = 2 then 'two'
 when max_ita = 3 then 'three'
 when max_ita in (4,5) then 'four-five'
 when max_ita > 5 then 'more than 5'
 else 'whut' end as grp
 from (select * from ##ita_repeat where max_ita>1) r
 left join ##average_time t
 on r.kcid=t.kcid
 order by r.kcid
 


 select distinct top 1000 [call_stamp] from [bhrd].[cc_intake]
 order by call_stamp asc


 DECLARE @StartDate DATE;
DECLARE @EndDate DATE;

SELECT @StartDate = '2015-01-01'; 
SELECT @EndDate = '2021-06-30'; 


   DROP TABLE IF EXISTS ##ITA_line

SELECT distinct
 cc.[intake_no] 
,cc.[kcid]
,cc.[call_stamp]
,count(intake_no) OVER (PARTITION by kcid ORDER BY kcid, call_stamp asc) as cnt 
INTO ##ITA_line
FROM [bhrd].[cc_intake] cc
LEFT JOIN [bhrd].[ref_ita_disposition] disp
on cc.disposition = disp.disposition
WHERE cc.[call_stamp] IS NOT NULL
 AND cc.[disposition] IS NOT NULL
 AND cc.call_stamp >= @StartDate 
 AND cc.call_stamp  <= @EndDate
 AND disp.[detained] = 'Y'
 and disp.version = '2021'
 group by cc.[intake_no] 
,cc.[kcid]
,cc.[call_stamp]


drop table if exists ##ita_repeat
 select kcid, max(cnt) as max_ita
 into ##ita_repeat
 from ##ITA_line group by kcid

select distinct kcid from ##ita_repeat where max_ita > 1 

-----------------------------Check new ITA entry
DECLARE @StartDate DATE;
DECLARE @EndDate DATE;

SELECT @StartDate = '2005-01-01'; 
SELECT @EndDate = '2021-06-30'; 


   DROP TABLE IF EXISTS ##ITA_line_historic

SELECT distinct
 cc.[intake_no] 
,cc.[kcid]
,cc.[call_stamp]
,year(call_stamp) as call_year
,count(intake_no) OVER (PARTITION by kcid ORDER BY kcid, call_stamp asc) as cnt 
INTO ##ITA_line_historic
FROM [bhrd].[cc_intake] cc
LEFT JOIN [bhrd].[ref_ita_disposition] disp
on cc.disposition = disp.disposition
WHERE cc.[call_stamp] IS NOT NULL
 AND cc.[disposition] IS NOT NULL
 --AND cc.call_stamp >= @StartDate 
 AND cc.call_stamp  <= @EndDate
 AND disp.[detained] = 'Y'
 and disp.version = '2021'
 group by cc.[intake_no] 
,cc.[kcid]
,cc.[call_stamp]

select *
,CASE WHEN cnt <> 1 then lag(call_year) OVER (PARTITION by kcid ORDER BY kcid, call_stamp asc) ELSE null end as prev_year
 ,CASE WHEN cnt <> 1 then DATEDIFF(year,lag(call_year) OVER (PARTITION by kcid ORDER BY kcid, call_stamp asc),call_year) ELSE null end as diff
from ##ITA_line_historic order by kcid

Select a.call_year, entry_cnt, total_cnt, total_cnt_dis
from 
(
select call_year, count (kcid) as entry_cnt
from ##ITA_line_historic
where cnt=1
group by call_year
) a

left join 
(select call_year, count (distinct kcid) as total_cnt_dis, count(kcid) as total_cnt
from ##ITA_line_historic
group by call_year) b
on a.call_year=b.call_year
order by call_year 