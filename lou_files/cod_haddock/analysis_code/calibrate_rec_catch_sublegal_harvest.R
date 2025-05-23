
#This is the simulation model for the calibration year WITH adjustments for illegal harvest or voluntary release


MRIP_data2<- readRDS(file.path(input_data_cd, "MRIP_simulated_data.rds")) %>% 
  dplyr::filter(mrip_index==i)



select_mode = unique(MRIP_data2$mode)
select_season = unique(MRIP_data2$open)

MRIP_stats<-MRIP_data2 %>% 
  dplyr::rename(tot_cod_catch_mrip=tot_cod_catch, 
                tot_cod_keep_mrip= tot_cod_keep, 
                tot_cod_rel_mrip=tot_cod_rel, 
                tot_hadd_catch_mrip=tot_hadd_catch, 
                tot_hadd_keep_mrip=tot_hadd_keep, 
                tot_hadd_rel_mrip=tot_hadd_rel, 
                dtrip_mrip=dtrip) 

k<- MRIP_data2$draw

n_drawz = 50
n_catch_draws = 30
set.seed(k)


directed_trips<-directed_trips<-read_feather(file.path(input_data_cd, "directed_trips_calib_150draws_cm.feather")) %>%
  tibble::tibble() %>%
  dplyr::filter(draw == k,
                mode == select_mode) %>%
  dplyr::mutate(open = dplyr::case_when(cod_bag > 0 ~ 1, TRUE ~ 0))



#Create as an object the minimum size at which fish are illegally harvested.
#1) This floor_subl_harvest size will be 2 inches below the minimum size, by mode. 
#1a) If the minimum size changes across the season, floor_subl_harvest=min(min_size). 
#2) If the fishery is closed the entire season, floor_subl_harvest=mean(catch_length)-0.5*sd(catch_length). 
#1) and #1a) below:

floor_subl_cod_harv<-min(directed_trips$cod_min)-2*2.54
floor_subl_hadd_harv<-min(directed_trips$hadd_min)-2*2.54


open<- directed_trips %>%
  dplyr::mutate(day = as.numeric(stringr::str_extract(day, '\\d{2}')),
                period2 = paste0(month, "_", day, "_", mode)) %>%
  dplyr::select(period2, open) %>%
  dplyr::filter(open == select_season)

directed_trips<- directed_trips %>%
  dplyr::mutate(day = as.numeric(stringr::str_extract(day, '\\d{2}')),
                period2 = paste0(month, "_", day, "_", mode)) %>%
  dplyr::filter(open == select_season)


######################################
##   Begin simulating trip outcomes ##
######################################

# Set up an output file for the separately simulated within-season regulatory periods
directed_trips_p <- directed_trips %>%
  dplyr::mutate(month = as.numeric(month)) %>%
  dplyr::mutate(n_draws = n_drawz)%>%
  dplyr::select(!c(month, mode))

regs <- directed_trips_p %>%
  dplyr::select(period2,
                cod_bag,
                cod_min,
                hadd_bag,
                hadd_min)

param_draws <- directed_trips_p %>%
  dplyr::select(period2, n_draws, open) %>%
  tidyr::uncount(n_draws) 


cod_catch_data <- feather::read_feather(file.path(iterative_input_data_cd, paste0("catch_draws", k, "_full.feather"))) %>%  
  dplyr::mutate(period2=paste0(month, "_", day1, "_", mode)) %>%  
  dplyr::left_join(open, by = "period2") %>%
  dplyr::filter(open == select_season) %>%
  dplyr::select(!open, !day) %>%
  dplyr::rename(tot_cod_catch = cod_catch,
                tot_had_catch = hadd_catch)  %>%
  dplyr::select(mode,month,tot_cod_catch,tot_had_catch,
                tripid,catch_draw,day, draw, age,  cost, period2)

##pull in choice experiment demographics
ids<-cod_catch_data %>% 
  dplyr::select(tripid, period2) %>% 
  dplyr::distinct(tripid, period2, .keep_all = FALSE) %>% 
  dplyr::mutate(id2=row_number())

n_ids<-nrow(ids)

angler_dems <- read.csv(file.path(input_data_cd,"angler CE demographics.csv")) %>% 
  dplyr::slice(rep(row_number(), each = round(n_ids/448+5))) %>% 
  dplyr::mutate(uniform=runif(n(), min=0, max=1)) %>% 
  dplyr::arrange(uniform)

angler_dems<- angler_dems %>% 
  dplyr::mutate(id2=1:nrow(angler_dems)) %>% 
  dplyr::filter(id2<=n_ids) %>% 
  dplyr::left_join(ids, by=c("id2")) %>% 
  dplyr::select(-id2, -id, -uniform)

cod_catch_data<-cod_catch_data %>% 
  dplyr::left_join(angler_dems, by=c("tripid", "period2"))

angler_dems<-cod_catch_data %>% 
  dplyr::filter(mode == select_mode) %>%
  dplyr::select(fish_pref_more, likely_to_fish)

