---------------------------------
--Create person-level table for Behavioral Health condition status for 2019
--Uses RDA MH service penetration and SUD treatment penetration measures - select denominator criteria
--2-year lookback (thus 2018-2019 claims)
--Medicaid data
--2021-09
---------------------------------

--Create persistent table on tmp schema to hold person-level table for 2018-2019
--Run time: 3 min


drop table phclaims.tmp.mcaid_bh_rda_denom_person;

DECLARE @StartDate DATE;
DECLARE @EndDate DATE;

SELECT @StartDate = '2018-01-01'; 
SELECT @EndDate = '2019-12-31'; 

SELECT *
,@StartDate as from_date
,@EndDate as to_date
INTO phclaims.tmp.mcaid_bh_rda_denom_person
--INTO ##test
FROM
--BASED ON DIAGNOSIS (group certain substances into other based on exploratory analysis)
(SELECT DISTINCT a.id_mcaid,
    CASE when b.value_set_name = 'SUD-Dx-Value-Set' and b.sub_group in ('NA', 'Hallucinogen', 'Inhalant') then 'Other Substance'
		else b.sub_group
		end as indicator 
    FROM PHClaims.final.mcaid_claim_icdcm_header AS a 
    INNER JOIN (SELECT sub_group, code_set, code, value_set_name
    		FROM PHClaims.ref.rda_value_set_2021
    		WHERE value_set_name in ('MI-Diagnosis', 'SUD-Dx-Value-Set')
    		) AS b
    ON a.icdcm_norm = b.code --AND a.icdcm_version = b.icdcm_version
    WHERE a.first_service_date BETWEEN @StartDate AND @EndDate
) CTE

-- BASED ON PRESCRIPTIONS
UNION
SELECT *
,@StartDate as from_date
,@EndDate as to_date
FROM 
(SELECT DISTINCT a.id_mcaid, 
	CASE 
    WHEN b.sub_group = 'ADHD Rx' THEN 'ADHD'
    WHEN b.sub_group = 'Antianxiety Rx' THEN 'Anxiety'
    WHEN b.sub_group = 'Antidepressants Rx' THEN 'Depression'
    WHEN b.sub_group = 'Antimania Rx' THEN 'Mania/Bipolar'
    WHEN b.sub_group = 'Antipsychotic Rx' THEN 'Psychotic'
    END AS indicator
    FROM PHClaims.final.mcaid_claim_pharm as a
    INNER JOIN (
    	SELECT sub_group, code_set, code
    	FROM PHClaims.ref.rda_value_set_2021
    	WHERE value_set_name = 'Psychotropic-NDC') as b
    ON a.ndc = b.code
    WHERE a.rx_fill_date between @StartDate AND @EndDate
) CTE2
    
     

	select top 1000 * from phclaims.tmp.mcaid_bh_rda_denom_person

	select indicator, count(id_mcaid) as cnt from phclaims.tmp.mcaid_bh_rda_denom_person
	group by indicator
	order by count(id_mcaid) desc
	select count(id_mcaid) from phclaims.tmp.mcaid_bh_rda_denom_person
	SELECT DISTINCT indicator from phclaims.tmp.mcaid_bh_rda_denom_person