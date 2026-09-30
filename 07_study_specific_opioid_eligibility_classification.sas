/*=============================================================================
  FILE 10: STUDY-SPECIFIC OPIOID ELIGIBILITY CLASSIFICATION
  Florida Medicaid Pharmacy Claims

  Project:
    Impact of Medical Marijuana Initiation on Opioid Dosing and Use
    Among Florida Medicaid Enrollees With Type 2 Diabetes

  Purpose:
    Apply the study-specific opioid eligibility rules after opioid claims have
    been identified and claim-level MME variables have been constructed.

  Input:
    STUDY.CLAIMS_WITH_MME
      Created in File 9.

  Outputs:
    STUDY.CLAIMS_OPIOID_ELIGIBILITY
      Audit dataset containing ALL opioid claims plus eligibility status and
      exclusion/review reason.

    STUDY.CLAIMS_OPIOID_ELIGIBLE
      Claims retained after applying the study-specific eligibility rules.

    STUDY.CLAIMS_OPIOID_REVIEW
      Claims requiring manual review because available variables are not
      sufficient for confident automated classification.

  Key principles:
    - Do not delete claims before documenting why they are excluded.
    - Eligible routes for the study are oral and transdermal formulations,
      with buccal buprenorphine retained as a prespecified pain formulation.
    - Injectable and other non-study routes are excluded.
    - Methadone eligibility is restricted to oral tablet claims with parsed
      strengths of 5 mg or 10 mg, consistent with the study's prespecified
      pain-management formulation rule.
    - Buprenorphine pain formulations (transdermal and buccal) are retained.
      Sublingual buprenorphine and buprenorphine/naloxone products are excluded
      as OUD-oriented formulations for this study.
    - Codeine is NOT excluded as an ingredient. Analgesic codeine products are
      retained when otherwise eligible; obvious cough/cold codeine combination
      products are excluded using product-name indicators.
    - Claims with insufficient information for confident classification are
      flagged for review rather than automatically discarded.
=============================================================================*/


/*=============================================================================
  WORKSTATION LIBRARY
=============================================================================*/

libname study "F:\perezalexandr\INCLUSION CRITERIA";


/*=============================================================================
  STEP 1: INVENTORY ROUTES AND OPIOID INGREDIENTS BEFORE ELIGIBILITY RULES
=============================================================================*/

proc freq data=study.claims_with_mme order=freq;
    tables route_category / missing;
    title 'File 10: All Available Opioid Routes Before Eligibility Rules';
run;

proc freq data=study.claims_with_mme order=freq;
    tables opioid_ingred / missing;
    title 'File 10: All Available Opioid Ingredients Before Eligibility Rules';
run;


/*=============================================================================
  STEP 2: INVENTORY SPECIAL PRODUCTS BEFORE CLASSIFICATION

  These tables are intentionally produced before exclusions so that the
  observed Medicaid product names/routes can be reviewed.
=============================================================================*/

/* Buprenorphine */
proc freq data=study.claims_with_mme order=freq;
    where upcase(strip(opioid_ingred)) = 'BUPRENORPHINE'
       or index(upcase(strip(nam_drug_generic)), 'BUPRENORPHINE') > 0;
    tables nam_drug_generic*route_category / list missing;
    title 'File 10 QC: Buprenorphine Product Names and Routes';
run;

/* Methadone */
proc freq data=study.claims_with_mme order=freq;
    where upcase(strip(opioid_ingred)) = 'METHADONE';
    tables nam_drug_generic*route_category / list missing;
    title 'File 10 QC: Methadone Product Names and Routes';
run;

proc freq data=study.claims_with_mme order=freq;
    where upcase(strip(opioid_ingred)) = 'METHADONE';
    tables opioid_strength_mg / missing;
    title 'File 10 QC: Methadone Parsed Strengths';
run;

/* Codeine */
proc freq data=study.claims_with_mme order=freq;
    where upcase(strip(opioid_ingred)) = 'CODEINE';
    tables nam_drug_generic*route_category / list missing;
    title 'File 10 QC: Codeine Product Names and Routes';
run;


/*=============================================================================
  STEP 3: CLASSIFY STUDY-SPECIFIC OPIOID ELIGIBILITY

  Variables:
    OPIOID_ELIGIBLE
      1 = retained for the study
      0 = excluded
      . = manual review required

    ELIGIBILITY_STATUS
      RETAIN / EXCLUDE / REVIEW

    EXCLUSION_REASON
      Specific reason for exclusion or manual review.

  The classification is hierarchical. Product-specific rules for
  buprenorphine, methadone, and codeine are applied explicitly.
=============================================================================*/