trip_costs<-cod_catch_data  %>%
  dplyr::filter(mode == select_mode) %>%
  dplyr::select(cost)

age<-cod_catch_data  %>%
  dplyr::filter(mode == select_mode) %>%
  dplyr::select(age)



cod_catch_data <- cod_catch_data %>%
  dplyr::mutate(day = as.numeric(stringr::str_extract(day, "\\d+"))) %>%
  dplyr::group_by(period2) %>%
  dplyr::slice_sample(n = n_drawz*n_catch_draws, replace = TRUE)   %>%
  dplyr::mutate(#period = rep(period_vec$period2, each = nsamp),
    catch_draw = rep(1:n_catch_draws, length.out = n_drawz*n_catch_draws),
    tripid = rep(1:n_drawz, each=n_catch_draws)) %>%
  dplyr::ungroup()%>%
  dplyr::select(!c(age, fish_pref_more, likely_to_fish, cost))%>%
  dplyr::select(!c(month))


if(select_season == 1){
  seas = "open"
}
if(select_season == 0){
  seas = "closed"
}

cod_size_data <- size_data_read %>% 
  dplyr::filter(species == "cod", season == seas) %>% 
  dplyr::filter(!is.na(fitted_prob)) %>% 
  dplyr::select(-observed_prob,-sum_nfish_catch, -nfish_catch_from_fitted, -nfish_catch_from_raw, -domain)

had_size_data <- size_data_read %>% 
  dplyr::filter(species == "hadd", season == seas) %>% 
  dplyr::filter(!is.na(fitted_prob)) %>% 
  dplyr::select(-observed_prob,-sum_nfish_catch, -nfish_catch_from_fitted, -nfish_catch_from_raw, -domain)


cod_had_catch_data <- cod_catch_data


# subset trips with zero catch, as no size draws are required
cod_zero_catch <- dplyr::filter(cod_catch_data, tot_cod_catch == 0)


#Check to see if there is no catch for either species and if so, pipe code around keep/release determination
cod_catch_check<-base::sum(cod_catch_data$tot_cod_catch)
had_catch_check<-base::sum(cod_catch_data$tot_had_catch)


if(cod_catch_check ==0 & had_catch_check==0){
  trip_data<-cod_catch_data
  trip_data<- trip_data %>% 
    dplyr::mutate(domain2 = paste0(period2, "_", catch_draw, "_", tripid)) %>% 
    dplyr::select(-mode)
  
  
  trip_data$tot_keep_cod_new<-0
  trip_data$tot_rel_cod_new<-0
  
  
  trip_data$tot_keep_hadd_new<-0
  trip_data$tot_rel_hadd_new<-0
  
  n_sub_had_kept<-0
  n_sub_cod_kept<-0
  n_legal_hadd_rel<-0
  n_legal_cod_rel<-0
}

#########################
###  Cod  ####
#########################

