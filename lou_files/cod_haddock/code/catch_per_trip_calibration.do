


/*This code uses the MRIP data to 
	1) estimate harvest, discards, and catch frequencies (i.e., # of trips that harvested/discarded/caught X fish) and their standard error at the month and mode (pr/fh) level using the most recent full year of data
	****Note that we compute catch-per-trip distributions based on harvest- and discard-per-trip distribrutions because we calibrate the model to total harvest and we need,  
	 for each draw of MRIP data, a draw of total harvest that is reflective of the random draw from the directed trips and harvest-per-trip distribution.Essesntially, to compute 
	 catch-per-trip, I take the sum of a random draw of discard frequencies and harvest frequencies. That way I also retain harvest-per-trip distributions, which I can multiply 
	 by the total number of trips drawn from the directed trip distributions to arrive at total simulated harvest. I also assess whether my simulated total harvest/discards/catch estimates
	 are similar to the MRIP point esimates in catch_totals_compare_model2mrip_open_seasons.
	 random draw of discar
	2) use those estimates to create 150 random draws of harvest, discards, and catch frequencies for each stratum
	2b) correct for the fact that a draw of number of trips cannot be <0 
	3) combine these data with the angler characterstics data
	4) create 150 draws of catch-per-trip and angler characteristics. 
*/
		


cd $input_data_cd

clear
mata: mata clear

tempfile tl1 cl1
dsconcat $triplist

sort year strat_id psu_id id_code
drop if strmatch(id_code, "*xx*")==1
duplicates drop 
save `tl1'
clear

dsconcat $catchlist
sort year strat_id psu_id id_code
replace common=subinstr(lower(common)," ","",.)
save `cl1'

replace var_id=strat_id if strmatch(var_id,"")

use `tl1'
merge 1:m year strat_id psu_id id_code using `cl1', keep(1 3) nogenerate /*Keep all trips including catch==0*/
replace var_id=strat_id if strmatch(var_id,"")

 /* THIS IS THE END OF THE DATA MERGING CODE */

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


*Old stock delineations for GoM cod/haddock are NFMS stat areas 514, 513, 512, 511
*New stock delineations for GoM cod are NFMS stat areas now include 521, 526, 541
*New stock delineations for GoM haddock are the same as the old

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
replace area_s="GBS" if st2=="25" & inlist(nmfs_stat_area, 521, 526, 537,  538)
replace area_s="GOM" if st2=="25" & intsite==224

tostring wave, gen(wv2)
tostring year, gen(yr2)
gen my_dom_id_string=area_s+"_"+month+"_"+mode1+"_"+common_dom

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


/* Set a variable "no_dup"=0 if the record is "$my_common" catch and no_dup=1 otherwise.*/
  
gen no_dup=0
replace no_dup=1 if  strmatch(common, "atlanticcod")==0
replace no_dup=1 if strmatch(common, "haddock")==0

/*
We sort on year, strat_id, psu_id, id_code, "no_dup", and "my_dom_id_string". For records with duplicate year, strat_id, psu_id, and id_codes, the first entry will be "my_common catch" if it exists.  These will all be have sp_dom "ATLCO."  If there is no my_common catch, but the trip targeted (cod or haddock) or caught cod, the secondary sorting on "my_dom_id_string" ensures the trip is properly classified.

After sorting, we generate a count variable (count_obs1 from 1....n) and we keep only the "first" observations within each "year, strat_id, psu_id, and id_codes" group.
*/

bysort year strat_id psu_id id_code (my_dom_id_string no_dup): gen count_obs1=_n

keep if count_obs1==1 // This keeps only one record for trips with catch of multiple species. We have already computed catch of the species of interest above and saved these in a trip-row

order strat_id psu_id id_code no_dup my_dom_id_string count_obs1 common
keep if common_dom=="ATLCO"
keep if area_s=="GOM"

replace my_dom_id_string=month+"_"+mode1+"_"+common_dom

svyset psu_id [pweight= wp_int], strata(strat_id) singleunit(certainty)

local vars cod_catch cod_keep cod_rel hadd_catch hadd_keep hadd_rel 
foreach v of local vars{
	replace `v'=round(`v')

}

tempfile new 
save `new', replace

*Loop over domains to get estimated numbers of trips that caught, harvested, and released X fish and se's
global catch 
levelsof my_dom_id_string, local(sts)
foreach s of local sts{
	
u `new', clear 