data study.claims_opioid_eligibility;
    set study.claims_with_mme;

    length ingred_clean $50
           route_clean $40
           drug_clean $200
           eligibility_status $10
           exclusion_reason $100;

    ingred_clean = upcase(strip(opioid_ingred));
    route_clean  = upcase(strip(route_category));
    drug_clean   = upcase(strip(nam_drug_generic));

    opioid_eligible = .;
    eligibility_status = 'REVIEW';
    exclusion_reason = 'UNCLASSIFIED';

    /*---------------------------------------------------------------------
      RULE 1: Missing ingredient or route cannot be confidently classified.
    ---------------------------------------------------------------------*/
    if missing(ingred_clean) then do;
        opioid_eligible = .;
        eligibility_status = 'REVIEW';
        exclusion_reason = 'MISSING_OPIOID_INGREDIENT';
    end;

    else if missing(route_clean) or route_clean = 'UNCLASSIFIED' then do;
        opioid_eligible = .;
        eligibility_status = 'REVIEW';
        exclusion_reason = 'MISSING_OR_UNCLASSIFIED_ROUTE';
    end;

    /*---------------------------------------------------------------------
      RULE 2: Exclude injectable/parenteral products.
    ---------------------------------------------------------------------*/
    else if route_clean = 'INJECTABLE' then do;
        opioid_eligible = 0;
        eligibility_status = 'EXCLUDE';
        exclusion_reason = 'INJECTABLE_ROUTE';
    end;

    /*---------------------------------------------------------------------
      RULE 3: BUPRENORPHINE

      Retain prespecified pain formulations:
        - Transdermal
        - Buccal

      Exclude:
        - Sublingual formulations
        - Buprenorphine/naloxone products

      Other formulations are sent to review.
    ---------------------------------------------------------------------*/
    else if ingred_clean = 'BUPRENORPHINE' then do;

        if index(drug_clean, 'NALOXONE') > 0 then do;
            opioid_eligible = 0;
            eligibility_status = 'EXCLUDE';
            exclusion_reason = 'BUPRENORPHINE_NALOXONE_OUD_PRODUCT';
        end;

        else if route_clean = 'SUBLINGUAL'
             or index(route_clean, 'SUBLINGUAL') > 0 then do;
            opioid_eligible = 0;
            eligibility_status = 'EXCLUDE';
            exclusion_reason = 'BUPRENORPHINE_SUBLINGUAL_OUD_FORM';
        end;

        else if route_clean = 'TRANSDERMAL' then do;
            opioid_eligible = 1;
            eligibility_status = 'RETAIN';
            exclusion_reason = '';
        end;

        else if route_clean = 'BUCCAL'
             or index(route_clean, 'BUCCAL') > 0 then do;
            opioid_eligible = 1;
            eligibility_status = 'RETAIN';
            exclusion_reason = '';
        end;

        else do;
            opioid_eligible = .;
            eligibility_status = 'REVIEW';
            exclusion_reason = 'BUPRENORPHINE_FORMULATION_REVIEW';
        end;
    end;

    /*---------------------------------------------------------------------
      RULE 4: METHADONE

      Study protocol rule:
        Retain oral tablet claims with 5-mg or 10-mg strength.
        Exclude strengths >10 mg.
        Review other/missing strengths rather than assuming eligibility.

      Route/product-name checks are included because strength alone does not
      establish formulation.
    ---------------------------------------------------------------------*/
    else if ingred_clean = 'METHADONE' then do;

        if route_clean ne 'ORAL' then do;
            opioid_eligible = 0;
            eligibility_status = 'EXCLUDE';
            exclusion_reason = 'METHADONE_NONORAL_ROUTE';
        end;

        else if index(drug_clean, 'TABLET') = 0 then do;
            opioid_eligible = .;
            eligibility_status = 'REVIEW';
            exclusion_reason = 'METHADONE_ORAL_FORM_REVIEW';
        end;

        else if opioid_strength_mg in (5,10) then do;
            opioid_eligible = 1;
            eligibility_status = 'RETAIN';
            exclusion_reason = '';
        end;

        else if opioid_strength_mg > 10 then do;
            opioid_eligible = 0;
            eligibility_status = 'EXCLUDE';
            exclusion_reason = 'METHADONE_STRENGTH_GT10MG';
        end;

        else do;
            opioid_eligible = .;
            eligibility_status = 'REVIEW';
            exclusion_reason = 'METHADONE_STRENGTH_REVIEW';
        end;
    end;

    /*---------------------------------------------------------------------
      RULE 5: CODEINE

      Codeine itself is not excluded. Retain analgesic codeine products when
      route is otherwise eligible.

      Exclude obvious cough/cold combination products using generic-name
      indicators observed/anticipated in pharmacy claims.

      This rule intentionally avoids excluding acetaminophen/codeine and
      other analgesic combinations merely because they contain codeine.
    ---------------------------------------------------------------------*/
    else if ingred_clean = 'CODEINE' then do;

        if index(drug_clean, 'GUAIFENESIN') > 0
        or index(drug_clean, 'PROMETHAZINE') > 0
        or index(drug_clean, 'PSEUDOEPHEDRINE') > 0
        or index(drug_clean, 'PHENYLEPHRINE') > 0
        or index(drug_clean, 'BROMPHENIRAMINE') > 0
        or index(drug_clean, 'CHLORPHENIRAMINE') > 0 then do;

            opioid_eligible = 0;
            eligibility_status = 'EXCLUDE';
            exclusion_reason = 'CODEINE_COUGH_COLD_PRODUCT';
        end;

        else if route_clean = 'ORAL' then do;
            opioid_eligible = 1;
            eligibility_status = 'RETAIN';
            exclusion_reason = '';
        end;

        else do;
            opioid_eligible = .;
            eligibility_status = 'REVIEW';
            exclusion_reason = 'CODEINE_FORMULATION_REVIEW';
        end;
    end;

    /*---------------------------------------------------------------------
      RULE 6: OTHER OPIOIDS

      For the remaining opioid ingredients, retain oral and transdermal
      products. Other routes are excluded from this study.
    ---------------------------------------------------------------------*/
    else if route_clean in ('ORAL','TRANSDERMAL') then do;
        opioid_eligible = 1;
        eligibility_status = 'RETAIN';
        exclusion_reason = '';
    end;

    else do;
        opioid_eligible = 0;
        eligibility_status = 'EXCLUDE';
        exclusion_reason = 'ROUTE_NOT_STUDY_ELIGIBLE';
    end;

    label opioid_eligible =
              'Study-specific opioid claim eligibility'
          eligibility_status =
              'Opioid eligibility status'
          exclusion_reason =
              'Opioid exclusion or review reason';

    drop ingred_clean route_clean drug_clean;