if(cod_catch_check !=0){
  
  #keep trips with positive cod catch
  cod_catch_data <- dplyr::filter(cod_catch_data, tot_cod_catch > 0)
  
  row_inds <- seq_len(nrow(cod_catch_data))
  
  cod_catch_data<-cod_catch_data %>%
    dplyr::slice(rep(row_inds,tot_cod_catch))   %>%
    dplyr::mutate(fishid=dplyr::row_number())
  
  # generate lengths for each fish
  catch_size_data <- cod_catch_data %>%
    dplyr::mutate(fitted_length = sample(cod_size_data$length,
                                         nrow(.),
                                         prob = cod_size_data$fitted_prob,
                                         replace = TRUE)) 
  
  
  
  #Create as an object the minimum size at which fish are illegally harvested.
  #1) This floor_subl_harvest size will be 2 inches below the minimum size, by mode. 
  #1a) If the minimum size changes across the season, floor_subl_harvest=min(min_size). 
  #2) If the fishery is closed the entire season, floor_subl_harvest=mean(catch_length)-0.5*sd(catch_length). 
  #2) below:
  if (floor_subl_cod_harv>=248){
    
    floor_subl_cod_harv=mean(catch_size_data$fitted_length)-0.5*sd(catch_size_data$fitted_length)
    
  }
  
  # Impose regulations, calculate keep and release per trip
  # For summer flounder, retain keep- and release-at-length
  ####### Start Here #################
  
  ############# Length #####################################
  catch_size_data <- catch_size_data %>%
    dplyr::left_join(regs, by = c("period2")) %>%
    dplyr::mutate(posskeep = ifelse(fitted_length>=cod_min ,1,0)) %>%
    dplyr::group_by(tripid, period2, catch_draw) %>%
    dplyr::mutate(csum_keep = cumsum(posskeep)) %>%
    dplyr::ungroup() %>%
    dplyr::mutate(
      keep_adj = dplyr::case_when(
        cod_bag > 0 ~ ifelse(csum_keep<=cod_bag & posskeep==1,1,0),
        TRUE ~ 0))
  
  
  catch_size_data <- catch_size_data %>%
    dplyr::mutate_if(is.numeric, tidyr::replace_na, replace = 0)
  
  catch_size_data <- catch_size_data %>%
    dplyr::mutate(keep = keep_adj,
                  release = ifelse(keep==0,1,0))
  
  catch_size_data<- catch_size_data %>%
    dplyr::select(fishid, fitted_length, tripid, keep, release, period2, catch_draw, mode, cod_bag, cod_min)  %>%
    dplyr::rename(mode1=mode) %>% 
    dplyr::mutate(floor_subl_cod_harv_indicator=case_when(release==1 & fitted_length>=floor_subl_cod_harv~1,TRUE~0))
  
  
  sum_cod_rel<-sum(catch_size_data$release)
  sum_cod_keep<-sum(catch_size_data$keep)
  
  sum(catch_size_data$release)
  sum(catch_size_data$keep)  
  ##Now reallocate a portion of all releases as kept if needed 
 
  
  ##Now reallocate a portion of all keeps as releases if needed 
  
  
  #length data 
  catch_size_data <- as.data.table(catch_size_data)
  new_size_data <- catch_size_data[, .(
    keep = sum(keep),
    release = sum(release)
  ), by = .(period2, catch_draw, tripid, fitted_length)]
  
  
  
  keep_size_data <- new_size_data %>%
    dplyr::select(-release) %>%
    tidyr::pivot_wider(names_from = fitted_length, #_length,
                       names_glue = "keep_cod_{fitted_length}",
                       names_sort = TRUE,
                       values_from = keep,
                       values_fill = 0)
  
  release_size_data <- new_size_data %>%
    dplyr::select(-keep) %>%
    tidyr::pivot_wider(names_from = fitted_length, #_length,
                       names_glue = "release_cod_{fitted_length}",
                       names_sort = TRUE,
                       values_from = release,
                       values_fill = 0)
  
  keep_release_cod <- keep_size_data %>%
    dplyr::left_join(release_size_data, by = c("period2",  "tripid", "catch_draw"))
  
  
  
  #trip data 
  trip_data <- catch_size_data %>%
    dplyr::group_by(period2, catch_draw, tripid) %>% 
    dplyr::summarize(tot_keep_cod_new = sum(keep),
                     tot_rel_cod_new = sum(release),
                     .groups = "drop") %>%
    dplyr::ungroup()
  
  
  cod_zero_catch<-cod_zero_catch %>%
    dplyr::select(tripid, catch_draw, period2) %>%
    dplyr::mutate(tot_keep_cod_new=0,
                  tot_rel_cod_new=0)
  
  trip_data <- dplyr::bind_rows(trip_data, cod_zero_catch) %>%
    dplyr::mutate_if(is.numeric, tidyr::replace_na, replace = 0) %>%
    dplyr::select(c("period2", "catch_draw","tripid",
                    "tot_keep_cod_new","tot_rel_cod_new"))
  
  
  trip_data<- trip_data %>% dplyr::mutate(domain2 = paste0(period2, "_", catch_draw, "_", tripid))
  trip_data<-data.table::as.data.table(trip_data)
  data.table::setkey(trip_data, "domain2")
}

#if there is catch of only haddock
if (cod_catch_check==0 & had_catch_check!=0){
  trip_data<-cod_catch_data
  trip_data<- trip_data %>% 
    dplyr::mutate(domain2 = paste0(period2, "_", catch_draw, "_", tripid)) %>% 
    dplyr::select(-mode) %>% 
    as.data.table()
  
  data.table::setkey(trip_data, "domain2")
  
  trip_data$tot_keep_cod_new<-0
  trip_data$tot_rel_cod_new<-0
  
  
  n_sub_cod_kept<-0
  n_legal_cod_rel<-0
}



#########################
###  Haddock  ####
#########################

