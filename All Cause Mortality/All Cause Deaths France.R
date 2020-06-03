rm(list=ls())

library(tidyverse)
library(curl)
library(readxl)
library(lubridate)
library(forcats)
library(ggtext)

#Read in historic French mortality data for 2010-18
#Source: https://www.insee.fr/fr/information/4190491
temp <- tempfile()
temp2 <- tempfile()
source <- "https://www.insee.fr/fr/statistiques/fichier/4190491/deces-2010-2018-csv.zip"
temp <- curl_download(url=source, destfile=temp, quiet=FALSE, mode="wb")
unzip(zipfile=temp, exdir=temp2)
data10 <- read.csv(file.path(temp2, "deces-2010.csv"), sep=";")
data11 <- read.csv(file.path(temp2, "deces-2011.csv"), sep=";")
data12 <- read.csv(file.path(temp2, "deces-2012.csv"), sep=";")
data13 <- read.csv(file.path(temp2, "deces-2013.csv"), sep=";")
data14 <- read.csv(file.path(temp2, "deces-2014.csv"), sep=";")
data15 <- read.csv(file.path(temp2, "deces-2015.csv"), sep=";")
data16 <- read.csv(file.path(temp2, "deces-2016.csv"), sep=";")
data17 <- read.csv(file.path(temp2, "deces-2017.csv"), sep=";")
data <- bind_rows(data10, data11, data12, data13, data14, data15, data16, data17)[,c(2,3,7)]
colnames(data) <- c("sex", "dob", "dod")

#Some dates of Birth, particularly older ones are missing days and months. Allocate these randomly.
data$dob <- as.character(data$dob)
data$yob <- as.numeric(substr(data$dob, 1, 4))
data$dob <- as.Date(data$dob, format=c("%Y%m%d"))
data$temp <- as.Date(paste0(data$yob, "-01-01"))
data$temp2 <- data$temp+round(runif(nrow(data), min=-0.49, max=365.49))
data$dob <- if_else(is.na(data$dob) & data$yob!=0, data$temp2, data$dob)

data$dod <- as.character(data$dod)

#remove very small number of dates of death which are too short
data <- subset(data, nchar(data$dod, type="chars")==8)[,c(1:3)]

data$dod <- as.Date(data$dod, format=c("%Y%m%d"))
data$age <- floor(time_length(difftime(data$dod, data$dob), "years"))

#remove a few other weird cases
data <- subset(data, age>=-1 & age<=120)

#categorise age
data$ageband <- case_when(
  data$age<15 ~ "0-14",
  data$age<65 ~ "15-64",
  data$age<75 ~ "65-74",
  data$age<85 ~ "75-84",
  TRUE ~ "85+")

#Tidy up sex variable
data$sex <- if_else(data$sex==1, "Male", "Female")

#Bring in deaths data for 2020
temp <- tempfile()
temp2 <- tempfile()
source <- "https://www.insee.fr/en/statistiques/fichier/4493808/2020-05-29_detail.zip"
temp <- curl_download(url=source, destfile=temp, quiet=FALSE, mode="wb")
unzip(zipfile=temp, exdir=temp2)
data1820 <- read.csv(file.path(temp2, "DC_jan2018-mai2020_det.csv"), sep=";")

#Set up dates
data1820$MNAIS <- as.character(formatC(data1820$MNAIS, width=2, format="d", flag="0"))
data1820$JNAIS <- as.character(formatC(data1820$JNAIS, width=2, format="d", flag="0"))
data1820$dob <- as.Date(paste0(data1820$ANAIS, data1820$MNAIS, data1820$JNAIS), format=c("%Y%m%d"))

data1820$MDEC <- as.character(formatC(data1820$MDEC, width=2, format="d", flag="0"))
data1820$JDEC <- as.character(formatC(data1820$JDEC, width=2, format="d", flag="0"))
data1820$dod <- as.Date(paste0(data1820$ADEC, data1820$MDEC, data1820$JDEC), format=c("%Y%m%d"))

data1820$age <- floor(time_length(difftime(data1820$dod, data1820$dob), "years"))
data1820$sex <- if_else(data1820$SEXE=="M", "Male", "Female")

data1820 <- data1820[,c(12:15)]

