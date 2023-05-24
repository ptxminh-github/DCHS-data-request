--create table with id, condition and 2year window 
 USE PHClaims;
 if object_id('tempdb..##header_bh') IS NOT NULL drop table ##header_bh;
    
--id_mcaid = {`id_source`}
--final = {`icdcm_from_schema`}
--mcaid_claim_icdcm_header = {`icdcm_from_table`} 
--ref.rda_value_set_2021 = {`ref_schema`}.{`ref_table`}
-- final.mcaid_claim_pharm = {`claim_pharm_from_schema`}.{`claim_pharm_from_table`}
--ref.rolling_time_24mo_2012_2020 = {`rolling_schema`}.{`rolling_table`}


   SELECT DISTINCT  
   id_mcaid
   ,svc_date
   --,DATEADD(month,24,svc_date) as end_window -- 24mo look back period
   ,bh_cond
   --, link = 1 
   INTO ##header_bh
   --BASED ON DIAGNOSIS (group certain substances into other based on exploratory analysis)
   FROM (SELECT 
       id_mcaid
	  ,svc_date
      ,CASE when b.value_set_name = 'SUD-Dx-Value-Set' and b.sub_group in ('NA', 'Hallucinogen', 'Inhalant') then 'Other Substance'
		    else b.sub_group
		    end as bh_cond
        FROM  (SELECT DISTINCT id_mcaid, icdcm_norm, first_service_date as svc_date
                FROM final.mcaid_claim_icdcm_header
                ) as a
        INNER JOIN (SELECT sub_group, code_set, code, value_set_name
    		            FROM  ref.rda_value_set_2021
    		            WHERE value_set_name in ('MI-Diagnosis', 'SUD-Dx-Value-Set') 
    		            ) as b
    		ON a.icdcm_norm = b.code 
   ) diag
   
   UNION
   
   SELECT DISTINCT  
   id_mcaid
   ,svc_date
   --,DATEADD(month,24,svc_date) as end_window -- 24mo look back period
   ,bh_cond
   --, 'link' = 1 
   -- BASED ON PRESCRIPTIONS
   FROM (SELECT DISTINCT a.id_mcaid
			,a.rx_fill_date as svc_date
	        ,CASE 
            WHEN b.sub_group = 'ADHD Rx' THEN 'ADHD'
            WHEN b.sub_group = 'Antianxiety Rx' THEN 'Anxiety'
            WHEN b.sub_group = 'Antidepressants Rx' THEN 'Depression'
            WHEN b.sub_group = 'Antimania Rx' THEN 'Mania/Bipolar'
            WHEN b.sub_group = 'Antipsychotic Rx' THEN 'Psychotic'
            end as bh_cond
    FROM final.mcaid_claim_pharm a
    INNER JOIN (SELECT sub_group, code_set, code
    	          FROM ref.rda_value_set_2021
    	          WHERE value_set_name = 'Psychotropic-NDC') as b
    ON a.ndc = b.code
          ) rx

---23,649,384 rows affected

SELECT --TOP (1000)  *
TOP (1000000) *
,1 as link
into ##test1
FROM ##header_bh order by id_mcaid, svc_date, bh_cond

 if object_id('tempdb..##test2') IS NOT NULL drop table ##test2;
Select 
id_mcaid
,svc_date
,bh_cond
,[start_window]
 ,[end_window]
 into ##test2
from ##test1 as header
left join 
(Select cast(start_window as date) as 'start_window'
		, cast(end_window as date) as 'end_window'
		, 1 as link from [ref].[rolling_time_24mo_2012_2020]) as rolling
on header.link=rolling.link
where header.svc_date between rolling.[start_window] and rolling.[end_window] 

select --top 10000 
* 
,case
        when datediff(month,
			lag(b.end_window) over (partition by b.id_mcaid, b.bh_cond  order by b.id_mcaid, b.bh_cond, b.start_window),
			b.start_window) <= 1 then null
        when b.start_window < 
			lag(b.end_window) over (partition by b.id_mcaid, b.bh_cond order by b.id_mcaid,  b.bh_cond, b.start_window) 
			then null
        when row_number() over (partition by b.id_mcaid , b.bh_cond
          order by b.id_mcaid, b.bh_cond,  b.start_window) = 1 then null
        else row_number() over (partition by b.id_mcaid , b.bh_cond
          order by b.id_mcaid, b.bh_cond, b.start_window)
      end as 'discont'
