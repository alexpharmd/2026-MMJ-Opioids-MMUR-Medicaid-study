/*****************************************************************************
 Program: 01_identify_type2_diabetes_cohort.sas
 Purpose: Identify beneficiaries with type 2 diabetes using inpatient and
          outpatient claims and combine qualifying beneficiaries into a
          single cohort with eligibility-source indicators.

 Data years: 2017-2024
 Diagnosis definition: ICD-10-CM E11* (Type 2 diabetes mellitus)

 IMPORTANT:
   1. Update the library paths below for the local computing environment.
   2. Do not commit restricted claims data, beneficiary identifiers, or
      machine-specific/private configuration files to a public repository.
   3. Confirm the intended definition of DTE_FIRST_SVC and the outpatient
      eligibility criterion before using this program for final analyses.

 Notes:
   - Inpatient eligibility: at least one E11* diagnosis in any of 25
     diagnosis positions and DTE_FIRST_SVC <= 0.
   - Outpatient eligibility: at least 2 outpatient E11* claims in total,
     with at least 1 E11* outpatient claim on/before the index date.
******************************************************************************/

/*==========================================================================*
  0. USER-SPECIFIED PATHS
  Replace placeholders with local paths, or move these definitions to a
  separate configuration file that is excluded from GitHub.
 *==========================================================================*/

%let project_path = <PROJECT_PATH>;
%let ahca_path    = <AHCA_DATA_PATH>;

libname study "&project_path.";
libname ahca  "&ahca_path.";


/*==========================================================================*
  1. IDENTIFY TYPE 2 DIABETES FROM INPATIENT CLAIMS
 *==========================================================================*/

data work.diab_eligible_ip;
    set
        ahca.ffs_ip_claims_17
        ahca.ffs_ip_claims_18
        ahca.ffs_ip_claims_19
        ahca.ffs_ip_claims_20
        ahca.ffs_ip_claims_21
        ahca.ffs_ip_claims_22
        ahca.ffs_ip_claims_23
        ahca.ffs_ip_claims_24
        ahca.mma_ip_claims_17
        ahca.mma_ip_claims_18
        ahca.mma_ip_claims_19
        ahca.mma_ip_claims_20
        ahca.mma_ip_claims_21
        ahca.mma_ip_claims_22
        ahca.mma_ip_claims_23
        ahca.mma_ip_claims_24
    ;

    /* Search principal and secondary diagnosis fields for ICD-10-CM E11*. */
    array dx_codes[25] CDE_DIAG_PRIM CDE_DIAG_2-CDE_DIAG_25;

    has_diab = 0;

    do i = 1 to dim(dx_codes);
        if not missing(dx_codes[i]) then do;
            if upcase(substr(strip(dx_codes[i]), 1, 3)) = 'E11' then do;
                has_diab = 1;
                leave;
            end;
        end;
    end;

    /* Qualifying inpatient diabetes evidence on/before the index date. */
    if has_diab = 1 and DTE_FIRST_SVC <= 0 then eligible = 1;
    else eligible = 0;

    drop i;
run;

/* Keep one record per beneficiary who meets inpatient eligibility. */
proc sort data=work.diab_eligible_ip(where=(eligible=1))
          out=work.diab_eligible_ip2(keep=BENE_ID)
          nodupkey;
    by BENE_ID;
run;


/*==========================================================================*
  2. IDENTIFY TYPE 2 DIABETES FROM OUTPATIENT CLAIMS
 *==========================================================================*/

data work.diab_eligible_op;
    set
        ahca.ffs_op_claims_17
        ahca.ffs_op_claims_18
        ahca.ffs_op_claims_19
        ahca.ffs_op_claims_20
        ahca.ffs_op_claims_21
        ahca.ffs_op_claims_22
        ahca.ffs_op_claims_23
        ahca.ffs_op_claims_24
        ahca.mma_op_claims_17
        ahca.mma_op_claims_18
        ahca.mma_op_claims_19
        ahca.mma_op_claims_20
        ahca.mma_op_claims_21
        ahca.mma_op_claims_22
        ahca.mma_op_claims_23
        ahca.mma_op_claims_24
    ;

    /* Search principal and secondary diagnosis fields for ICD-10-CM E11*. */
    array dx_codes[25] CDE_DIAG_PRIM CDE_DIAG_2-CDE_DIAG_25;

    has_diab = 0;

    do i = 1 to dim(dx_codes);
        if not missing(dx_codes[i]) then do;
            if upcase(substr(strip(dx_codes[i]), 1, 3)) = 'E11' then do;
                has_diab = 1;
                leave;
            end;
        end;
    end;

    /* Indicators used to count outpatient diabetes claims by beneficiary. */
    total_diab_visit = (has_diab = 1);
    prior_diab_visit = (has_diab = 1 and DTE_FIRST_SVC <= 0);

    drop i;
run;

/* Aggregate outpatient diabetes claims to the beneficiary level. */
proc means data=work.diab_eligible_op nway noprint;
    class BENE_ID;
    var total_diab_visit prior_diab_visit;

    output out=work.diab_eligible_op2(drop=_TYPE_ _FREQ_)
        sum(total_diab_visit) = total_diab_count
        sum(prior_diab_visit) = prior_diab_count;
run;


/*==========================================================================*
  3. APPLY OUTPATIENT ELIGIBILITY RULE

  A beneficiary qualifies through the outpatient pathway when:
      - TOTAL_DIAB_COUNT >= 2, and
      - PRIOR_DIAB_COUNT >= 1.
 *==========================================================================*/

data work.diab_eligible_op3;
    set work.diab_eligible_op2;
    if total_diab_count >= 2 and prior_diab_count >= 1;
run;


/*==========================================================================*
  4. COMBINE INPATIENT AND OUTPATIENT ELIGIBILITY

  Creates one record per beneficiary meeting either eligibility pathway and
  retains indicators identifying the source of eligibility:
      ELIG_VIA_IP = qualifying inpatient evidence
      ELIG_VIA_OP = qualifying outpatient evidence
 *==========================================================================*/

proc sort data=work.diab_eligible_ip2(keep=BENE_ID)
          out=work.ip_sort nodupkey;
    by BENE_ID;
run;

proc sort data=work.diab_eligible_op3(keep=BENE_ID)
          out=work.op_sort
          nodupkey;
    by BENE_ID;
run;

data study.combined_diab_elig3;
    merge work.ip_sort(in=in_ip)
          work.op_sort(in=in_op);
    by BENE_ID;

    /* Retain beneficiaries qualifying through either pathway. */
    if in_ip or in_op;

    elig_via_ip = in_ip;
    elig_via_op = in_op;

    label
        elig_via_ip = "Eligible via inpatient diabetes criterion"
        elig_via_op = "Eligible via outpatient diabetes criterion";
run;


/*==========================================================================*
  5. OPTIONAL QUALITY-CONTROL OUTPUT
 *==========================================================================*/

proc freq data=study.combined_diab_elig3;
    tables elig_via_ip*elig_via_op / missing;
    title "Type 2 Diabetes Cohort: Eligibility Pathway";
run;

title;

proc sql;
    select count(*) as N_Final_Cohort
           label="Number of unique beneficiaries in final diabetes cohort"
    from study.combined_diab_elig3;
quit;

/*****************************************************************************
 End of program
******************************************************************************/
