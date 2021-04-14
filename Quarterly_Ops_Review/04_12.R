library(DBI)
library(BHRDtools)
library(dplyr)
#library(tidyr)
#library(stringr)
#library(odbc)
library(tidyverse)
library(readxl)
library(readr)

####################################################################
####SLIDE 1 AND SLIDE 3: SCREENSHOT FROM DASHBOARD



####################################################################
####SLIDE 4: 
##set up here
monthly_folder <- "202103"
cutoff_start <- "2020-02-28"
cutoff_end <- "2021-02-28"
##location
CCS_data_folder <- "Q:/SPE/aaReports/Regular/Crisis System/CSSUDR/Metrics_Aggregated"
data_folder <- paste(CCS_data_folder,monthly_folder,sep="/")
ITA_file <- paste(data_folder,"ITA.xlsx",sep="/")
ITA <- select(filter(read_excel(ITA_file,sheet=1),
                (met_abbr=="ITA_NEW_DETAINED" | met_abbr=="ITA_INVEST" )  & 
                report_date >= cutoff_start & 
                report_date <= cutoff_end),
              report_date,met_abbr,count)
library(tidyr)

##long to wide
ITA_count <- spread(ITA,met_abbr,count)

##calculation 
ITA_analysis <- ITA_count %>%
  rowwise() %>% 
  mutate (pct=ITA_NEW_DETAINED/ITA_INVEST)

########################################################################################
####SLIDE 2: DEMOGRAPHICS
##load census data
q_perf_dir <- "//Dchs-shares01/mhddata/SPE/Data transfer/Quarterly_Performance/"
census_file <- "KingCounty_DOH_censustracts_dashboard.xlsx"
Census <- read_excel(paste0(q_perf_dir,census_file),sheet="Data_short")

##load demographic for ITA iNvestigations aka CCS Assessment 

dsn <- "HHSAW_prod"
con <- DBI::dbConnect(odbc::odbc(), dsn = 'HHSAW_prod')

member_query <- "Select distinct kcid, datepart(year,[call_month]) as year
from ##ITA_line
where call_stamp >= '01/01/2019' and call_stamp <= '03/31/2021'
and investigation=1"
ITA_mbr <- dbGetQuery(con,member_query)

php96 <- DBI::dbConnect(odbc::odbc(), dsn = 'PHP96')
Member_demog <- BHRDtools::get_demographics(php96,localdata =ITA_mbr)

member_race_raw <- dplyr::select(Member_demog,kcid, Multiple_race,AIAN,Asian,BlackAA,MENA,NHPI,Other,Unknown_Race,White,hispanic)

##recode hispanic 
member_race_raw2 <- member_race_raw %>%
  dplyr::mutate(
    hisp = case_when(
        hispanic == "yes" ~ 1,
        hispanic == "no"| hispanic == "unknown" ~ 0,
        TRUE ~ 0.5), 
    unknown = case_when(
      Unknown_Race == 1 & (hispanic == "unknown" | hispanic == "yes" | hispanic == "no") ~ 1,
      Unknown_Race == 0 & hispanic == "unknown" ~ 1,
      Unknown_Race == 0 & (hispanic == "yes" | hispanic == "no") ~ 0,
      TRUE ~ 0.5)
    )
#check if there are any 0.5 here 
#test <- filter(member_race_raw2,unknown==0.5)

##sum race columns
member_race_raw3 <- member_race_raw2 %>%
  rowwise() %>%
  dplyr::mutate(
    sum_race=sum(c(AIAN,Asian,BlackAA,MENA,NHPI,Other,White,unknown))
  )

##define Muitple Race - NOT Hispanic
member_race_raw3 <- member_race_raw3 %>%
  dplyr::mutate(
    multiple_NH = case_when(
      (Multiple_race == 1 | sum_race > 1 ) & hisp == 1 ~ 0,
      (Multiple_race == 1 | sum_race > 1 ) & hisp == 0 ~ 1,
      Multiple_race == 0 & (sum_race == 0 | sum_race == 1) & ( hisp == 0 | hisp == 1) ~ 0, 
      TRUE ~ 0.5)
  )

#rm(member_race_raw3)

###select relevant columns only
member_race_raw4 <- member_race_raw3 %>%
  dplyr::select(kcid,hisp,multiple_NH,sum_race,AIAN,Asian,BlackAA,MENA,NHPI,White,Other,unknown)

##check if there are duplicated KCID    
#test <- distinct(select(member_race_raw4,kcid)) #no

##extract hispanic first
hispanic <- member_race_raw4 %>%
  filter(hisp ==1) %>%
  select(kcid) %>%
  mutate(race="Hispanic")

##extract not hispanic 
non_hisp <- member_race_raw4 %>%
  filter(hisp == 0) %>%
  select(kcid,multiple_NH,sum_race,AIAN,Asian,BlackAA,MENA,NHPI,White,Other,unknown)

##extract mixed, not hispanic
multi_nh <- non_hisp %>%
  filter(multiple_NH == 1) %>%
  select(kcid) %>%
  mutate(race="Multi-Race,NH")

## extract single race
single_race <- non_hisp %>%
  filter(multiple_NH == 0) %>%
  select(kcid,AIAN,Asian,BlackAA,MENA,NHPI,White,Other,unknown) 
#qa test <- filter (single_race,sum_race > 1)

single_race_def <- single_race %>%
  gather(race, cnt, AIAN:unknown) %>% 
  group_by(kcid) %>% 
  slice(which.max(cnt)) 

single_race_final <- distinct(select(single_race_def,kcid,race))

##combine hispanic, multi-race NH, single_RaceNh
all_race <- bind_rows(multi_nh,single_race_final,hispanic)

##join back with ITA_mbr 
ITA_mbr_race <- left_join(ITA_mbr,all_race,by="kcid")

summary <- ITA_mbr_race %>% 
  group_by(year,race) %>% 
  summarise(count=n_distinct(kcid))

##long to wide
summary_wide <- spread(summary ,year,count)