if (had_catch_check!=0){
  # subset trips with zero catch, as no size draws are required
  had_zero_catch <- dplyr::filter(cod_had_catch_data, tot_had_catch == 0)
  
  #keep trips with positive catch
  had_catch_data <- dplyr::filter(cod_had_catch_data, tot_had_catch > 0)
  
  #expand the sf_catch_data so that each row represents a fish
  row_inds <- seq_len(nrow(had_catch_data))
  
  had_catch_data<- had_catch_data %>%
    dplyr::slice(rep(row_inds,tot_had_catch))
  
  rownames(had_catch_data) <- NULL
  had_catch_data$fishid <- 1:nrow(had_catch_data)
  
  # # generate lengths for each fish
  catch_size_data_had <- had_catch_data %>%
    dplyr::mutate(fitted_length = sample(had_size_data$length,
                                         nrow(.),
                                         prob = had_size_data$fitted_prob,
                                         replace = TRUE)) #%>%    dplyr::arrange(period2, tripid, catch_draw)
  
  
  #Create as an object the minimum size at which fish are illegally harvested.
  #1) This floor_subl_harvest size will be 2 inches below the minimum size, by mode. 
  #1a) If the minimum size changes across the season, floor_subl_harvest=min(min_size). 
  #2) If the fishery is closed the entire season, floor_subl_harvest=mean(catch_length)-0.5*sd(catch_length). 
  #2) below:
  if (floor_subl_hadd_harv>=248){
    
    floor_subl_hadd_harv=mean(catch_size_data_had$fitted_length)-0.5*sd(catch_size_data_had$fitted_length)
    
  }
  
  
  # Impose regulations, calculate keep and release per trip
  # For summer flounder, retain keep- and release-at-length
  ####### Start Here #################
  
  ############# Length #####################################
  catch_size_data_had <- catch_size_data_had %>%
    dplyr::left_join(regs, by = c("period2")) %>%
    dplyr::mutate(posskeep = ifelse(fitted_length>=hadd_min ,1,0)) %>%
    dplyr::group_by(tripid, period2, catch_draw) %>%
    dplyr::mutate(csum_keep = cumsum(posskeep)) %>%
    dplyr::ungroup() %>%
    dplyr::mutate(
      keep_adj = dplyr::case_when(
        hadd_bag > 0 ~ ifelse(csum_keep<=hadd_bag & posskeep==1,1,0),
        TRUE ~ 0))
  catch_size_data_had<-catch_size_data_had %>% 
    dplyr::arrange(period2, tripid, catch_draw, fishid)
  
  catch_size_data_had <- catch_size_data_had %>%
    dplyr::mutate_if(is.numeric, tidyr::replace_na, replace = 0)
  
  catch_size_data_had <- catch_size_data_had %>%
    dplyr::mutate(keep = keep_adj,
                  release = ifelse(keep==0,1,0))
  
  catch_size_data_had<- catch_size_data_had %>%
    dplyr::select(fishid, fitted_length, tripid, keep, release, period2, catch_draw, mode, hadd_bag, hadd_min)  %>%
    dplyr::rename(mode1=mode) %>% 
    dplyr::mutate(floor_subl_hadd_harv_indicator=case_when(release==1 & fitted_length>=floor_subl_hadd_harv~1,TRUE~0))
  
  sum_hadd_rel<-sum(catch_size_data_had$release)
  sum_hadd_kept<-sum(catch_size_data_had$keep)
  
  sum(catch_size_data_had$release)
  sum(catch_size_data_had$keep)
  
  ##Now reallocate a portion of all releases as kept if needed 
  if (hadd_release_2_keep==1 & sum_hadd_rel>0){
    
    
    catch_size_data_had_re_allocate<- catch_size_data_had %>%
      dplyr::filter(floor_subl_hadd_harv_indicator==1) %>% 
      dplyr::select(-mode1, -hadd_bag, -hadd_min)
    
    catch_size_data_had_re_allocate_base<- catch_size_data_had %>%
      dplyr::filter(floor_subl_hadd_harv_indicator==0) %>% 
      dplyr::select(-mode1, -hadd_bag, -hadd_min)
    
    catch_size_data_had_re_allocate <- catch_size_data_had_re_allocate %>% 
      dplyr::mutate(uniform=runif(n(), min=0, max=1)) %>% 
      dplyr::arrange(uniform) 
    
    n_row_had_re_allocate<-nrow(catch_size_data_had_re_allocate)
    n_sub_had_kept=round(h_star_hadd_release_to_keep_variable*n_row_had_re_allocate)  
    
    catch_size_data_had_re_allocate <- catch_size_data_had_re_allocate %>% 
      dplyr::mutate(fishid2=1:n_row_had_re_allocate) %>% 
      dplyr::mutate(keep_new=case_when(fishid2<=n_sub_had_kept~1, TRUE~ 0))
    
    catch_size_data_had_re_allocate <- catch_size_data_had_re_allocate %>% 
      dplyr::mutate(rel_new=case_when(keep_new==0~1, TRUE~ 0)) %>% 
      dplyr::select(-keep, -release, -uniform, -fishid2, -uniform) %>% 
      dplyr::rename(keep=keep_new, release=rel_new)
    
    
    setDT(catch_size_data_had_re_allocate)
    catch_size_data_had_re_allocate <- catch_size_data_had_re_allocate[order(tripid, period2, catch_draw, fishid)][
      , `:=`(
        csum_keep = cumsum(keep),               # Calculate cumulative sum of keep
        bag_cutoff =  5                         # Define bag cutoff
      ), by = .(tripid, period2, catch_draw)][
        , `:=`(
          release_new = as.integer(csum_keep > bag_cutoff | release == 1), # Update release flag
          keep_new = as.integer(!(csum_keep > bag_cutoff | release == 1))  # Update keep flag
        )][, .(tripid, period2, fitted_length, floor_subl_hadd_harv_indicator, catch_draw, fishid, keep = keep_new, release = release_new)] # Select and rename]
    
    catch_size_data_had_re_allocate<-catch_size_data_had_re_allocate %>% 
      dplyr::arrange(period2, tripid, catch_draw) #%>% 
    #dplyr:::filter(csum_keep>3)
    
    catch_size_data_had<- rbind.fill(catch_size_data_had_re_allocate,catch_size_data_had_re_allocate_base) %>% 
      dplyr::select(-floor_subl_hadd_harv_indicator)
    
    sum(catch_size_data_had$release)
    sum(catch_size_data_had$keep)
    
    
    n_legal_hadd_rel<-0
    
    
    
  }
  
  ##Now reallocate a portion of all keeps as releases if needed 
  if (hadd_keep_2_release==1 & sum_hadd_kept>0){
    
    #If all hadd kept must be release, all_hadd_keep_2_release==1
    if (all_hadd_keep_2_release==1){
      
      catch_size_data_had<-catch_size_data_had %>% 
        dplyr::mutate(rel_new = keep+release, 
                      keep_new = 0) %>% 
        dplyr::select(-keep, -release) %>% 
        dplyr::rename(release=rel_new,  keep=keep_new) 
      
      n_sub_had_kept<-0
      n_legal_hadd_rel<-sum(catch_size_data_had$release+catch_size_data_had$keep) 
    }
    
    
    #If not all hadd kept must be release, all_hadd_keep_2_release==0
    if (all_hadd_keep_2_release==0){
      
      catch_size_data_had_re_allocate<- catch_size_data_had %>%
        dplyr::filter(keep==1)
      
      catch_size_data_had_re_allocate_base<- catch_size_data_had %>%
        dplyr::filter(keep==0) 
      
      sum_keep_hadd_re_allocate=sum(catch_size_data_had_re_allocate$keep)
      n_row_had_re_allocate<-nrow(catch_size_data_had_re_allocate)
      
      catch_size_data_had_re_allocate<-catch_size_data_had_re_allocate %>% 
        dplyr::mutate(uniform=runif(n_row_had_re_allocate)) %>%
        dplyr::arrange(uniform) %>% 
        dplyr::mutate(fishid2=1:n_row_had_re_allocate)
      
      n_legal_hadd_rel=round(h_star_hadd_keep_to_release_variable*n_row_had_re_allocate)
      
      catch_size_data_had_re_allocate<-catch_size_data_had_re_allocate %>% 
        dplyr::mutate(rel_new=dplyr::case_when(fishid2<=n_legal_hadd_rel~1, TRUE~ 0))
      
      catch_size_data_had_re_allocate<-catch_size_data_had_re_allocate %>% 
        dplyr::mutate(keep_new=dplyr::case_when(rel_new==0~1, TRUE~ 0)) %>% 
        dplyr::select(-keep, -release, -fishid2, -uniform) %>% 
        dplyr::rename(keep=keep_new, release=rel_new)
      
      sum(catch_size_data_had$release)
      sum(catch_size_data_had$keep)
      
      catch_size_data_had<-rbind.fill(catch_size_data_had_re_allocate,catch_size_data_had_re_allocate_base )
      
      sum(catch_size_data_had$release)
      sum(catch_size_data_had$keep)
      
      rm(catch_size_data_had_re_allocate, catch_size_data_had_re_allocate_base)
      n_sub_had_kept<-0
    }
  }
  
  
  
  #length data
  catch_size_data_had <- as.data.table(catch_size_data_had)
  new_size_data <- catch_size_data_had[, .(
    keep = sum(keep),
    release = sum(release)
  ), by = .(period2, catch_draw, tripid, fitted_length)]
  
  keep_size_data <- new_size_data %>%
    dplyr::select(-release) %>%
    tidyr::pivot_wider(names_from = fitted_length, #_length,
                       names_glue = "keep_had_{fitted_length}",
                       names_sort = TRUE,
                       values_from = keep,
                       values_fill = 0)
  
  release_size_data <- new_size_data %>%
    dplyr::select(-keep) %>%
    tidyr::pivot_wider(names_from = fitted_length, #_length,
                       names_glue = "release_had_{fitted_length}",
                       names_sort = TRUE,
                       values_from = release,
                       values_fill = 0)
  
  keep_release_hadd <- keep_size_data %>%
    dplyr::left_join(release_size_data, by = c("period2",  "tripid", "catch_draw"))
  
  
  #trip data
  trip_data_hadd <- catch_size_data_had %>%
    dplyr::group_by(period2, catch_draw, tripid) %>% 
    dplyr::summarize(tot_keep_hadd_new = sum(keep),
                     tot_rel_hadd_new = sum(release), 
                     .groups = "drop") %>%
    dplyr::ungroup()
  
  
  had_zero_catch<-had_zero_catch %>%
    dplyr::select(tripid, catch_draw, period2) %>%
    dplyr::mutate(tot_keep_hadd_new=0,
                  tot_rel_hadd_new=0)
  
  trip_data_hadd <- dplyr::bind_rows(trip_data_hadd, had_zero_catch) %>%
    dplyr::mutate_if(is.numeric, tidyr::replace_na, replace = 0) %>%
    dplyr::select(c("period2", "catch_draw","tripid",
                    "tot_keep_hadd_new","tot_rel_hadd_new"))
  
  
  trip_data_hadd<- trip_data_hadd %>% dplyr::mutate(domain2 = paste0(period2, "_", catch_draw, "_", tripid)) %>% 
    dplyr::select(-period2, -catch_draw, -tripid)
  trip_data_hadd<-data.table::as.data.table(trip_data_hadd)
  data.table::setkey(trip_data_hadd, "domain2")
  
  # merge the hadd trip data with the rest of the trip data
  #trip_data <-  merge(trip_data,trip_data_bsb,by=c("period2", "catch_draw", "tripid", "state", "mode", "month" ))
  trip_data<-trip_data[trip_data_hadd, on = "domain2"]
  
}

