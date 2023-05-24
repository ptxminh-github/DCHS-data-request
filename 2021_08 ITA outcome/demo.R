rm(list=ls()) # Clear objects from Memory
cat("\014") # Clear Console

library(DBI)
library(BHRDtools)
library(dplyr)
#library(tidyr)
#library(stringr)
#library(odbc)
library(tidyverse)
library(readxl)
library(readr)
library(tidyr)
library(writexl)

q_perf_dir <- "//Dchs-shares01/mhddata/SPE/Data transfer/Quarterly_Performance/"
census_file <- "KingCounty_DOH_censustracts_dashboard.xlsx"
Census <- read_excel(paste0(q_perf_dir,census_file),sheet="Data_short")

##load demographic for ITA detained

dsn <- "HHSAW_prod"
con <- DBI::dbConnect(odbc::odbc(), dsn = 'HHSAW_prod')

member_query <- "

select distinct kcid from ##ita_repeat where max_ita > 1 "
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
  group_by(race) %>% 
  summarise(count=n_distinct(kcid))



##### CALCULATE AGE
member_query2 <- "
SELECT distinct kcid, CAST(call_stamp as DATE) as call_date FROM ##ITA_line  where kcid in (select distinct KCID from ##ita_repeat where max_ita > 1) and cnt = 1 order by kcid "
ITA_mbr2 <- dbGetQuery(con,member_query2)

calc_age <- function(birthDate, refDate = Sys.Date()) {
  require(lubridate)
  period <- as.period(interval(birthDate, refDate),
                      unit = "year")
  period$year
} 

ITA_mbr2 <- ITA_mbr2 %>%
  dplyr::left_join(Member_demog, by='kcid') %>%
  dplyr::select(kcid, dob, call_date) %>% 
  dplyr::mutate(age=calc_age(birthDate=dob,refDate=call_date)) %>%
  dplyr::mutate(age_group = case_when(
    age <18 ~ "<18",
    age >= 18 & age < 25 ~ "18-24",
    age >= 25 & age < 35 ~ "25-34",
    age >= 35 & age < 45 ~ "35-44",
    age >= 45 & age < 55 ~ "45-54", 
    age >= 55 & age < 65 ~ "55-64",
    age >= 65 ~ "65+",
    TRUE ~ "0.5"))
rm(ITA_mbr2)


summary_age <- ITA_mbr2 %>% 
  group_by(age_group) %>% 
  summarise(count=n_distinct(kcid))

## export
output_path = 'C:/Users/xphan/Repos/data-request/2021_08 ITA outcome'
write_xlsx(list("detained_demo"=summary, "census"=Census, "age"=summary_age)
           ,paste(output_path,"demo_0816.xlsx",sep = "/")) 