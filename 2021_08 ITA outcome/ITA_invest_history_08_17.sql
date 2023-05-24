DECLARE @StartDate DATE;
DECLARE @EndDate DATE;

SELECT @StartDate = '2005-01-01'; 
SELECT @EndDate = '2021-06-30'; 


   DROP TABLE IF EXISTS ##ITA_line_historic

SELECT distinct
p.petition_no
,p.file_date
,cc.[intake_no] 
,cc.[kcid]
,cc.[call_stamp]
,year(call_stamp) as call_year
,count(cc.intake_no) OVER (PARTITION by kcid ORDER BY kcid, call_stamp asc) as cnt 
--INTO ##ITA_line_historic
FROM [bhrd].[cc_intake] cc
LEFT JOIN [bhrd].[cc_petition] p
on cc.[intake_no] = p.[intake_no] 
--LEFT JOIN [bhrd].[ref_ita_disposition] disp
--on cc.disposition = disp.disposition
WHERE cc.[call_stamp] IS NOT NULL
 --AND cc.[disposition] IS NOT NULL
 --AND cc.call_stamp >= @StartDate 
-- AND cc.call_stamp  <= @EndDate
AND p.file_date <= @EndDate
 --AND disp.[investigation] = 'Y'
 --and disp.version = '2021'
 group by cc.[intake_no] 
,cc.[kcid]
,cc.[call_stamp]

select *
,CASE WHEN cnt <> 1 then lag(call_year) OVER (PARTITION by kcid ORDER BY kcid, call_stamp asc) ELSE null end as prev_year
 ,CASE WHEN cnt <> 1 then DATEDIFF(year,lag(call_year) OVER (PARTITION by kcid ORDER BY kcid, call_stamp asc),call_year) ELSE null end as diff
from ##ITA_line_historic order by kcid

Select a.call_year, cnt_1st, cnt_2nd, cnt_3rd, cnt_4th, cnt_5plus, total_cnt, total_cnt_dis
from 
(
select call_year, count (intake_no) as cnt_1st
from ##ITA_line_historic
where cnt=1
group by call_year
) a

left join 

(
select call_year, count (intake_no) as cnt_2nd
from ##ITA_line_historic
where cnt=2
group by call_year
) b 
on a.call_year=b.call_year

left join
(
select call_year, count (kcid) as cnt_3rd 
from ##ITA_line_historic
where cnt=3
group by call_year
) c
on a.call_year=c.call_year

left join
(
select call_year, count (kcid) as cnt_4th
from ##ITA_line_historic
where cnt=4
group by call_year
) e
on a.call_year=e.call_year

left join
(
select call_year, count (kcid) as cnt_5plus
from ##ITA_line_historic
where cnt>4
group by call_year
) f
on a.call_year=f.call_year

left join
(select call_year, count (distinct intake_no) as total_cnt_dis, count(intake_no) as total_cnt
from ##ITA_line_historic
group by call_year) d
on a.call_year=d.call_year
order by call_year 



SELECT distinct
p.petition_no
,p.file_date
,cc.[intake_no] 
,cc.[kcid]
,cc.[call_stamp]
,year(call_stamp) as call_year
,count(cc.intake_no) OVER (PARTITION by kcid ORDER BY kcid, call_stamp asc) as cnt 
--INTO ##ITA_line_historic
FROM [bhrd].[cc_intake] cc
LEFT JOIN [bhrd].[cc_petition] p
on cc.[intake_no] = p.[intake_no] 
--LEFT JOIN [bhrd].[ref_ita_disposition] disp
--on cc.disposition = disp.disposition
WHERE cc.[call_stamp] IS NOT NULL
 --AND cc.[disposition] IS NOT NULL
 --AND cc.call_stamp >= @StartDate 
-- AND cc.call_stamp  <= @EndDate
 --AND disp.[investigation] = 'Y'
 --and disp.version = '2021'
 group by p.petition_no
,p.file_date
,cc.[intake_no] 
,cc.[kcid]
,cc.[call_stamp]
,year(call_stamp)
order by intake_no