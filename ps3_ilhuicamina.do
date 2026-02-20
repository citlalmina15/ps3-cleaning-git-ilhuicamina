** CWD 
cd "C:\Users\citla\Downloads\pset3_data"
capture log close
log using "logs\ps3.log", replace

** Part A: Clean and validate people_full.csv
import delimited "people_full.csv", clear stringcols(_all)

** Standardize strings
replace location = strtrim(location)
replace location = strlower(location)
replace location = strproper(location)
replace sex = strtrim(sex)

** Convert numeric columns
foreach v in person_id household_id age height_cm weight_kg systolic_bp diastolic_bp {
    replace `v' = "" if `v' == "NA"
    destring `v', replace
}

** Date/time conversion
gen visit_date = date(date_str, "MDY")
format visit_date %td
gen people_year = yofd(visit_date)
gen visit_time = clock(time_str, "hms")
format visit_time %tcHH:MM:SS

** QA checks
assert !missing(person_id)
isid person_id people_year
bysort person_id: assert _N == 5

** Categorical encodings
encode sex, gen(sex_id)
encode location, gen(location_id)

** Grouped variables
bysort household_id: gen hh_n = _N
bysort household_id (person_id people_year): gen hh_row = _n
bysort household_id: egen hh_mean_age = mean(age)

** Export
export delimited "processed_data/ps3_people_clean.csv", replace

** Part A: Clean and validate households.csv
import delimited "households.csv", clear stringcols(_all)

** Convert numeric columns
foreach v in household_id year region_id income hh_size {
    replace `v' = "" if `v' == "NA"
    destring `v', replace
}

** Categorical encoding
encode region, gen(region_code)
label list region_code

** Grouped variables
bysort year: egen year_mean_income = mean(income)
bysort region_code year: egen region_year_mean_income = mean(income)
bysort region_code (year): gen region_year_row = _n

** Regression
reg income i.region_code c.hh_size##c.year

** Export
export delimited "processed_data/ps3_households_clean.csv", replace

** Part A: Clean and validate regions.csv
import delimited "regions.csv", clear stringcols(_all) varnames(1)
describe

** Convert numeric columns
foreach v in region_id year median_income population {
    replace `v' = "" if `v' == "NA"
    destring `v', replace
}

** Drop missing panel keys
drop if missing(region_id) | missing(year)

** Resolve duplicates
duplicates report region_id year
duplicates drop region_id year, force

** Verify uniqueness and declare panel
isid region_id year
xtset region_id year

** Lag-based variables
gen yoy_change_median_income = median_income - L.median_income
gen median_income_growth_rate = (median_income - L.median_income) / L.median_income

** Panel diagnostics
xtdescribe
xtsum median_income population yoy_change_median_income median_income_growth_rate

** Export
export delimited "processed_data/ps3_regions_clean.csv", replace

** Close log
log close