#If there is catch of only cod
if (had_catch_check==0 & cod_catch_check!=0){
  trip_data_hadd<-cod_had_catch_data  %>% 
    dplyr::mutate(domain2 = paste0(period2, "_", catch_draw, "_", tripid)) %>% 
    dplyr::select(-mode, -period2, -catch_draw, -tripid) %>% 
    as.data.table()
  
  data.table::setkey(trip_data_hadd, "domain2")
  
  trip_data_hadd$tot_keep_hadd_new<-0
  trip_data_hadd$tot_rel_hadd_new<-0
  
  trip_data<-trip_data[trip_data_hadd, on = "domain2"]
  
  
}



##Utility parameters Table 9 from Carr-Harris and Steinback */

period_vec1 <- param_draws %>%
  dplyr::mutate(beta_sqrt_cod_keep = rnorm(nrow(param_draws), mean =0.957, sd = 1.092),
                beta_sqrt_cod_release = rnorm(nrow(param_draws), mean = 0.168 , sd = 0.409),
                beta_sqrt_hadd_keep = rnorm(nrow(param_draws), mean = 0.703, sd = 1.014 ),
                beta_sqrt_hadd_release = rnorm(nrow(param_draws), mean = 0.083 , sd = 0 ),
                #beta_sqrt_cod_hadd_keep = rnorm(nrow(param_draws), mean =-0.314  , sd = 0.778 ),
                beta_cost = rnorm(nrow(param_draws), mean =-0.015 , sd =0 ),
                beta_opt_out = rnorm(nrow(param_draws), mean =-2.427 , sd = 3.155 ),
                beta_opt_out_age = rnorm(nrow(param_draws), mean =0.037 , sd = 0 ),
                beta_opt_out_likely = rnorm(nrow(param_draws), mean =-1.453 , sd = 0 ),
                beta_opt_out_prefer = rnorm(nrow(param_draws), mean =-0.901 , sd = 0 ))%>%
  dplyr::group_by(period2) %>% dplyr::mutate(tripid = dplyr::row_number(period2))


