** TASK 1: Initialize and begin logging

** CWD
cd "C:\Users\citla\Downloads\PS5"

* Create logs and processed_data directories if they do not exist
capture mkdir logs
capture mkdir processed_data

* Close any open logs and start fresh
capture log close _all
log using "logs/ps5.log", replace text

display "Log started: $S_DATE $S_TIME"

** TASK 2: Import the data without forcing all columns to strings

import delimited "data/psam_p50.csv", clear varnames(1)

** Verify dataset has more than 100 variables
ds
local nvars = r(varlist)
local nv = wordcount("`nvars'")
display "Number of variables in dataset: `nv'"
assert `nv' > 100
display "CONFIRMED: dataset has more than 100 variables."

** TASK 3: Define numeric and categorical column macros

** Define macro for numeric variables (lowercase to match dataset)
local numeric_vars "agep wagp wkhp schl pincp povpip esr cow mar sex rac1p hisp adjinc pwgtp"

* Define macro for categorical (string) variables (lowercase to match dataset)
local categorical_vars "naicsp socp"

** Display both macro contents in the log
display "numeric_vars macro: `numeric_vars'"
display "categorical_vars macro: `categorical_vars'"

** --- Loop over numeric_vars: verify existence and convert to numeric if needed ---
foreach v of local numeric_vars {
    * Verify variable exists
    capture confirm variable `v'
    if _rc != 0 {
        display as error "WARNING: variable `v' not found in dataset."
    }
    else {
        display as txt "Confirmed variable exists: `v'"
        * Replace common missing-value strings with blank, then destring if needed
        capture confirm string variable `v'
        if _rc == 0 {
            replace `v' = "" if inlist(strtrim(`v'), "NA", ".", "N/A", "")
            destring `v', replace
            display as txt "  -> destringed: `v'"
        }
    }
}

** --- Loop over categorical_vars: clean strings and encode to _id variables ---
foreach v of local categorical_vars {
    capture confirm variable `v'
    if _rc != 0 {
        display as error "WARNING: variable `v' not found in dataset."
    }
    else {
        display as txt "Confirmed variable exists: `v'"
        * Standardize string formatting
        replace `v' = strtrim(`v')
        replace `v' = strlower(`v')
        replace `v' = strproper(`v')
        * Encode to numeric _id variable
        encode `v', gen(`v'_id)
        display as txt "  -> encoded: `v'_id created."
    }
}

** TASK 4: QA checks and save cleaned full file

** Check for missing key fields
display "--- Missing value counts for key variables ---"
foreach v of local numeric_vars {
    capture confirm variable `v'
    if _rc == 0 {
        quietly count if missing(`v')
        display as txt "`v': `r(N)' missing"
    }
}

** Check uniqueness of serialno sporder
duplicates report serialno sporder
isid serialno sporder

display "CONFIRMED: serialno sporder uniquely identify observations."

** Save cleaned full dataset
save "processed_data/ps5_cleaned_full.dta", replace
display "Saved: processed_data/ps5_cleaned_full.dta"

** TASK 5: Build a sample-construction table

tempname sample_post
tempfile sample_steps

postfile `sample_post' str80 step int n_remaining int n_excluded ///
    using "`sample_steps'", replace

** --- Step 0: Starting point ---
count
local n_prev = r(N)
post `sample_post' ("Start: cleaned observations") (`n_prev') (0)

** --- Inclusion 1: Ages 25-64 ---
keep if inrange(agep, 25, 64)
count
local n_now = r(N)
post `sample_post' ("Inclusion: age 25 to 64") (`n_now') (`n_prev' - `n_now')
local n_prev = `n_now'

** --- Inclusion 2: wagp > 0 and wkhp >= 35 ---
keep if wagp > 0 & !missing(wagp) & wkhp >= 35 & !missing(wkhp)
count
local n_now = r(N)
post `sample_post' ("Inclusion: wagp > 0 and wkhp >= 35") (`n_now') (`n_prev' - `n_now')
local n_prev = `n_now'