#categorise age
data1820$ageband <- case_when(
  data1820$age<15 ~ "0-14",
  data1820$age<65 ~ "15-64",
  data1820$age<75 ~ "65-74",
  data1820$age<85 ~ "75-84",
  TRUE ~ "85+")

#Merge all years
fulldata <- bind_rows(data, data1820)

fulldata$year <- year(fulldata$dod)
fulldata$week <- week(fulldata$dod)

#Aggregate to weekly data
aggdata <- fulldata %>%
  group_by(ageband, year, week, sex) %>%
  filter(year>=2010) %>%
  summarise(deaths=n())

#Combines sexes for saving later
data.FR <- aggdata %>%
  group_by(ageband, year, week) %>%
  summarise(deaths=sum(deaths))

#Save data
write.csv(data.FR, "Data/deaths_age_France.csv")

#Calculate 2010-19 average, min and max
hist.data <- aggdata %>%
  filter(year!=2020) %>%
  group_by(ageband, sex, week) %>%
  summarise(mean_d=mean(deaths), max_d=max(deaths), min_d=min(deaths))

aggdata <- merge(hist.data, subset(aggdata, year==2020), all.x=TRUE, all.y=TRUE)

#Calculate excess deaths in 2020 vs. historic mean
excess <- aggdata %>%
  group_by(ageband, sex) %>%
  filter(!is.na(deaths)) %>%
  summarise(deaths=sum(deaths), mean=sum(mean_d))

excess$excess <- excess$deaths-excess$mean
excess$prop <- excess$excess/excess$mean

ann_text <- data.frame(week=rep(20, times=10), 
                       position=c(600,300,1000,1700,1100,1400,1800,2000,4000,2500), 
                       sex=rep(c("Female", "Male"), times=5),
                       ageband=rep(c("0-14", "15-64", "65-74", "75-84", "85+"), each=2))

tiff("Outputs/ExcessDeathsFrancexAge.tiff", units="in", width=16, height=6, res=300)
ggplot(aggdata)+
  geom_ribbon(aes(x=week, ymin=min_d, ymax=max_d), fill="Skyblue2")+
  geom_ribbon(aes(x=week, ymin=mean_d, ymax=deaths), fill="Red", alpha=0.2)+
  geom_line(aes(x=week, y=mean_d), colour="Grey50", linetype=2)+
  geom_line(aes(x=week, y=deaths), colour="Red")+
  scale_x_continuous(name="Week number")+
  scale_y_continuous("Weekly deaths recorded")+
  facet_grid(sex~ageband, scales="free_y")+
  geom_text(data=ann_text, aes(x=week, y=position), label=c(
    paste0(round(excess[1,5],0)," excess deaths in 2020\nvs. 2010-19 mean (", round(excess[1,6]*100,0),"%)"),
    paste0(round(excess[2,5],0)," deaths (", round(excess[2,6]*100,0),"%)"),
    paste0(round(excess[3,5],0)," deaths (", round(excess[3,6]*100,0),"%)"),
    paste0(round(excess[4,5],0)," deaths (", round(excess[4,6]*100,0),"%)"),
    paste0("+",round(excess[5,5],0)," deaths (+", round(excess[5,6]*100,0),"%)"),
    paste0("+",round(excess[6,5],0)," deaths (+", round(excess[6,6]*100,0),"%)"),
    paste0(round(excess[7,5],0)," deaths (", round(excess[7,6]*100,0),"%)"),
    paste0("+",round(excess[8,5],0)," deaths (+", round(excess[8,6]*100,0),"%)"),
    paste0("+",round(excess[9,5],0)," deaths (+", round(excess[9,6]*100,0),"%)"),
    paste0("+",round(excess[10,5],0)," deaths (+", round(excess[10,6]*100,0),"%)")),
            size=3.5, colour="Red", hjust=0)+
  theme_classic()+
  theme(strip.background=element_blank(), strip.text=element_text(size=rel(1), face="bold"), 
        plot.subtitle =element_markdown(), plot.title=element_markdown())+
  labs(title="Mortality rates in France in people of working age have <i style='color:black'>fallen</i> during the pandemic",
       subtitle="Weekly deaths in <span style='color:red;'>2020</span> compared to <span style='color:Skyblue4;'>the range in 2010-19</span>.",
       caption="Date from Insee | Plot by @VictimOfMaths")
dev.off()