trip_data<- trip_data %>% as.data.frame() %>% 
  dplyr::left_join(period_vec1, by = c("period2","tripid")) %>% 
  dplyr::arrange(period2, tripid, catch_draw) %>% 
  cbind(trip_costs) %>% 
  cbind(age) %>% 
  cbind(angler_dems)

rm(trip_costs, age, angler_dems)

# Costs_new_state data sets will retain raw trip outcomes from the baseline scenario.
# We will merge these data to the prediction year outcomes to calculate changes in CS.
costs_new_all <- trip_data %>%
  dplyr::select(c(tripid, cost, catch_draw, tot_keep_cod_new, tot_rel_cod_new,
                  age, fish_pref_more, likely_to_fish, beta_opt_out_age,  beta_opt_out_likely,  beta_opt_out_prefer,
                  tot_keep_hadd_new,tot_rel_hadd_new,
                  beta_cost, beta_opt_out, beta_sqrt_hadd_keep,
                  beta_sqrt_hadd_release, #beta_sqrt_cod_hadd_keep,
                  beta_sqrt_cod_keep, beta_sqrt_cod_release, period2)) %>%
  dplyr::rename(tot_keep_cod_base = tot_keep_cod_new,
                tot_rel_cod_base = tot_rel_cod_new,
                tot_keep_had_base = tot_keep_hadd_new,
                tot_rel_had_base = tot_rel_hadd_new) %>%
  dplyr::mutate(n_cal_draw = k,
                mode = select_mode,
                open = select_season)


season1<-unique(costs_new_all$open)
mode1<-unique(costs_new_all$mode)
draw1<-unique(costs_new_all$n_cal_draw)

write_feather(costs_new_all, file.path(iterative_input_data_cd, paste0("costs_", mode1,"_", season1, "_", draw1, ".feather")))