** --- Inclusion 3: esr in employed categories (1 or 2) ---
keep if inlist(esr, 1, 2)
count
local n_now = r(N)
post `sample_post' ("Inclusion: esr employed (1 or 2)") (`n_now') (`n_prev' - `n_now')
local n_prev = `n_now'

** --- Exclusion: missing key model covariates ---
drop if missing(agep, schl, wkhp, wagp, pincp, povpip, cow, mar, sex, rac1p, hisp)
count
local n_now = r(N)
post `sample_post' ("Exclusion: missing key numeric covariates") (`n_now') (`n_prev' - `n_now')
local n_prev = `n_now'

** --- Exclusion: missing encoded categorical IDs ---
drop if missing(naicsp_id, socp_id)
count
local n_now = r(N)
post `sample_post' ("Exclusion: missing encoded categorical IDs") (`n_now') (`n_prev' - `n_now')
local n_prev = `n_now'

** --- Create log wage ---
gen ln_wage = ln(wagp)
label var ln_wage "Log annual wage and salary income"

** Close postfile
postclose `sample_post'

** Export sample construction table
preserve
    use "`sample_steps'", clear
    list
    export delimited using "processed_data/ps5_sample_construction.csv", replace
    save "processed_data/ps5_sample_construction.dta", replace
    display "Saved: processed_data/ps5_sample_construction.csv"
restore

**TASK 6: Use macros for model specification and loops
** --- Define covariate block locals ---
local outcome "ln_wage"

local covariates_demo "i.sex i.rac1p i.hisp i.mar agep"

local covariates_humancap "schl wkhp"

local covariates_labor "i.cow i.esr"

local covariates_occ "i.naicsp_id i.socp_id"

local model_covariates "`covariates_demo' `covariates_humancap' `covariates_labor' `covariates_occ'"

** --- Display outcome and model_covariates macros in log ---
display "outcome macro: `outcome'"
display "model_covariates macro: `model_covariates'"

** --- QA loop: report means and SDs for key variables ---
local qa_vars "ln_wage wagp wkhp schl agep"

display "--- QA: Means and Standard Deviations ---"
foreach v of local qa_vars {
    quietly summarize `v'
    display as txt "`v': mean = " %8.3f r(mean) "  sd = " %8.3f r(sd) "  N = " r(N)
}

** --- forvalues loop: count obs with wkhp >= cutoff ---
display "--- WKHP cutoff counts ---"
forvalues cut = 35(5)55 {
    quietly count if wkhp >= `cut'
    display as txt "wkhp >= `cut': " r(N) " observations"
}

** --- Run and store three regression specifications ---
** M1: Demographics only
regress `outcome' `covariates_demo'
estimates store m1
display "Stored: m1 (demographics only)"

** M2: Demographics + human capital
regress `outcome' `covariates_demo' `covariates_humancap'
estimates store m2
display "Stored: m2 (demographics + human capital)"

** M3: Full model
regress `outcome' `model_covariates'
estimates store m3
display "Stored: m3 (full model)"

** Display estimates comparison table
estimates table m1 m2 m3, b(%9.3f) se stats(N r2)

** TASK 7: Required macro-based keep list

** Define keepvars macro with all required variables
local keepvars "serialno sporder agep sex rac1p hisp mar schl wkhp wagp pincp povpip esr cow adjinc pwgtp naicsp socp naicsp_id socp_id ln_wage"

** Verify each kept variable exists before keeping
display "--- Verifying all keepvars exist ---"
foreach v of local keepvars {
    capture confirm variable `v'
    if _rc != 0 {
        display as error "ERROR: variable `v' not found — cannot keep."
    }
    else {
        display as txt "Confirmed: `v'"
    }
}

** Apply macro-driven keep command
keep `keepvars'

** Save final analysis dataset
save "processed_data/ps5_analysis_data.dta", replace
display "Saved: processed_data/ps5_analysis_data.dta"

** TASK 9: Finalize
display "Script completed: $S_DATE $S_TIME"
log close
