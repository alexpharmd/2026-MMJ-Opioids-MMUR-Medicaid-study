/*=============================================================================
  MEDICAID OPIOID PHARMACY CLAIM IDENTIFICATION
  Florida Medicaid Pharmacy Claims, 2017-2024

  Purpose:
    1. Combine FFS and MMA pharmacy claims across 2017-2024.
    2. Match pharmacy-claim NDCs to the finalized opioid NDC reference list.
    3. Retain opioid ingredient and route classifications.
    4. Assign exposure/control study group using DATE_REFERENCE.
    5. Perform initial quality-control checks.

  Inputs:
    AHCA.FFS_PHARM_CLAIMS_17 - AHCA.FFS_PHARM_CLAIMS_24
    AHCA.MMA_PHARM_CLAIMS_17 - AHCA.MMA_PHARM_CLAIMS_24
    NDC_LIST.OPIOID_NDC_TRULY_FINAL

  Outputs:
    STUDY.PHARM_CLAIMS_ALL
    STUDY.CLAIMS_OPIOID_MERGED

  Note: Reproduced from the supplied screenshots.
=============================================================================*/

/* WORKSTATION CREATION */
libname study "E:\\perezalexandr\\INCLUSION CRITERIA";
libname ahca  "E:\\AHCA";

/* STEP 1: COMBINE FFS AND MMA PHARMACY CLAIMS, 2017-2024 */
data study.pharm_claims_all
    (keep=bene_ID cde_NDC DTE_first_svc days_supply dsc_strength
          QNTY_dispensed nam_drug_generic date_reference DTE_FIRST_SVC_YR);
    set ahca.ffs_pharm_claims_17
        ahca.ffs_pharm_claims_18
        ahca.ffs_pharm_claims_19
        ahca.ffs_pharm_claims_20
        ahca.ffs_pharm_claims_21
        ahca.ffs_pharm_claims_22
        ahca.ffs_pharm_claims_23
        ahca.ffs_pharm_claims_24
        ahca.mma_pharm_claims_17
        ahca.mma_pharm_claims_18
        ahca.mma_pharm_claims_19
        ahca.mma_pharm_claims_20
        ahca.mma_pharm_claims_21
        ahca.mma_pharm_claims_22
        ahca.mma_pharm_claims_23
        ahca.mma_pharm_claims_24;
run;

/* STEP 2: MATCH PHARMACY CLAIMS TO FINAL OPIOID NDC LIST */
proc sql;
    create table study.claims_opioid_merged as
    select
        a.BENE_ID,
        a.CDE_NDC,
        a.DTE_FIRST_SVC,
        a.DAYS_SUPPLY,
        a.DSC_STRENGTH,
        a.QNTY_DISPENSED,
        a.NAM_DRUG_GENERIC,
        a.DATE_REFERENCE,
        case
            when a.DATE_REFERENCE = 'First Date of OMMU Certification'
                then 'EXPOSURE'
            else 'Control'
        end as study_group,
        b.opioid_ingred,
        b.route_category
    from study.pharm_claims_all as a
    inner join ndc_list.opioid_ndc_truly_final as b
        on a.CDE_NDC = b.ndc_11;
quit;

/* STEP 3: QUALITY CONTROL */
proc sql;
    select count(*) as n_opioid_claims,
           count(distinct BENE_ID) as n_unique_patients
    from study.claims_opioid_merged;
quit;
title 'Total opioid claims and unique paitents after NDC merge';

proc freq data=study.claims_opioid_merged;
    tables study_group / missing;
    title 'Opioid claims by study group (exposure vs control)';
run;

proc sql;
    select study_group,
           count(distinct BENE_ID) as n_unique_patients
    from study.claims_opioid_merged
    group by study_group;
quit;
title 'Unique paitents by study group';

title;