,row_number() over (partition by b.id_mcaid , b.bh_cond
          order by b.id_mcaid, b.start_window) as row_no
, lag(b.end_window) over (partition by b.id_mcaid, b.bh_cond order by b.id_mcaid, b.bh_cond, b.start_window) as lag_end
into ##test3
from ##test2 b
order by id_mcaid
--,svc_date
,bh_cond
,[start_window]
 --,[end_window]

 select * from ##test3 
 where discont is not null
 order by id_mcaid
--,svc_date
,bh_cond
,[start_window]
 --,[end_window]

 select * from ##test3 
 where id_mcaid ='100010145WA'
 --and bh_cond='Anxiety'
 and bh_cond='Cannabis'
  order by id_mcaid
--,svc_date
,bh_cond
,[start_window]
 --,[end_window]

  select * from ##test3 
 where id_mcaid ='100013467WA'
 order by id_mcaid
,bh_cond
,[start_window]

   SELECT distinct d.id_mcaid, bh_cond, min(d.start_window) as 'from_date', 
          max(d.end_window) as 'to_date' 
into ##result
FROM
(
 SELECT c.id_mcaid, c.start_window, c.end_window, c.discont, c.row_no ,bh_cond
    ,sum(case when c.discont is null then 0 else 1 end) over
      (order by c.id_mcaid, bh_cond, c.row_no) as 'grp'
from ##test3 c) d
group by d.id_mcaid,d.grp,bh_cond
order by id_mcaid
--,svc_date
,bh_cond


if object_id('tempdb..##rolling_tmp_bh') IS NOT NULL drop table ##rolling_tmp_bh;
SELECT *
INTO ##rolling_tmp_bh
FROM
(
SELECT 
id_mcaid
,bh_cond
,start_window as from_date
,CASE WHEN cont=0 
		and lag(new_end_window) OVER (partition by id_mcaid, bh_cond order by id_mcaid,bh_cond,svc_date desc) is not null 
		then lag(new_end_window) OVER (partition by id_mcaid, bh_cond order by id_mcaid,bh_cond,svc_date desc) 
	When cont=0 
		and lag(new_end_window) OVER (partition by id_mcaid, bh_cond order by id_mcaid,bh_cond,svc_date desc) is null
		then end_window 
	else new_end_window 
	end as to_date
FROM 
(--define rows that have start_window and end_window from each continuous period  
SELECT 
*
,CASE WHEN cont = 0 then svc_date else null end as start_window
,CASE WHEN cont = 1 then end_window else null end as new_end_window
,CASE WHEN cont = 0 -- start of a new period
		or lag(cont) OVER (partition by id_mcaid, bh_cond order by id_mcaid,bh_cond,svc_date desc) = 0 
		or lag(id_mcaid) OVER (partition by id_mcaid, bh_cond order by id_mcaid,bh_cond,svc_date desc) <> id_mcaid -- start of a new ID
		or lag(bh_cond) OVER (partition by id_mcaid, bh_cond order by id_mcaid,bh_cond,svc_date desc) <> bh_cond -- start of a new condition
		or lag(bh_cond) OVER (partition by id_mcaid, bh_cond order by id_mcaid,bh_cond,svc_date desc) is null -- start of a new condition
		then 1 else 0 end as keep_row
FROM
( -- define continuity in time periods for each id, condition
SELECT 
id_mcaid
,bh_cond
,svc_date
,end_window
,case when LAG(end_window) OVER (partition by id_mcaid, bh_cond order by id_mcaid,bh_cond,svc_date) between svc_date and end_window 
		then 1 else 0 end as cont
from ##header_bh
) a
) b
where b.keep_row=1 --keeping rows with start_date and rows with end_date of each continuous period only
) c
where c.from_date is not null

--SELECT TOP (1000) * FROM ##rolling_tmp_bh ORDER BY id_mcaid,bh_cond, from_date