**cod catch
preserve
estpost svy: tab cod_catch my_dom_id_string if my_dom_id_string=="`s'", count ci se format(%11.3g)

mat b = e(b)'
mat se = e(se)'
mat rownames = e(Row)'

clear 
svmat rownames
svmat b
svmat se
		
drop if rownames==.
rename rownames nfish
rename b1 tot_ntrips
rename se se_ntrips
gen disp="catch"		
gen species="cod"
gen domain="`s'"
tempfile cod`s'catch
save `cod`s'catch', replace 
restore 


**hadd catch
preserve
estpost svy: tab hadd_catch my_dom_id_string if my_dom_id_string=="`s'", count ci se format(%11.3g)
mat b = e(b)'
mat se = e(se)'
mat rownames = e(Row)'

clear 
svmat rownames
svmat b
svmat se
		
drop if rownames==.
rename rownames nfish
rename b1 tot_ntrips
rename se se_ntrips
gen disp="catch"			
gen species="hadd"
gen domain="`s'"
tempfile hadd`s'catch
save `hadd`s'catch', replace 
restore 


**cod keep
preserve
estpost svy: tab cod_keep my_dom_id_string if my_dom_id_string=="`s'", count ci se format(%11.3g)

mat b = e(b)'
mat se = e(se)'
mat rownames = e(Row)'

clear 
svmat rownames
svmat b
svmat se
		
drop if rownames==.
rename rownames nfish
rename b1 tot_ntrips
rename se se_ntrips
gen disp="keep"		
gen species="cod"
gen domain="`s'"
tempfile cod`s'keep
save `cod`s'keep', replace 
restore 


**hadd keep
preserve
estpost svy: tab hadd_keep my_dom_id_string if my_dom_id_string=="`s'", count ci se format(%11.3g)
mat b = e(b)'
mat se = e(se)'
mat rownames = e(Row)'

clear 
svmat rownames
svmat b
svmat se
		
drop if rownames==.
rename rownames nfish
rename b1 tot_ntrips
rename se se_ntrips
gen disp="keep"	
gen species="hadd"
gen domain="`s'"
tempfile hadd`s'keep
save `hadd`s'keep', replace 
restore 


**cod release
preserve
estpost svy: tab cod_rel my_dom_id_string if my_dom_id_string=="`s'", count ci se format(%11.3g)

mat b = e(b)'
mat se = e(se)'
mat rownames = e(Row)'

clear 
svmat rownames
svmat b
svmat se
		
drop if rownames==.
rename rownames nfish
rename b1 tot_ntrips
rename se se_ntrips
gen disp="rel"	
gen species="cod"
gen domain="`s'"
tempfile cod`s'rel
save `cod`s'rel', replace 
restore 


**hadd release
preserve
estpost svy: tab hadd_rel my_dom_id_string if my_dom_id_string=="`s'", count ci se format(%11.3g)
mat b = e(b)'
mat se = e(se)'
mat rownames = e(Row)'

clear 
svmat rownames
svmat b
svmat se
		
drop if rownames==.
rename rownames nfish
rename b1 tot_ntrips
rename se se_ntrips
gen disp="rel"	
gen species="hadd"
gen domain="`s'"
tempfile hadd`s'rel
save `hadd`s'rel', replace 
restore 


u `cod`s'catch', clear 
append using  `hadd`s'catch'
append using  `cod`s'keep'
append using  `hadd`s'keep'
append using  `cod`s'rel'
append using  `hadd`s'rel'


tempfile catch`s'
save `catch`s'', replace
global catch "$catch "`catch`s''" " 

}	

clear
dsconcat $catch


sort domain species nfish

replace tot_n=round(tot_n)
replace se=round(se)


replace domain=domain+"_"+species+"_"+disp
drop species disp

replace se=tot if se==0

*With the point estimates and standard errors, create 150 probability distributions of harvest, relased, total catch 

tempfile new
save `new', replace 

global x

levelsof domain, local(doms)
foreach d of local doms{
	
u `new', clear 
keep if domain=="`d'"
tempfile new1
save `new1', replace 

levelsof nfish, local(levs)
foreach c of local levs{
	
u `new1', clear 

keep if nfish==`c'

su tot_ntrip
local mean=`r(mean)'

su se
local se=`r(mean)'

clear
set obs $ndraws
gen nfish=`c'

