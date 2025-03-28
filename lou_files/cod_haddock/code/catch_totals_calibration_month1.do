



* This file creates:
	*1) total harvest and discards for each species for January-June and July-December to align with the 
		 *length-weight equations that vary by season (for haddock)
	*2) total harvest and discards for each species for the entire year
	
	
cd $input_data_cd

clear
mata: mata clear

tempfile tl1 cl1
dsconcat $triplist

sort year strat_id psu_id id_code
*replace id_code=ID_CODE if id_code=="" & ID_CODE!=""
drop if strmatch(id_code, "*xx*")==1
drop if strat_id==""
duplicates drop 
save `tl1'
clear

dsconcat $catchlist
sort year strat_id psu_id id_code
replace common=subinstr(lower(common)," ","",.)
save `cl1'

use `tl1'
merge 1:m year strat_id psu_id id_code using `cl1', keep(1 3) nogenerate

 /* THIS IS THE END OF THE DATA MERGING CODE */
*replace mode_fx=MODE_FX if mode_fx=="" & MODE_FX!=""
*replace area_x=AREA_X if area_x=="" & AREA_X!=""



 /* ensure only relevant states */
keep if inlist(st,23, 33, 25)


/*This is the "full" mrip data */
tempfile tc1
save `tc1'
 
keep if $calibration_year

gen st2 = string(st,"%02.0f")

gen state="MA" if st==25
replace state="MD" if st==24
replace state="RI" if st==44
replace state="CT" if st==9
replace state="NY" if st==36
replace state="NJ" if st==34
replace state="DE" if st==10
replace state="VA" if st==51
replace state="NC" if st==37
replace state="ME" if st==23
replace state="NH" if st==33


gen mode1="sh" if inlist(mode_fx, "1", "2", "3")
replace mode1="pr" if inlist(mode_fx, "7")
replace mode1="fh" if inlist(mode_fx, "4", "5")

*classify trips that I care about into the things I care about (caught or targeted sf/bsb) and things I don't care about "ZZ" 
replace prim1_common=subinstr(lower(prim1_common)," ","",.)
replace prim2_common=subinstr(lower(prim1_common)," ","",.)

/* we need to retain 1 observation for each strat_id, psu_id, and id_code.  */
/* A.  Trip (Targeted or Caught) (Cod or Haddock) then it should be marked in the domain "_ATLCO"
   B.  Trip did not (Target or Caught) (Cod or Haddock) then it is marked in the the domain "ZZZZZ"
*/

gen common_dom="ZZ"
replace common_dom="ATLCO" if inlist(common, "atlanticcod") 
replace common_dom="ATLCO" if inlist(common, "haddock") 

replace common_dom="ATLCO"  if inlist(prim1_common, "atlanticcod") 
replace common_dom="ATLCO"  if inlist(prim1_common, "haddock") 
*OLD MRIP site allocations
/*
*classify into GOM or GBS
rename intsite SITE_ID
merge m:1 SITE_ID using "$input_data_cd/ma site allocation.dta",  keep(1 3)
rename  SITE_ID intsite
rename  STOCK_REGION_CALC stock_region_calc
replace stock_region_calc="NORTH" if intsite==4434

drop _merge

gen str3 area_s="AAA"

replace area_s="GOM" if st2=="23" | st2=="33"
replace area_s="GOM" if st2=="25" & strmatch(stock_region_calc,"NORTH")
replace area_s="GBS" if st2=="25" & strmatch(stock_region_calc,"SOUTH")
*/

*NEW MRIP site allocations
preserve 
import excel using "$input_data_cd/ma_site_list_updated_SS.xlsx", clear first
keep SITE_EXTERNAL_ID NMFS_STAT_AREA
renvarlab, lower
rename site_external_id intsite
tempfile mrip_sites
save `mrip_sites', replace 
restore

