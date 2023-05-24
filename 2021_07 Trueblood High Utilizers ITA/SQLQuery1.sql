/****** Script for SelectTopNRows command from SSMS  ******/

DECLARE @StartDate  DATE,
        @EndDate    DATE;

SELECT   @StartDate = '2021-01-01'        
       ,@EndDate   = '2021-06-30';
SELECT
b.[kcid]
--,a.[auth_no]
,a.[admit_date]
,a.[discharge_date]
,a.agency_id
--,d.[year_month] 
,DATEDIFF(DAY, a.[admit_date], a.[discharge_date]) AS [LOS_days]
--,c.[ip_type]
--,CASE WHEN f.[stay_no] IS NULL then 0 else 1 end as SBC_flag
FROM [bhrd].[au_facility_stay] AS a
LEFT JOIN [bhrd].[au_master] AS b
ON a.[auth_no] = b.[auth_no]
LEFT JOIN [bhrd].[ip_master] AS c
ON a.[auth_no] = c.[auth_no]
--LEFT JOIN [bhrd].[cc_facility_stay] AS f
--ON a.[stay_no] = f.[stay_no]
WHERE 1=1 
AND c.[ip_type] = 'I' 
--AND f.[stay_no] IS NULL --include SBC
AND b.[status_code] = 'AA'
AND (discharge_date between @StartDate and @EndDate
	or [admit_date] between @StartDate and @EndDate)
AND (b.kcid in (Select distinct kcid from ##kcid_list) 
	or b.kcid in (Select distinct kcid2 from ##kcid_list) )

ORDER BY kcid, admit_date,discharge_date

SELECT * FROM bhrd.cd_table where column_name='petition_type'

SELECT * FROM bhrd.cd_table where code_id in ('I','SV','V') order by column_name