gen draw=_n

gen tot_ntrip_not_trunc=rnormal(`mean', `se')
gen tot_ntrip=max(0, tot_ntrip_not_trunc)

gen domain="`d'"
tempfile x`c'`d'
save `x`c'`d'', replace
global x "$x "`x`c'`d''" " 


}	
}
clear
dsconcat $x

egen group=group(domain nfish)

sort domain draw nfish


*The following code snippet correct for bias that occurs when drawing from uncertain MRIP estimates. 
*When an MRIP estimate is very uncertain, some draws of x from the distribution of X can result in x_i<0. 
*Because trip outcomes cannot be negative I change these values to 0. But doing so results in an upward 
*shift of the mean value across draws. To correct for this, I first sum the x_i's across draws where x_i<0. 
*Then I add some of this (negative) value to each of the other x_i's (i.e., to x_i's >0) in proportion to each 
*x_i>0's contribution to the total value of X. 

*I have tried paramaterizing non-negative distributions using the MRIP point estimate and SE, but couldn't quite figure it out. Can work on this in the future. 

gen tab=1 if tot_ntrip_not_trunc<0
egen sum_neg=sum(tot_ntrip_not_trunc) if tab==1, by(group)
sort group
egen mean_sum_neg=mean(sum_neg), by(group)

egen sum_non_neg=sum(tot_ntrip_not_trunc) if tot_ntrip_not_trunc>0 , by(group)
gen prop=tot_ntrip_not_trunc/sum_non_neg
gen adjust=prop*mean_sum_neg

gen tot_ntrip2=tot_ntrip+adjust if tot_ntrip!=0 & adjust !=.
replace tot_ntrip2=tot_ntrip if tot_ntrip2==.
replace tot_ntrip2=0 if tot_ntrip2<0
 
 *checks
 split domain, parse(_)
gen nfish0= tot_ntrip*nfish if domain4=="hadd" & domain2=="pr" & draw==1
gen nfish1= tot_ntrip_not*nfish  if domain4=="hadd" & domain2=="pr" & draw==1
gen nfish2= tot_ntrip2*nfish  if domain4=="hadd" & domain2=="pr" & draw==1