merge m:1 intsite using `mrip_sites',  keep(1 3)

/*classify into GOM or GBS */
gen str3 area_s="AAA"

replace area_s="GOM" if st2=="23" | st2=="33"
replace area_s="GOM" if st2=="25" & inlist(nmfs_stat_area,511, 512, 513,  514)
replace area_s="GBS" if st2=="25" & inlist(nmfs_stat_area,521, 526, 537,  538)
replace area_s="GOM" if st2=="25" & intsite==224


tostring wave, gen(wv2)
tostring year, gen(yr2)

destring month, gen(month1)
gen day=substr(id_code, 12, 2)
destring day, gen(day1)
gen date=mdy( month1, day1, year)
format date %td


*gen season="op" if ((date>=$cod_start_date1 & date<=$cod_end_date1 ) | (date>=$cod_start_date2 & date<=$cod_end_date2 )) 
*replace season="cl" if season==""


gen season="JanJun" if inlist(month1, 1, 2, 3, 4, 5, 6)
replace season="JulDec" if inlist(month1, 7, 8, 9, 10, 11, 12)


gen my_dom_id_string=common_dom+"_"+season+"_"+area_s
replace my_dom_id_string=subinstr(ltrim(rtrim(my_dom_id_string))," ","",.)
encode my_dom_id_string, gen(my_dom_id)

*gen my_dom_id_string=area_s+"_"+mode1+"_"+common_dom+"_"+season

gen cod_tot_cat=tot_cat if common=="atlanticcod"
egen sum_cod_tot_cat=sum(cod_tot_cat), by(strat_id psu_id id_code)

gen cod_harvest=landing if common=="atlanticcod"
egen sum_cod_harvest=sum(cod_harvest), by(strat_id psu_id id_code)
 
gen cod_releases=release if common=="atlanticcod"
egen sum_cod_releases=sum(cod_releases), by(strat_id psu_id id_code)
 
gen hadd_tot_cat=tot_cat if common=="haddock"
egen sum_hadd_tot_cat=sum(hadd_tot_cat), by(strat_id psu_id id_code)

gen hadd_harvest=landing if common=="haddock"
egen sum_hadd_harvest=sum(hadd_harvest), by(strat_id psu_id id_code)

gen hadd_releases=release if common=="haddock"
egen sum_hadd_releases=sum(hadd_releases), by(strat_id psu_id id_code)

drop cod_tot_cat cod_harvest cod_releases hadd_tot_cat hadd_harvest hadd_releases 
rename sum_cod_tot_cat cod_catch
rename sum_cod_harvest cod_keep
rename sum_cod_releases cod_rel
rename sum_hadd_tot_cat hadd_catch
rename sum_hadd_harvest hadd_keep
rename sum_hadd_releases hadd_rel


**Round these estimates to align with catch-per-trip computations
local vars cod_catch cod_keep cod_rel hadd_catch hadd_keep hadd_rel
foreach v of local vars{
	replace `v'=round(`v')
	
}

/* Set a variable "no_dup"=0 if the record is "$my_common" catch and no_dup=1 otherwise.*/
  
gen no_dup=0
replace no_dup=1 if  strmatch(common, "atlanticcod")==0
replace no_dup=1 if strmatch(common, "haddock")==0

/*
We sort on year, strat_id, psu_id, id_code, "no_dup", and "my_dom_id_string". For records with duplicate year, strat_id, psu_id, and id_codes, the first entry will be "my_common catch" if it exists.  These will all be have sp_dom "ATLCO."  If there is no my_common catch, but the  trip targeted (cod or haddock) or caught cod, the secondary sorting on "my_dom_id_string" ensures the trip is properly classified.

After sorting, we generate a count variable (count_obs1 from 1....n) and we keep only the "first" observations within each "year, strat_id, psu_id, and id_codes" group.
*/

bysort year strat_id psu_id id_code (my_dom_id_string no_dup): gen count_obs1=_n