#  utility (prediction year)
trip_data <-trip_data %>%
  dplyr::mutate(
    vA = beta_sqrt_cod_keep*sqrt(tot_keep_cod_new) +
      beta_sqrt_cod_release*sqrt(tot_rel_cod_new) +
      beta_sqrt_hadd_keep*sqrt(tot_keep_hadd_new) +
      beta_sqrt_hadd_release*sqrt(tot_rel_hadd_new) +
      beta_cost*cost)

trip_data <- trip_data %>%
  dplyr::mutate(period = as.numeric(as.factor(period2)))

period_names<-subset(trip_data, select=c("period", "period2"))
period_names <- period_names[!duplicated(period_names), ]


mean_trip_data <- trip_data %>% data.table::data.table() %>% 
  .[, group_index := .GRP, by = .(period2, catch_draw, tripid)]

# Now expand the data to create two alternatives, representing the alternatives available in choice survey
mean_trip_data <- mean_trip_data %>%
  dplyr::mutate(n_alt = rep(2,nrow(.))) %>%
  tidyr::uncount(n_alt) %>%
  dplyr::mutate(alt = rep(1:2,nrow(.)/2),
                opt_out = ifelse(alt == 2, 1, 0))

#Calculate the expected utility of alts 2 parameters of the utility function,
setDT(mean_trip_data)

# Filter only alt == 2 once, and calculate vA 
mean_trip_data[alt == 2, "vA" := .(
  beta_opt_out * opt_out +
    beta_opt_out_age * (age * opt_out) +
    beta_opt_out_likely * (likely_to_fish * opt_out) +
    beta_opt_out_prefer * (fish_pref_more * opt_out)
)]

# Pre-compute exponential terms
mean_trip_data[, `:=`(exp_vA = exp(vA))]

# Group by group_index and calculate probabilities and log-sums
mean_trip_data[, `:=`(
  probA = exp_vA / sum(exp_vA)
), by = group_index]



mean_trip_data<- subset(mean_trip_data, alt==1) %>% 
  dplyr::select(-domain2, -group_index) %>% 
  dplyr::mutate(tot_cat_cod_new=tot_keep_cod_new+tot_rel_cod_new, 
                tot_cat_hadd_new=tot_keep_hadd_new+tot_rel_hadd_new)


# Get rid of things we don't need.
mean_trip_data <- subset(mean_trip_data, alt==1,select=-c(alt, beta_cost,beta_opt_out, beta_opt_out_age, 
                                                          beta_opt_out_likely, beta_opt_out_prefer, #beta_sqrt_cod_hadd_keep, 
                                                          beta_sqrt_cod_keep, beta_sqrt_cod_release, beta_sqrt_hadd_keep, 
                                                          beta_sqrt_hadd_release, likely_to_fish, fish_pref_more, open, period, 
                                                          opt_out, vA, exp_vA, cost, age))

# Multiply the trip probability by each of the catch variables (not the variables below) to get probability-weighted catch
list_names <- colnames(mean_trip_data)[colnames(mean_trip_data) !="tripid" 
                                       & colnames(mean_trip_data) !="period2" 
                                       & colnames(mean_trip_data) !="probA" 
                                       & colnames(mean_trip_data) !="catch_draw"]


mean_trip_data <- mean_trip_data %>%
  data.table::as.data.table() %>%
  .[,as.vector(list_names) := lapply(.SD, function(x) x * probA), .SDcols = list_names] %>%
  .[]



mean_trip_data_prob_catch_draw<-mean_trip_data %>% 
  dplyr::select("period2","tripid", "catch_draw", "probA")


#Take the average outcomes across catch draws
all_vars<-c()
all_vars <- names(mean_trip_data)[!names(mean_trip_data) %in% c("period2","tripid")]

mean_trip_data<-mean_trip_data  %>% data.table::as.data.table() %>%
  .[,lapply(.SD, mean), by = c("period2","tripid"), .SDcols = all_vars]


mean_trip_data <- mean_trip_data %>%
  dplyr::mutate(n_choice_occasions = rep(1,nrow(.))) %>%
  dplyr::left_join(period_names, by = c("period2"))


#source(compute calibration weights)

#Now multiply the trip outcomes (catch, trip probabilities) for each choice occasion in
#mean_trip_pool by the expansion factor (expand), so that  each choice occasion represents a certain number of choice occasions
#calibration_data <- calibration_data  %>%   rename(period2 = period)

sims <- directed_trips_p %>%
  dplyr::select(c(dtrip, period2)) 

mean_trip_data<-mean_trip_data %>%
  dplyr::select(-period)

mean_trip_data <- mean_trip_data %>%
  dplyr::left_join(sims, by="period2")

mean_probs<-mean_trip_data  %>% 
  dplyr::select(period2, probA) %>% 
  dplyr::rename(mean_prob=probA) %>% 
  data.table::as.data.table() %>%
  .[,lapply(.SD, mean), by = c("period2"), .SDcols = "mean_prob"]

