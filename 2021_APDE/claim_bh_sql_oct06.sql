/****** Script for SelectTopNRows command from SSMS  ******/
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
   ,DATEADD(month,24,svc_date) as end_window
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
   ,DATEADD(month,24,svc_date) as end_window
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

if object_id('tempdb..##test_2') IS NOT NULL drop table ##test_2;
SELECT 
*
,CASE WHEN cont = 0 then svc_date else null end as start_window
,CASE WHEN cont = 1 then end_window else null end as new_end_window
, lag(cont) OVER (partition by id_mcaid, bh_cond order by id_mcaid,bh_cond,svc_date desc) as lag_cont
,CASE WHEN cont = 0 
		or lag(cont) OVER (partition by id_mcaid, bh_cond order by id_mcaid,bh_cond,svc_date desc) = 0 
		or lag(id_mcaid) OVER (partition by id_mcaid, bh_cond order by id_mcaid,bh_cond,svc_date desc) <> id_mcaid 
		or lag(bh_cond) OVER (partition by id_mcaid, bh_cond order by id_mcaid,bh_cond,svc_date desc) <> bh_cond 
		or lag(bh_cond) OVER (partition by id_mcaid, bh_cond order by id_mcaid,bh_cond,svc_date desc) is null
		then 1 else 0 end as keep_row
--, lag(bh_cond) OVER (partition by id_mcaid, bh_cond order by id_mcaid,bh_cond,svc_date desc) as lag_bh
INTO ##test_2
FROM
(
SELECT 
id_mcaid
,bh_cond
,svc_date
,end_window
,LAG(end_window) OVER (partition by id_mcaid, bh_cond order by id_mcaid,bh_cond,svc_date) as lag_end
,case when LAG(end_window) OVER (partition by id_mcaid, bh_cond order by id_mcaid,bh_cond,svc_date) between svc_date and end_window then 1 else 0 end as cont
from ##header_bh
) a
ORDER BY id_mcaid,bh_cond, svc_date

SELECT TOP (1000) * 
FROM ##test_2 
where keep_row=1 
ORDER BY id_mcaid,bh_cond, svc_date 

SELECT 
*
,lag(start_window) OVER (partition by id_mcaid, bh_cond order by id_mcaid,bh_cond,svc_date)  as test
from ##test_2
ORDER BY id_mcaid,bh_cond, svc_date


  if object_id('tempdb..##rolling_tmp_bh') IS NOT NULL drop table ##rolling_tmp_bh;
Select 
id_mcaid 
,header.svc_date 
,DATEADD('month',24,svc_date) as end_window
,header.bh_cond
into ##rolling_tmp_bh 
FROM ##header_bh as header 

select top (1000) * from ##rolling_tmp_bh order by id_mcaid,bh_cond,svc_date 
--(11mins)

if object_id('tempdb..##rolling_tmp_bh') IS NOT NULL drop table ##rolling_tmp_bh;
      
      --join rolling time table to person ids

      --, CASE WHEN header.svc_date between rolling.start_window and rolling.end_window THEN 1 ELSE 0 END AS FLAG
SELECT 
a.{`id_source`}
,a.start_window
,a.end_window
,sum(a.bh_cond) as 'condition_1_cnt'

INTO ##rolling_tmp_bh 
SELECT
header.id_mcaid
,matrix.start_window
,matrix.end_window
,header.bh_cond
,header.svc_date
(



SELECT
header.id_mcaid
,matrix.start_window
,matrix.end_window
,header.bh_cond
--,header.svc_date
INTO ##rolling_tmp_bh
FROM ##header_bh as header 
LEFT JOIN ##matrix as matrix        
on header.id_mcaid = matrix.id_mcaid
where header.svc_date = matrix.start_window

) as a
group by a.id_mcaid, a.start_window, a.end_window
      --order by id.{`id_source`}, rolling.start_window




	  SELECT TOP (1000) * FROM ##rolling_tmp_bh  ORDER BY id_mcaid, start_window, end_window
	  SELECT * FROM ##rolling_tmp_bh where flag=0


--#drop temp table if it exists
        if object_id('tempdb..{`ccw_abbrev_table`}') IS NOT NULL drop table {`ccw_abbrev_table`};
      
      --collapse to single row per ID and contiguous time period
        SELECT distinct d.{`id_source`}, min(d.start_window) as 'from_date', 
          max(d.end_window) as 'to_date', {ccw_code} as 'ccw_code',
          {ccw_abbrev} as 'ccw_desc'
      
      INTO {`ccw_abbrev_table`}
      
      FROM (
      --set up groups where there is contiguous time
      SELECT c.{`id_source`}, c.start_window, c.end_window, c.discont, c.temp_row,
      
      sum(case when c.discont is null then 0 else 1 end) over
      (order by c.{`id_source`}, c.temp_row rows between unbounded preceding and current row) as 'grp'
  
    FROM (
      --pull out ID and time periods that contain appropriate claim counts
      SELECT b.{`id_source`}, b.start_window, b.end_window, b.condition_1_cnt, 
        b.condition_2_min_date, b.condition_2_max_date,
    
      --create a flag for a discontinuity in a person's disease status
      case
        when datediff(month, lag(b.end_window) over 
          (partition by b.{`id_source`} order by b.{`id_source`}, b.start_window), b.start_window) <= 1 then null
        when b.start_window < lag(b.end_window) over 
          (partition by b.{`id_source`} order by b.{`id_source`}, b.start_window) then null
        when row_number() over (partition by b.{`id_source`} 
          order by b.{`id_source`}, b.start_window) = 1 then null
        else row_number() over (partition by b.{`id_source`} 
          order by b.{`id_source`}, b.start_window)
      end as 'discont',
  
    row_number() over (partition by b.{`id_source`} order by b.{`id_source`}, b.start_window) as 'temp_row'
  
    FROM (
    --sum condition1 and condition2 claims by ID and period, take min and max service date for each condition2 claim by ID and period
      SELECT a.{`id_source`}, a.start_window, a.end_window, sum(a.condition1) as 'condition_1_cnt', 
      sum(a.condition2) as 'condition_2_cnt', min(a.condition_2_from_date) as 'condition_2_min_date', 
      max(a.condition_2_from_date) as 'condition_2_max_date'
    
      FROM (
      --pull ID, time period and claim information, subset to ID x time period rows containing a relevant claim
        SELECT matrix.{`id_source`}, matrix.start_window, matrix.end_window, cond.first_service_date, cond.condition1,
          cond.condition2, condition_2_from_date
      
      --pull in ID x time period matrix
        FROM (
          SELECT {`id_source`}, start_window, end_window
          FROM ##rolling_tmp
        ) as matrix
      
      --join to condition temp table
        left join (
          SELECT {`id_source`}, first_service_date, condition1, condition2, condition_2_from_date
          FROM ##header
        ) as cond
      
        on matrix.{`id_source`} = cond.{`id_source`}
        where cond.first_service_date between matrix.start_window and matrix.end_window
        ) as a
        group by a.{`id_source`}, a.start_window, a.end_window
      ) as b 
      {claim_count_condition}) as c
    ) as d
    group by d.{`id_source`}, d.grp
    order by d.{`id_source`}, from_date