su nfish2 
return list
local new = `r(sum)'

su nfish1 
return list
local not_truc = `r(sum)'
di `new'-`not_truc'
di ((`new'-`not_truc')/`not_truc')*100

su tot_ntrip2 
return list
local new = `r(sum)'

su tot_ntrip_not 
return list
local not_truc = `r(sum)'
di `new'-`not_truc'
di ((`new'-`not_truc')/`not_truc')*100
*end checks 

drop group tab sum_neg sum_non_neg mean_sum_neg  prop  adjust nfish1 nfish2 nfish0
drop tot_ntrip_not_trunc tot_ntrip
rename tot_ntrip2 tot_ntrip
sort domain draw nfish

*When the # of trips that catch zero fish==0, it creates problems. Replace these instances with 
*the mean # of trips that catch zero fish across draws for a given nfish bin
/*
bysort domain nfish: egen mean_non_zero=mean(tot) if tot!=0
sort domain nfish tot
browse if nfish==0 & tot==0
egen mean_mean_non_zero=mean(mean_non_zero), by(domain nfish)

replace tot_ntrip=mean_mean_non_zero if nfish==0 & tot_ntrip==0
drop  mean_non_zero mean_mean_non_zero
*/

*When the # of trips that catch zero fish==0, it creates problems. Replace these instances with tot_ntrips=1
replace tot_ntrip=1 if nfish==0 & tot_ntrip==0 



/*
egen sumtrips=sum(tot), by(domain draw)
browse if sum==0
egen mean_ntrips=mean(tot) if tot!=0, by(domain draw)
egen mean_mean_ntrips=mean(mean_ntrips), by(domain )
sort domain draw
replace tot=mean_mean_ntrips if sumtrips==0

drop sumtrips mean_ntrips mean_mean_ntrips
*/
reshape wide tot_ntrip, i(nfish domain) j(draw)

order domain
sort domain nfish 


rename domain1 month
rename domain2 mode
drop domain3
rename domain4 species
rename domain5 disp

*drop shore trips
drop if mode=="sh"

order domai*

encode domain, gen(domain3)
xtset domain3 nfish

tsfill, full
mvencode tot*, mv(0) override
decode domain3, gen(disp4)

drop domain  month mode species disp
rename disp4 domain
rename domain xvar
split xvar, parse("_")
rename xvar1 month
rename xvar2 mode
drop xvar3
rename xvar4 species
rename xvar5 disp
rename xvar domain

gen domain2=month+"_"+mode

order domain* month mode species disp

tempfile new
save `new', replace 

global domainz

levelsof domain2, local(doms) 
foreach d of local doms{
u `new', clear 

keep if domain2=="`d'"

keep  domain* month mode species disp nfish tot_ntrip*

drop if disp=="catch"


preserve
keep if disp=="keep"
keep if species=="cod"
renvarlab tot*, postfix(_keep_cod)
drop disp
drop species
tempfile keepcod
save `keepcod', replace 
restore

preserve
keep if disp=="rel"
keep if species=="cod"
renvarlab tot*, postfix(_rel_cod)
drop disp
drop species
tempfile relcod
save `relcod', replace 
restore

preserve
keep if disp=="keep"
keep if species=="hadd"
renvarlab tot*, postfix(_keep_hadd)
drop disp
drop species
tempfile keephadd
save `keephadd', replace 
restore

keep if disp=="rel" & species=="hadd"
drop species

drop disp
renvarlab tot*, postfix(_rel_hadd)
merge 1:1 nfish month mode   using `keepcod', keep(3) nogen
merge 1:1 nfish month mode   using `relcod', keep(3) nogen
merge 1:1 nfish month mode   using `keephadd', keep(3) nogen


*We need to make sure that for each draw, the total number of trips 
*in the keep distribution equals the total number of trips in the release distirbution

forv i =1/$ndraws{

*compute the sum of trips in the keep/release distirbutions by draw 
egen sum_trips_keep`i'_cod=sum(tot_ntrip`i'_keep_cod)
egen sum_trips_rel`i'_cod=sum(tot_ntrip`i'_rel_cod)
egen sum_trips_keep`i'_hadd=sum(tot_ntrip`i'_keep_hadd)
egen sum_trips_rel`i'_hadd=sum(tot_ntrip`i'_rel_hadd)

*compute proportions of trips that kept/released c fish in each draw
gen prop_ntrips_rel`i'_cod=tot_ntrip`i'_rel_cod/sum_trips_rel`i'_cod
gen prop_ntrips_rel`i'_hadd=tot_ntrip`i'_rel_hadd/sum_trips_rel`i'_hadd
gen prop_ntrips_keep`i'_hadd=tot_ntrip`i'_keep_hadd/sum_trips_keep`i'_hadd
gen prop_ntrips_keep`i'_cod=tot_ntrip`i'_keep_cod/sum_trips_keep`i'_cod

*compute the number of trips that kept/released c fish in each draw. 
*use the hadd rel distribution as the baseline 
gen tot_ntrip`i'_rel_new_hadd=tot_ntrip`i'_rel_hadd

*multiply the proportion of trips that released cod, kept haddock, and released haddock
*by the total number of trips in the hadd rel distribution
gen tot_ntrip`i'_rel_new_cod=prop_ntrips_rel`i'_cod*sum_trips_rel`i'_hadd
gen tot_ntrip`i'_keep_new_cod=prop_ntrips_keep`i'_cod*sum_trips_rel`i'_hadd
gen tot_ntrip`i'_keep_new_hadd=prop_ntrips_keep`i'_hadd*sum_trips_rel`i'_hadd

 drop  sum_trips_keep`i'_cod sum_trips_rel`i'_cod sum_trips_keep`i'_hadd sum_trips_rel`i'_hadd ///
		  prop_ntrips_rel`i'_cod prop_ntrips_rel`i'_hadd prop_ntrips_keep`i'_hadd   ///
		  tot_ntrip`i'_rel_cod tot_ntrip`i'_keep_cod tot_ntrip`i'_rel_hadd tot_ntrip`i'_keep_hadd prop_ntrips_keep`i'_cod
}


drop domain
drop domain3

preserve
drop *rel_new* *keep_new_hadd
renvarlab tot_ntrip*, postdrop(13) 
gen disp="keep"
gen species="cod"
tempfile keepcod
save `keepcod', replace
restore

preserve
drop *rel_new* *keep_new_cod
renvarlab tot_ntrip*, postdrop(14) 
gen disp="keep"
gen species="hadd"
tempfile keephadd
save `keephadd', replace
restore

preserve
drop *keep_new* *rel_new_hadd
renvarlab tot_ntrip*, postdrop(12) 
gen disp="rel"
gen species="cod"
tempfile relcod
save `relcod', replace
restore


drop *keep_new* *rel_new_cod
renvarlab tot_ntrip*, postdrop(13) 
gen disp="rel"
gen species="hadd"

append using `keepcod'
append using `keephadd'
append using `relcod'

gen domain = month+"_"+mode+"_"+species+"_"+disp
order domain month mode species disp nfish

tempfile domainz`d'
save `domainz`d'', replace
global domainz "$domainz "`domainz`d''" " 

}
clear 
dsconcat $domainz

drop domain2

mvencode tot_ntrip*, mv(0) over

save "$iterative_input_data_cd\catch per trip1.dta", replace 


/*
*check how the resulting catch totals match up to mrip estimates
u "$iterative_data_cd\catch per trip1.dta", clear 

forv i =1/150{
gen nfish2`i'=tot_ntrip`i'*nfish
egen sum_nfish2`i'=sum(nfish2`i'), by(species disp mode  )
}

collapse (mean) sum_nfish2*, by(species disp mode )
reshape long sum_nfish2, i(species disp mode ) j(new)
collapse (mean) sum_nfish2*, by(species disp mode )
tempfile sim 
save `sim', replace 

import delimited using "$input_data_cd\MRIP_catch_totals_open_season.csv", clear 
drop ll* ul* 
ds mode season, not
renvarlab `r(varlist)', prefix(mrip_)
reshape long mrip_, i(mode season) j(new) string
split new, parse(_)
rename new1 species
rename new2 disp
drop new3 new
collapse (sum) mrip_, by(species disp mode)
drop if disp=="catch"
merge 1:1 mode disp species using `sim'
gen diff=sum-mrip
gen pdiff=((sum-mrip)/mrip)*100

collapse (sum) mrip_ sum, by(species  mode)
gen diff=sum-mrip
gen pdiff=((sum-mrip)/mrip)*100

*/

*Now create a file for each draw that contains:
	*a) 50 trips per day of the fishing season, each with 30 draws of catch-per-trip
	*b) demographics for each trip that are constant across catch draws
	
*Will add age and avidities here
import excel using "$input_data_cd\population ages.xlsx", clear firstrow
keep if region=="MENY"
replace wtd_fre=round(wtd_fre)
expand wtd_fre
keep age
tempfile ages 
save `ages', replace 

import excel using "$input_data_cd\population avidity.xlsx", clear firstrow
keep if region=="MENY"
replace wtd_fre=round(wtd_fre)
expand wtd_fre
keep days_fished
tempfile avidities 
save `avidities', replace 

import delimited using  "$input_data_cd\directed_trips_calib_150draws_cm.csv", clear 
gen wave = 1 if inlist(month, 1, 2)
replace wave=2 if inlist(month, 3, 4)
replace wave=3 if inlist(month, 5, 6)
replace wave=4 if inlist(month, 7, 8)
replace wave=5 if inlist(month, 9, 10)
replace wave=6 if inlist(month, 11, 12)
drop month1
tostring month, gen(month1)
tostring wave, gen(wave1)

drop if dtrip==0

keep day_i day  mode month month1 dtrip wave wave1 draw

gen domain1=mode+"_"+day
gen domain=mode+"_"+month1

encode domain1, gen(domain3)

tempfile trips
save `trips', replace

qui forv i=1/$ndraws{

u `trips', clear  
keep if draw==`i'

tempfile trips2
save `trips2', replace 

global domainz

levelsof domain3, local(doms) 
foreach d of local doms{
	u `trips2', clear 
	keep if domain3==`d'
	levelsof mode, local(md) clean
	levelsof month, local(mnth)
	levelsof day_i, local(day_i1)
	levelsof day, local(day1) clean
	levelsof domain, local(dom) clean
	levelsof wave, local(wv) 
	levelsof dtrip, local(dtrip) 
	levelsof domain1, local(dom1) clean

	u "$iterative_input_data_cd\catch per trip1.dta", clear 
	drop if disp=="catch"
	drop domain
	destring month, replace
	tostring month, gen(month1)
	drop month 
	rename month1 month 
	gen domain=mode+"_"+month
	gen domain2=mode+"_"+month+"_"+species
	order domain*

	keep if domain=="`dom'"

	tempfile base`d' 
	save `base`d'', replace 
	
	**keep draws cod
	u `base`d'', clear 
	keep if species=="cod"
	
	ds domain domain2  month mode species disp nfish
	keep `r(varlist)' tot_ntrip`i'

	keep if disp=="keep"

	su tot_ntrip`i'
	gen double prop=tot_ntrip`i'/r(sum)

	keep if prop!=0
	gen ntrip=2000
	replace ntrip=round(ntrip*prop)
	expand ntrip
	
	sample 1500, count
	renvarlab nfish, postfix("cod")
	renvarlab nfish, postfix("keep")
	egen tripid = seq(), f(1) t(50)
	bysort tripid: gen catch_draw=_n
	
	keep month mode nfish tripid catch_draw 
	
	tempfile keep
	save `keep', replace

	
	*release draws cod
	u `base`d'', clear 

	keep if species=="cod"
	
	ds domain domain2  month mode species disp nfish
	keep `r(varlist)' tot_ntrip`i'

	keep if disp=="rel"

	su tot_ntrip`i'
	gen double prop=tot_ntrip`i'/r(sum)

	keep if prop!=0
	gen ntrip=2000
	replace ntrip=round(ntrip*prop)
	expand ntrip
	
	sample 1500, count
	renvarlab nfish, postfix("cod")
	renvarlab nfish, postfix("rel")
	egen tripid = seq(), f(1) t(50)
	bysort tripid: gen catch_draw=_n
	
	keep month mode nfish tripid catch_draw 
	
	merge 1:1 tripid catch_draw using `keep', nogen
	
	tempfile cod
	save `cod', replace
	
	
	**keep draws hadd
	u `base`d'', clear 
	keep if species=="hadd"
	
	ds domain domain2  month mode species disp nfish
	keep `r(varlist)' tot_ntrip`i'

	keep if disp=="keep"
	
	su tot_ntrip`i'
	gen double prop=tot_ntrip`i'/r(sum)

	keep if prop!=0
	gen ntrip=2000
	replace ntrip=round(ntrip*prop)
	expand ntrip
	
	sample 1500, count
	renvarlab nfish, postfix("hadd")
	renvarlab nfish, postfix("keep")
	egen tripid = seq(), f(1) t(50)
	bysort tripid: gen catch_draw=_n
	
	keep month mode nfish tripid catch_draw 
	
	tempfile keep
	save `keep', replace


	*release draws hadd
	u `base`d'', clear 

	keep if species=="hadd"
	
	ds domain domain2  month mode species disp nfish
	keep `r(varlist)' tot_ntrip`i'

	keep if disp=="rel"
	
	su tot_ntrip`i'
	
	gen double prop=tot_ntrip`i'/r(sum)

	keep if prop!=0
	gen ntrip=2000
	replace ntrip=round(ntrip*prop)
	expand ntrip
	
	sample 1500, count
	renvarlab nfish, postfix("hadd")
	renvarlab nfish, postfix("rel")
	egen tripid = seq(), f(1) t(50)
	bysort tripid: gen catch_draw=_n
	
	keep month mode nfish tripid catch_draw 
	
	merge 1:1 tripid catch_draw using `keep', nogen
	
		
	***Merge to the other species 
	merge 1:1 tripid catch_draw using  `cod', nogen
	gen domain3=`d'
	gen domain="`dom'"
	gen day_i=`day_i1'
	gen day ="`day1'"
	gen wave=`wv'	
	gen draw = `i'
	gen dtrip=`dtrip'
	gen domain1="`dom1'"

	gen cod_catch=nfishcodrel+nfishcodkeep
	gen hadd_catch=nfishhaddrel+nfishhaddkeep

	rename nfishcodrel cod_rel
	rename nfishcodkeep cod_keep
	
	rename nfishhaddrel hadd_rel
	rename nfishhaddkeep hadd_keep

	preserve
	u `ages', clear 
	sample 50, count
	gen tripid=_n
	tempfile ages2
	save `ages2', replace	
	restore 
	
	preserve
	u `avidities', clear 
	sample 50, count
	gen tripid=_n
	tempfile avidities2
	save `avidities2', replace	
	restore 
	
	merge m:1 tripid using `ages2', keep(3) nogen
	merge m:1 tripid using `avidities2', keep(3) nogen

	gen cost=rnormal($fh_cost_est, $fh_cost_sd) if mode=="fh" & catch_draw==1
	replace cost=rnormal($pr_cost_est, $pr_cost_sd) if mode=="pr" & catch_draw==1
	replace cost=rnormal($sh_cost_est, $sh_cost_sd) if mode=="sh" & catch_draw==1

	egen mean_cost=mean(cost), by(tripid)
	
	drop cost
	rename mean_cost cost 
	
	
	tempfile domainz`d'
	save `domainz`d'', replace
	global domainz "$domainz "`domainz`d''" " 

}


clear
dsconcat $domainz

order domain1 domain wave wave month mode day day_i dtrip draw tripid catch_draw cod_keep cod_rel cod_catch hadd_keep hadd_rel hadd_catch 
drop domain3 domain1 domain
sort day_i mode tripid catch_draw
export delimited using "$iterative_input_data_cd\catch_draws`i'_full.csv", replace 

}


*Now for each of these files, make sure that there are catch draws for periods with directed trips but no catch 

global drawz
  forv i=1/$ndraws{

import excel using "$input_data_cd\population ages.xlsx", clear firstrow
keep if region=="MENY"
replace wtd_fre=round(wtd_fre)
expand wtd_fre
keep age
tempfile ages 
save `ages', replace 

import excel using "$input_data_cd\population avidity.xlsx", clear firstrow
keep if region=="MENY"
replace wtd_fre=round(wtd_fre)
expand wtd_fre
keep days_fished
tempfile avidities 

save `avidities', replace 
preserve
u `ages', clear 
sample 50, count
gen tripid=_n
tempfile ages2
save `ages2', replace	
restore 
	
preserve
u `avidities', clear 
sample 50, count
gen tripid=_n
tempfile avidities2
save `avidities2', replace	
restore 

import delimited using  "$input_data_cd\directed_trips_calib_150draws_cm.csv", clear 
keep if draw==`i'
keep day day_i mode dtrip 
duplicates drop 
tempfile draws
save `draws', replace 


import delimited using "$iterative_input_data_cd\catch_draws`i'_full.csv", clear 
tempfile basedraws
save `basedraws', replace 

rename dtrip dtrip_catchfile
keep day day_i mode dtrip 
duplicates drop 

merge 1:1 day day_i mode using `draws'

keep if _merge==2
gen domain=mode+"_"+day
sort  mode day

tempfile base2
save `base2', replace 

global domainz
levelsof domain, local(doms)
foreach d of local doms{

u `base2', clear 

keep if domain=="`d'"
expand 1500
egen tripid = seq(), f(1) t(50)
bysort tripid: gen catch_draw=_n

merge m:1 tripid using `ages2', keep(3) nogen
merge m:1 tripid using `avidities2', keep(3) nogen

gen cost=rnormal($fh_cost_est, $fh_cost_sd) if mode=="fh" & catch_draw==1
replace cost=rnormal($pr_cost_est, $pr_cost_sd) if mode=="pr" & catch_draw==1
replace cost=rnormal($sh_cost_est, $sh_cost_sd) if mode=="sh" & catch_draw==1

egen mean_cost=mean(cost), by(tripid)
	
drop cost
rename mean_cost cost 
gen draw=`i'
tempfile domainz`d'
save `domainz`d'', replace
global domainz "$domainz "`domainz`d''" " 
}

dsconcat $domainz
append using  `basedraws'
mvencode cod_keep cod_rel cod_catch hadd_keep hadd_rel hadd_catch, mv(0) override
drop _merge month wave domain dtrip_catchfile dtrip

gen day1 = substr(day, 1, 2)
gen month1= substr(day, 3, 3)
gen month="1" if month1=="jan"
replace month="2" if month1=="feb"
replace month="3" if  month1=="mar"
replace month="4" if   month1=="apr"
replace month="5" if  month1=="may"
replace month="6" if  month1=="jun"
replace month="7" if  month1=="jul"
replace month="8" if  month1=="aug"
replace month="9" if  month1=="sep"
replace month="10" if  month1=="oct"
replace month="11" if  month1=="nov"
replace month="12" if  month1=="dec"
gen period2 = month+ "_"+ day1+ "_"+ mode
destring month, replace 
destring day1, replace 


export delimited using "$iterative_input_data_cd\catch_draws`i'_full.csv", replace 

 }
 