keep if count_obs1==1 // This keeps only one record for trips with catch of multiple species. We have already computed catch of the species of interest above and saved these in a trip-row
order strat_id psu_id id_code no_dup my_dom_id_string count_obs1 common
keep if common_dom=="ATLCO"
keep if area_s=="GOM"

*replace my_dom_id_string=mode1+"_"+season


encode strat_id, gen(strat_id2)
encode psu_id, gen(psu_id2)

*replace wp_int=round(wp_int)
svyset psu_id2 [pweight= wp_int], strata(strat_id2) singleunit(certainty)

*encode my_dom_id_string, gen(my_dom_id)

*svy: total hadd_catch, over(my_dom_id2)

preserve
keep my_dom_id my_dom_id_string
duplicates drop 
tostring my_dom_id, gen(my_dom_id2)
keep my_dom_id2 my_dom_id_string
tempfile domains
save `domains', replace 
restore

tempfile base
save `base', replace

global catchez

local vars cod_catch cod_keep cod_rel hadd_catch hadd_keep hadd_rel
foreach v of local vars{
u `base', clear 
svy: total `v' , over(my_dom_id)
xsvmat, from(r(table)') rownames(rname) names(col) norestor

split rname, parse("@")
drop rname1
split rname2, parse(.)
drop rname2 rname22
rename rname21 my_dom_id2
merge 1:1 my_dom_id2 using `domains'
drop rname my_dom_id2 _merge 
order my_dom_id_string

*rename b `v'
gen var="`v'"
*rename rname my_dom_id_string

keep my_dom_id_string var b se ll ul

tempfile catchez`v'
save `catchez`v'', replace
global catchez "$catchez "`catchez`v''" " 

}

dsconcat $catchez

split my_dom, parse(_)
rename my_dom_id_string2 season

keep   season var b ll ul 

reshape wide b ll ul, i( season) j(var) string
renvarlab b*, predrop(1)
ds   season, not
renvarlab `r(varlist)', postfix(_mrip)
sort season  

ds   season, not
mvencode `r(varlist)', mv(0) over
sort  season 

export delimited using "$input_data_cd\MRIP_catch_totals_month_calibration.csv", replace 




***Now compute catch totals for the full season 

cd $input_data_cd

clear
mata: mata clear

tempfile tl1 cl1
dsconcat $triplist

sort year strat_id psu_id id_code
*replace id_code=ID_CODE if id_code=="" & ID_CODE!=""
drop if strmatch(id_code, "*xx*")==1
drop if strat_id==""
duplicates drop 
save `tl1'
clear

dsconcat $catchlist
sort year strat_id psu_id id_code
replace common=subinstr(lower(common)," ","",.)
save `cl1'

use `tl1'
merge 1:m year strat_id psu_id id_code using `cl1', keep(1 3) nogenerate

 /* THIS IS THE END OF THE DATA MERGING CODE */
*replace mode_fx=MODE_FX if mode_fx=="" & MODE_FX!=""
*replace area_x=AREA_X if area_x=="" & AREA_X!=""



 /* ensure only relevant states */
keep if inlist(st,23, 33, 25)


/*This is the "full" mrip data */
tempfile tc1
save `tc1'
 
keep if $calibration_year

gen st2 = string(st,"%02.0f")

gen state="MA" if st==25
replace state="MD" if st==24
replace state="RI" if st==44
replace state="CT" if st==9
replace state="NY" if st==36
replace state="NJ" if st==34
replace state="DE" if st==10
replace state="VA" if st==51
replace state="NC" if st==37
replace state="ME" if st==23
replace state="NH" if st==33


gen mode1="sh" if inlist(mode_fx, "1", "2", "3")
replace mode1="pr" if inlist(mode_fx, "7")
replace mode1="fh" if inlist(mode_fx, "4", "5")

*classify trips that I care about into the things I care about (caught or targeted sf/bsb) and things I don't care about "ZZ" 
replace prim1_common=subinstr(lower(prim1_common)," ","",.)
replace prim2_common=subinstr(lower(prim1_common)," ","",.)

/* we need to retain 1 observation for each strat_id, psu_id, and id_code.  */
/* A.  Trip (Targeted or Caught) (Cod or Haddock) then it should be marked in the domain "_ATLCO"
   B.  Trip did not (Target or Caught) (Cod or Haddock) then it is marked in the the domain "ZZZZZ"
*/

gen common_dom="ZZ"
replace common_dom="ATLCO" if inlist(common, "atlanticcod") 
replace common_dom="ATLCO" if inlist(common, "haddock") 

replace common_dom="ATLCO"  if inlist(prim1_common, "atlanticcod") 
replace common_dom="ATLCO"  if inlist(prim1_common, "haddock") 


*OLD MRIP site allocations
/*
*classify into GOM or GBS
rename intsite SITE_ID
merge m:1 SITE_ID using "$input_data_cd/ma site allocation.dta",  keep(1 3)
rename  SITE_ID intsite
rename  STOCK_REGION_CALC stock_region_calc
replace stock_region_calc="NORTH" if intsite==4434

drop _merge

gen str3 area_s="AAA"

replace area_s="GOM" if st2=="23" | st2=="33"
replace area_s="GOM" if st2=="25" & strmatch(stock_region_calc,"NORTH")
replace area_s="GBS" if st2=="25" & strmatch(stock_region_calc,"SOUTH")
*/

*NEW MRIP site allocations
preserve 
import excel using "$input_data_cd/ma_site_list_updated_SS.xlsx", clear first
keep SITE_EXTERNAL_ID NMFS_STAT_AREA
renvarlab, lower
rename site_external_id intsite
tempfile mrip_sites
save `mrip_sites', replace 
restore

merge m:1 intsite using `mrip_sites',  keep(1 3)

/*classify into GOM or GBS */
gen str3 area_s="AAA"

replace area_s="GOM" if st2=="23" | st2=="33"
replace area_s="GOM" if st2=="25" & inlist(nmfs_stat_area,511, 512, 513,  514)
replace area_s="GBS" if st2=="25" & inlist(nmfs_stat_area,521, 526, 537,  538)
replace area_s="GOM" if st2=="25" & intsite==224


tostring wave, gen(wv2)
tostring year, gen(yr2)

destring month, gen(month1)
gen day=substr(id_code, 12, 2)
destring day, gen(day1)
gen date=mdy( month1, day1, year)
format date %td


*gen season="op" if ((date>=$cod_start_date1 & date<=$cod_end_date1 ) | (date>=$cod_start_date2 & date<=$cod_end_date2 )) 
*replace season="cl" if season==""


gen season="JanJun" if inlist(month1, 1, 2, 3, 4, 5, 6)
replace season="JulDec" if inlist(month1, 7, 8, 9, 10, 11, 12)


gen my_dom_id_string=common_dom+"_"+area_s
replace my_dom_id_string=subinstr(ltrim(rtrim(my_dom_id_string))," ","",.)
encode my_dom_id_string, gen(my_dom_id)

*gen my_dom_id_string=area_s+"_"+mode1+"_"+common_dom+"_"+season

gen cod_tot_cat=tot_cat if common=="atlanticcod"
egen sum_cod_tot_cat=sum(cod_tot_cat), by(strat_id psu_id id_code)

gen cod_harvest=landing if common=="atlanticcod"
egen sum_cod_harvest=sum(cod_harvest), by(strat_id psu_id id_code)
 
gen cod_releases=release if common=="atlanticcod"
egen sum_cod_releases=sum(cod_releases), by(strat_id psu_id id_code)
 
gen hadd_tot_cat=tot_cat if common=="haddock"
egen sum_hadd_tot_cat=sum(hadd_tot_cat), by(strat_id psu_id id_code)

gen hadd_harvest=landing if common=="haddock"
egen sum_hadd_harvest=sum(hadd_harvest), by(strat_id psu_id id_code)

gen hadd_releases=release if common=="haddock"
egen sum_hadd_releases=sum(hadd_releases), by(strat_id psu_id id_code)

drop cod_tot_cat cod_harvest cod_releases hadd_tot_cat hadd_harvest hadd_releases 
rename sum_cod_tot_cat cod_catch
rename sum_cod_harvest cod_keep
rename sum_cod_releases cod_rel
rename sum_hadd_tot_cat hadd_catch
rename sum_hadd_harvest hadd_keep
rename sum_hadd_releases hadd_rel


**Round these estimates to align with catch-per-trip computations
local vars cod_catch cod_keep cod_rel hadd_catch hadd_keep hadd_rel
foreach v of local vars{
	replace `v'=round(`v')
	
}

/* Set a variable "no_dup"=0 if the record is "$my_common" catch and no_dup=1 otherwise.*/
  
gen no_dup=0
replace no_dup=1 if  strmatch(common, "atlanticcod")==0
replace no_dup=1 if strmatch(common, "haddock")==0

/*
We sort on year, strat_id, psu_id, id_code, "no_dup", and "my_dom_id_string". For records with duplicate year, strat_id, psu_id, and id_codes, the first entry will be "my_common catch" if it exists.  These will all be have sp_dom "ATLCO."  If there is no my_common catch, but the  trip targeted (cod or haddock) or caught cod, the secondary sorting on "my_dom_id_string" ensures the trip is properly classified.

After sorting, we generate a count variable (count_obs1 from 1....n) and we keep only the "first" observations within each "year, strat_id, psu_id, and id_codes" group.
*/

bysort year strat_id psu_id id_code (my_dom_id_string no_dup): gen count_obs1=_n

keep if count_obs1==1 // This keeps only one record for trips with catch of multiple species. We have already computed catch of the species of interest above and saved these in a trip-row
order strat_id psu_id id_code no_dup my_dom_id_string count_obs1 common
keep if common_dom=="ATLCO"
keep if area_s=="GOM"

*replace my_dom_id_string=mode1+"_"+season


encode strat_id, gen(strat_id2)
encode psu_id, gen(psu_id2)

*replace wp_int=round(wp_int)
svyset psu_id2 [pweight= wp_int], strata(strat_id2) singleunit(certainty)

*encode my_dom_id_string, gen(my_dom_id)

*svy: total hadd_catch, over(my_dom_id2)

preserve
keep my_dom_id my_dom_id_string
duplicates drop 
tostring my_dom_id, gen(my_dom_id2)
keep my_dom_id2 my_dom_id_string
tempfile domains
save `domains', replace 
restore

tempfile base
save `base', replace

global catchez

local vars cod_catch cod_keep cod_rel hadd_catch hadd_keep hadd_rel
foreach v of local vars{
u `base', clear 
svy: total `v' , over(my_dom_id)
xsvmat, from(r(table)') rownames(rname) names(col) norestor

split rname, parse("@")
drop rname1
split rname2, parse(.)
drop rname2 rname22
rename rname21 my_dom_id2
merge 1:1 my_dom_id2 using `domains'
drop rname my_dom_id2 _merge 
order my_dom_id_string

*rename b `v'
gen var="`v'"
*rename rname my_dom_id_string

keep my_dom_id_string var b se ll ul

tempfile catchez`v'
save `catchez`v'', replace
global catchez "$catchez "`catchez`v''" " 

}

dsconcat $catchez

split my_dom, parse(_)

keep    var b ll ul 
gen tab=1
reshape wide b ll ul, i( tab ) j(var) string
renvarlab b*, predrop(1)
ds   tab, not
renvarlab `r(varlist)', postfix(_mrip)

ds   tab, not
mvencode `r(varlist)', mv(0) over

export delimited using "$input_data_cd\MRIP_catch_totals_annual_calibration.csv", replace 


