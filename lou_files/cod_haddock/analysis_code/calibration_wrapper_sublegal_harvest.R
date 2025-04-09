
#This file pulls in the data from step 1, i.e., the differences between model simulated harvest 
#and MRIP estimates of harvest, and re-runs the calibration model but this time adjusts per-trip
#outcomes until simulated harvest in numbers of fish is within 5% or 500 fish of the MRIP estimate. 

baseline_output0<-readRDS(file.path(input_data_cd, "harvest_differences.rds")) 

n_distinct(baseline_output0$draw)


#l_w_conversion =
cod_lw_a = 0.000005132
cod_lw_b = 3.1625
had_lw_a = 0.000009298
had_lw_b = 3.0205

Disc_mort<- readr::read_csv(file.path(input_data_cd, "Discard_Mortality.csv"), show_col_types = FALSE)


for(i in unique(baseline_output0$mrip_index)){
  
  p_cod_kp_2_rl<-0
  p_cod_rl_2_kp<-0
  p_hadd_kp_2_rl<-0
  p_hadd_rl_2_kp<-0
  

  source(file.path("C:\Users\andrew.carr-harris\Desktop\Git\rdmtool\lou_files\cod_haddock\analysis_code", "calibrate_rec_catch_sublegal_harvest.R"))
 
  
  
  ##Uncomment this if you want calibration catch weights
  #source(file.path(code_cd, "calibration_catch_weights2.R"))
  
}


baseline_output0<-readRDS(file.path(input_data_cd, "harvest_differences_check.rds")) 

n_distinct(baseline_output0$draw)

check1<-data.frame() 
check2<-data.frame() 

for(i in unique(baseline_output0$mrip_index)){
  
  check0<-baseline_output0 %>% dplyr::filter(mrip_index==i)
  
  season1<-unique(check0$open)
  mode1<-unique(check0$mode)
  draw1<-unique(check0$draw)
  
  check1 <- feather::read_feather(file.path(iterative_input_data_cd, paste0("comparison_", mode1,"_", season1, "_", draw1, ".feather")))  
  check2<-rbind(check1, check2)
  
}


baseline<- readRDS(file.path(input_data_cd, "harvest_differences_check.rds")) %>% 
  dplyr::select(cod_keep_2_release, cod_release_2_keep, hadd_keep_2_release, hadd_release_2_keep, draw, 
                mode, mrip_index, diff_cod_harv, diff_hadd_harv, tot_cod_catch_model, tot_hadd_catch_model, 
                tot_keep_cod_model, tot_keep_hadd_model, tot_rel_cod_model, tot_rel_hadd_model) 
colnames(baseline) <- gsub("_model", "_model_base", colnames(baseline))
colnames(baseline) <- gsub("_harv", "_harv_base", colnames(baseline))

check2<-check2 %>% 
  dplyr::left_join(baseline, by=c("draw", "mode", "mrip_index")) %>% 
  dplyr::mutate(tab=case_when((cod_achieved==0 | hadd_achieved==0)~1, TRUE~0)) %>% 
  dplyr::group_by(draw) %>% 
  dplyr::mutate(sumtab=sum(tab)) %>% 
  dplyr::filter(sumtab==0)

n_distinct(check2$draw)

check3<-check2 %>% 
  dplyr::filter((abs_perc_diff_cod_harv>5 & abs(diff_cod_harv)>500) | (abs_perc_diff_hadd_harv>5 & abs(diff_hadd_harv)>500))

saveRDS(check2, file = file.path(input_data_cd, "calibration_comparison.rds"))
n_distinct(check2$draw)


##Now we have the data for the projections stored in input_data_cd:
#pds_new_x = number of choice occasion
#comparison_x = percent of choice occasions the keep all harvest/release all harvest 
#costs_x = baseline catch levels, trip costs, and demographics. 




##Uncomment this if you want calibration catch weights
#Compile the calibration catch weights
# check1a<-data.frame()
# check2a<-data.frame()
# 
# for(i in unique(check2$mrip_index)){
#   check0a<- check2 %>% dplyr::filter(mrip_index==i)
# 
#   season1<-unique(check0a$open)
#   mode1<-unique(check0a$mode)
#   draw1<-unique(check0a$draw)
# 
#   check1a<- readRDS(file.path(iterative_input_data_cd, paste0("calibrate_catch_wts_", mode1,"_", season1, "_", draw1, ".rds")))
#   check2a<-rbind(check1a, check2a)
# 
# }
# n_distinct(check2a$run)

# write_xlsx(check2a, file.path(input_data_cd, "calibration_catch_weights_cm.xlsx"))