mean_trip_data <- mean_trip_data %>%
  dplyr::left_join(mean_probs, by="period2")



mean_trip_data <- mean_trip_data %>%
  dplyr::mutate(sims=dtrip/mean_prob,
                expand=sims/n_drawz) %>% 
  dplyr::rename(tot_keep_cod_model=tot_keep_cod_new, 
                tot_keep_hadd_model=tot_keep_hadd_new, 
                tot_rel_cod_model=tot_rel_cod_new, 
                tot_rel_hadd_model=tot_rel_hadd_new, 
                tot_cat_hadd_model=tot_cat_hadd_new, 
                tot_cat_cod_model=tot_cat_cod_new)

mean_trip_data0<-  mean_trip_data %>% 
  dplyr::select(period2, expand)

list_names = c("tot_keep_cod_model","tot_keep_hadd_model",
               "tot_rel_cod_model","tot_rel_hadd_model",
               "tot_cat_hadd_model","tot_cat_cod_model",
               "probA", "n_choice_occasions")


mean_trip_data <- mean_trip_data %>%
  data.table::as.data.table() %>%
  .[,as.vector(list_names) := lapply(.SD, function(x) x * expand), .SDcols = list_names] %>%
  .[]

aggregate_trip_data <- mean_trip_data %>%
  data.table::as.data.table() %>%
  .[,lapply(.SD, sum), by =c("period2"), .SDcols = list_names]

names(aggregate_trip_data)[names(aggregate_trip_data) == "probA"] = "estimated_trips"

pds_new<-aggregate_trip_data %>%
  dplyr::mutate(draw = k,
                mode = select_mode,
                open = select_season)

season1<-unique(pds_new$open)
mode1<-unique(pds_new$mode)
draw1<-unique(pds_new$draw)

write_feather(pds_new, file.path(iterative_input_data_cd, paste0("pds_new_", mode1,"_", season1, "_", draw1, ".feather")))



aggregate_trip_data2=pds_new %>% 
  dplyr::group_by(draw, mode, open) %>% 
  dplyr::summarize(tot_keep_cod_model=sum(tot_keep_cod_model),
                   tot_keep_hadd_model=sum(tot_keep_hadd_model), 
                   tot_rel_cod_model=sum(tot_rel_cod_model), 
                   tot_rel_hadd_model=sum(tot_rel_hadd_model), 
                   tot_cat_hadd_model=sum(tot_cat_hadd_model), 
                   tot_cat_cod_model=sum(tot_cat_cod_model), 
                   estimated_trips=sum(estimated_trips), .groups='drop') %>% 
  dplyr::mutate(mrip_index=i)

comparison<-aggregate_trip_data2 %>% 
  dplyr::left_join(MRIP_stats, by=c("mode", "open", "draw", "mrip_index"))


comparison<-comparison %>% 
  dplyr::mutate(diff_cod_harv=tot_keep_cod_model-tot_cod_keep_mrip, 
                diff_hadd_harv=tot_keep_hadd_model-tot_hadd_keep_mrip, 
                perc_diff_cod_harv = ((tot_keep_cod_model-tot_cod_keep_mrip)/tot_cod_keep_mrip)*100, 
                perc_diff_hadd_harv = ((tot_keep_hadd_model-tot_hadd_keep_mrip)/tot_hadd_keep_mrip)*100, 
                abs_perc_diff_cod_harv = abs(perc_diff_cod_harv), 
                abs_perc_diff_hadd_harv = abs(perc_diff_hadd_harv)) %>% 
  dplyr::mutate(cod_achieved = ifelse(abs(diff_cod_harv)<500 | abs_perc_diff_cod_harv<5, 1, 0), 
                hadd_achieved = ifelse(abs(diff_hadd_harv)<500 | abs_perc_diff_hadd_harv<5, 1, 0)) %>% 
  cbind(h_star_cod_keep_to_release_variable, h_star_hadd_keep_to_release_variable, h_star_cod_release_to_keep_variable, h_star_hadd_release_to_keep_variable, 
        p_cod_rl_2_kp, p_cod_kp_2_rl, p_hadd_rl_2_kp, p_hadd_kp_2_rl, n_sub_had_kept, n_sub_cod_kept, n_legal_hadd_rel, n_legal_cod_rel)

comparison2<-comparison %>% 
  dplyr::select(- p_cod_rl_2_kp, -p_cod_kp_2_rl, -p_hadd_rl_2_kp, -p_hadd_kp_2_rl)


season1<-unique(comparison2$open)
mode1<-unique(comparison2$mode)
draw1<-unique(comparison2$draw)

write_feather(comparison2, file.path(iterative_input_data_cd, paste0("comparison_", mode1,"_", season1, "_", draw1, ".feather")))



rm(catch_size_data, catch_size_data_had, cod_catch_data, cod_had_catch_data, costs_new_all, had_catch_data, 
   keep_size_data, new_size_data, param_draws, release_size_data, 
   trip_data, trip_data_hadd)




