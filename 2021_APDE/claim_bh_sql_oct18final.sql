/****** Script for SelectTopNRows command from SSMS  ******/
USE PHClaims;
 
    
--id_mcaid = {`id_source`}
--final = {`icdcm_from_schema`}
--mcaid_claim_icdcm_header = {`icdcm_from_table`} 
--ref.rda_value_set_2021 = {`ref_schema`}.{`ref_table`}
-- final.mcaid_claim_pharm = {`claim_pharm_from_schema`}.{`claim_pharm_from_table`}
--ref.rolling_time_24mo_2012_2020 = {`rolling_schema`}.{`rolling_table`}

if object_id('tempdb..##header_bh') IS NOT NULL drop table ##header_bh;

   SELECT DISTINCT  
   id_mcaid
   ,svc_date
   --,DATEADD(month,24,svc_date) as end_window -- 24mo look back period
   ,bh_cond
   ,1 as link
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
   ,1 as link 
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

Select 
id_mcaid
,svc_date
,bh_cond
,[start_window]
,[end_window]
into ##matrix
from ##header_bh as header
left join 
(Select cast(start_window as date) as 'start_window'
		, cast(end_window as date) as 'end_window'
		, 1 as link from [ref].[rolling_time_24mo_2012_2020]) as rolling
on header.link=rolling.link
where header.svc_date between rolling.[start_window] and rolling.[end_window] 

if object_id('tempdb..##rolling_matrix') IS NOT NULL drop table ##rolling_matrix;
select 
* 
,case
        when datediff(month,
				lag(b.end_window) over (partition by b.id_mcaid, b.bh_cond order by b.id_mcaid, b.bh_cond, b.start_window),
				b.start_window) <= 1 
			then null
        when b.start_window < 
				lag(b.end_window) over (partition by b.id_mcaid, b.bh_cond order by b.id_mcaid,  b.bh_cond, b.start_window) 
			then null
        when row_number() over (partition by b.id_mcaid , b.bh_cond order by b.id_mcaid, b.bh_cond,  b.start_window) = 1 
			then null
        else row_number() over (partition by b.id_mcaid , b.bh_cond order by b.id_mcaid, b.bh_cond, b.start_window)
      end as 'discont'
,row_number() over (partition by b.id_mcaid, b.bh_cond order by b.id_mcaid, b.bh_cond, b.start_window) as row_no
--,lag(b.end_window) over (partition by b.id_mcaid, b.bh_cond order by b.id_mcaid, b.bh_cond, b.start_window) as lag_end
into ##rolling_matrix
from ##matrix b
--order by id_mcaid, bh_cond, start_window
 --28 mins

 if object_id('tmp.rolling_tmp_bh') IS NOT NULL drop table tmp.rolling_tmp_bh;
SELECT DISTINCT
d.id_mcaid
,bh_cond
,min(d.start_window) as 'from_date'
,max(d.end_window) as 'to_date' 
into tmp.rolling_tmp_bh
FROM
(SELECT c.id_mcaid, c.start_window, c.end_window,bh_cond
--, c.discont, c.row_no 
    ,sum(case when c.discont is null then 0 else 1 end) over
      (order by c.id_mcaid, bh_cond, c.row_no) as 'grp'
from ##rolling_matrix c) d
group by d.id_mcaid,d.grp,d.bh_cond
--order by id_mcaid,bh_cond
--2h30m

Select TOP (10000) *
FROM tmp.rolling_tmp_bh
order by id_mcaid,bh_cond