run;


/*=============================================================================
  STEP 4: CREATE RETAINED AND MANUAL-REVIEW DATASETS
=============================================================================*/

data study.claims_opioid_eligible;
    set study.claims_opioid_eligibility;
    where opioid_eligible = 1;
run;

data study.claims_opioid_review;
    set study.claims_opioid_eligibility;
    where missing(opioid_eligible);
run;


/*=============================================================================
  STEP 5: OVERALL ELIGIBILITY QC
=============================================================================*/

proc freq data=study.claims_opioid_eligibility order=freq;
    tables eligibility_status exclusion_reason / missing;
    title 'File 10 QC: Opioid Eligibility Status and Reasons';
run;

proc sql;
    title 'File 10 QC: Opioid Claim Counts Before and After Eligibility Rules';

    select count(*) as original_claim_count format=comma15.
    from study.claims_with_mme;

    select count(*) as retained_claim_count format=comma15.
    from study.claims_opioid_eligible;

    select count(*) as excluded_claim_count format=comma15.
    from study.claims_opioid_eligibility
    where opioid_eligible = 0;

    select count(*) as review_claim_count format=comma15.
    from study.claims_opioid_review;
quit;


/*=============================================================================
  STEP 6: COUNT EACH EXCLUSION/REVIEW CATEGORY
=============================================================================*/

proc sql;
    title 'File 10 QC: Detailed Eligibility Counts';

    select
        eligibility_status,
        exclusion_reason,
        count(*) as n_claims format=comma15.,
        count(distinct bene_id) as n_unique_patients format=comma15.
    from study.claims_opioid_eligibility
    group by eligibility_status, exclusion_reason
    order by eligibility_status, calculated n_claims desc;
quit;


/*=============================================================================
  STEP 7: ROUTE AND INGREDIENT DISTRIBUTION AFTER ELIGIBILITY RULES
=============================================================================*/

proc freq data=study.claims_opioid_eligible order=freq;
    tables route_category opioid_ingred / missing;
    title 'File 10 QC: Routes and Opioid Ingredients Retained';
run;


/*=============================================================================
  STEP 8: METHADONE QC
=============================================================================*/

proc freq data=study.claims_opioid_eligibility order=freq;
    where upcase(strip(opioid_ingred)) = 'METHADONE';
    tables opioid_strength_mg*eligibility_status / list missing;
    title 'File 10 QC: Methadone Strength by Eligibility Status';
run;

proc print data=study.claims_opioid_review(obs=100);
    where upcase(strip(opioid_ingred)) = 'METHADONE';

    var bene_id
        cde_ndc
        dte_first_svc
        nam_drug_generic
        route_category
        dsc_strength
        opioid_strength_mg
        eligibility_status
        exclusion_reason;

    title 'File 10 QC: Methadone Claims Requiring Review';
run;


/*=============================================================================
  STEP 9: BUPRENORPHINE QC
=============================================================================*/

proc freq data=study.claims_opioid_eligibility order=freq;
    where upcase(strip(opioid_ingred)) = 'BUPRENORPHINE'
       or index(upcase(strip(nam_drug_generic)), 'BUPRENORPHINE') > 0;

    tables nam_drug_generic*route_category*eligibility_status / list missing;
    title 'File 10 QC: Buprenorphine Product, Route, and Eligibility';
run;

proc print data=study.claims_opioid_review(obs=100);
    where upcase(strip(opioid_ingred)) = 'BUPRENORPHINE'
       or index(upcase(strip(nam_drug_generic)), 'BUPRENORPHINE') > 0;

    var bene_id
        cde_ndc
        dte_first_svc
        nam_drug_generic
        route_category
        dsc_strength
        opioid_strength_mg
        eligibility_status
        exclusion_reason;

    title 'File 10 QC: Buprenorphine Claims Requiring Review';
run;


/*=============================================================================
  STEP 10: CODEINE QC

  Confirm that analgesic products were retained while cough/cold products were
  excluded or sent for review when appropriate.
=============================================================================*/

proc freq data=study.claims_opioid_eligibility order=freq;
    where upcase(strip(opioid_ingred)) = 'CODEINE';

    tables nam_drug_generic*eligibility_status / list missing;
    title 'File 10 QC: Codeine Product Eligibility';
run;

proc print data=study.claims_opioid_eligibility(obs=100);
    where upcase(strip(opioid_ingred)) = 'CODEINE'
          and eligibility_status ne 'RETAIN';

    var bene_id
        cde_ndc
        dte_first_svc
        nam_drug_generic
        route_category
        dsc_strength
        opioid_strength_mg
        eligibility_status
        exclusion_reason;

    title 'File 10 QC: Codeine Claims Not Automatically Retained';
run;


/*=============================================================================
  STEP 11: UNIQUE BENEFICIARY COUNTS
=============================================================================*/

proc sql;
    title 'File 10: Unique Beneficiaries With Study-Eligible Opioid Claims';

    select count(distinct bene_id) as total_unique_patients format=comma15.
    from study.claims_opioid_eligible;
quit;


/*=============================================================================
  STEP 12: FINAL REVIEW DATASET SUMMARY

  IMPORTANT:
    Review STUDY.CLAIMS_OPIOID_REVIEW before downstream cohort construction.
    If recurring products can be resolved confidently, their rules should be
    incorporated into this program so that the classification remains
    reproducible rather than manually editing individual claims.
=============================================================================*/

proc freq data=study.claims_opioid_review order=freq;
    tables opioid_ingred route_category exclusion_reason / missing;
    title 'File 10: Claims Requiring Manual Eligibility Review';
run;

proc print data=study.claims_opioid_review(obs=200);
    var bene_id
        cde_ndc
        dte_first_svc
        nam_drug_generic
        opioid_ingred
        route_category
        dsc_strength
        opioid_strength_mg
        exclusion_reason;

    title 'File 10: Sample of Claims Requiring Manual Eligibility Review';
run;

title;


/*=============================================================================
  END OF FILE 10

  NEXT ANALYTIC STEP:
    After the review category has been resolved and the opioid eligibility
    rules are finalized, use STUDY.CLAIMS_OPIOID_ELIGIBLE to construct:
      - chronic opioid-use eligibility;
      - baseline and follow-up opioid exposure;
      - total MME over prespecified periods;
      - MME/day;
      - >=30% MME reduction;
      - opioid prescription-fill outcomes; and
      - opioid discontinuation.

  NOTE:
    Buprenorphine pain formulations retained by this eligibility program may
    remain eligible opioid-use claims even when CDC-2022-based MME is not
    calculable. Opioid-use outcomes and MME-based outcomes should therefore
    remain analytically distinguishable.
=============================================================================*/
