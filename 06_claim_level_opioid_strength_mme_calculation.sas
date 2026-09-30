/*=============================================================================
  FILE 9: CLAIM-LEVEL OPIOID STRENGTH AND MME CALCULATION
  Florida Medicaid Pharmacy Claims

  Purpose:
    1. Parse the opioid ingredient strength from Medicaid pharmacy claims.
    2. Attach CDC 2022 MME conversion factors created in File 8.
    3. Calculate claim-level total MME and MME/day where CDC 2022 methodology
       supports calculation.
    4. Handle transdermal fentanyl separately because its CDC factor is based
       on mcg/hour rather than mg/unit.
    5. Preserve opioid claims without a CDC 2022 MME factor and classify why
       MME was not calculated.
    6. Perform quality-control checks before downstream cohort/outcome work.

  Required inputs:
    STUDY.CLAIMS_OPIOID_MERGED
      Created in File 6.

    STUDY.OPIOID_MME_LOOKUP_CDC2022
      Created in File 8.

  Primary output:
    STUDY.CLAIMS_WITH_MME

  IMPORTANT METHODOLOGIC RULES:
    - File 8 is the single source of truth for CDC 2022 conversion factors.
      Do not hard-code alternative methadone or fentanyl factors here.
    - Methadone uses the CDC 2022 factor stored in File 8 (4.7), after
      study-specific eligibility rules have identified pain-eligible claims.
    - The CDC 2022 fentanyl factor applies to TRANSDERMAL fentanyl expressed
      in mcg/hour. Other fentanyl formulations are not assigned a CDC 2022
      MME factor in this program.
    - Buprenorphine may remain an opioid exposure for study purposes but is
      not included in total MME/day calculations using the CDC 2022 table.
    - Unresolved strength parsing is flagged rather than assigned an assumed
      opioid strength.
=============================================================================*/


/*=============================================================================
  WORKSTATION CREATION
  Update path if needed for the local workstation.
=============================================================================*/

libname study "F:\perezalexandr\INCLUSION CRITERIA";


/*=============================================================================
  STEP 1: PARSE INGREDIENT NAMES AND STRENGTH COMPONENTS

  The source claims contain generic drug names and strength strings that may
  represent single-ingredient or combination products.

  This step:
    - normalizes " WITH " to "/"
    - separates up to four ingredient names
    - separates up to four strength components
    - converts mcg strength components to mg for ordinary mg-based products
    - matches the standardized opioid ingredient to the corresponding
      strength component

  IMPORTANT:
    Transdermal fentanyl is handled separately later because the relevant
    CDC 2022 factor is based on mcg/hour, not mg/unit.
=============================================================================*/

data study.claims_with_opioid_strength;
    set study.claims_opioid_merged;

    length drug_name_var_norm $200
           ingred1_name ingred2_name ingred3_name ingred4_name $50
           clean_strength $100
           part1_raw part2_raw part3_raw part4_raw $40
           strength_parse_status $30;

    length strength_part1 strength_part2 strength_part3 strength_part4 8
           opioid_strength_mg opioid_strength_mcg_hr 8;

    /* Normalize drug-name delimiter used in some single/combo product names. */
    drug_name_var_norm =
        tranwrd(upcase(strip(nam_drug_generic)), ' WITH ', '/');

    /* Clean package-volume suffixes such as "(15ml)" when present. */
    clean_strength = strip(dsc_strength);
    if index(clean_strength, '(') > 0 then
        clean_strength = scan(clean_strength, 1, '(');

    /* If a denominator is present, retain the numerator portion for the
       initial component parsing. The original DSC_STRENGTH remains available
       for later formulation-specific review. */
    if index(clean_strength, '/') > 0 then
        clean_strength = scan(clean_strength, 1, '/');

    /* Split generic drug name into up to four ingredient components. */
    ingred1_name = strip(scan(drug_name_var_norm, 1, '/'));
    ingred2_name = strip(scan(drug_name_var_norm, 2, '/'));
    ingred3_name = strip(scan(drug_name_var_norm, 3, '/'));
    ingred4_name = strip(scan(drug_name_var_norm, 4, '/'));

    /* Split strength into up to four components using "-" delimiter. */
    part1_raw = strip(scan(clean_strength, 1, '-'));
    part2_raw = strip(scan(clean_strength, 2, '-'));
    part3_raw = strip(scan(clean_strength, 3, '-'));
    part4_raw = strip(scan(clean_strength, 4, '-'));

    /* Extract numeric values while retaining digits and decimal points. */
    if not missing(part1_raw) then
        strength_part1 = input(compress(part1_raw, '.', 'kd'), ?? best32.);
    if not missing(part2_raw) then
        strength_part2 = input(compress(part2_raw, '.', 'kd'), ?? best32.);
    if not missing(part3_raw) then
        strength_part3 = input(compress(part3_raw, '.', 'kd'), ?? best32.);
    if not missing(part4_raw) then
        strength_part4 = input(compress(part4_raw, '.', 'kd'), ?? best32.);

    /* Convert mcg to mg for ordinary mg-based products.
       Transdermal fentanyl is re-parsed separately below. */
    if index(lowcase(part1_raw), 'mcg') > 0 then strength_part1 = strength_part1 / 1000;
    if index(lowcase(part2_raw), 'mcg') > 0 then strength_part2 = strength_part2 / 1000;
    if index(lowcase(part3_raw), 'mcg') > 0 then strength_part3 = strength_part3 / 1000;
    if index(lowcase(part4_raw), 'mcg') > 0 then strength_part4 = strength_part4 / 1000;

    /* Match the standardized opioid ingredient to the corresponding
       ingredient/strength position. No automatic position-1 fallback is
       used when a match cannot be established. */
    if not missing(opioid_ingred) then do;

        if index(upcase(ingred1_name), upcase(strip(opioid_ingred))) > 0 then do;
            opioid_strength_mg = strength_part1;
            strength_parse_status = 'MATCH_POSITION_1';
        end;
        else if index(upcase(ingred2_name), upcase(strip(opioid_ingred))) > 0 then do;
            opioid_strength_mg = strength_part2;
            strength_parse_status = 'MATCH_POSITION_2';
        end;
        else if index(upcase(ingred3_name), upcase(strip(opioid_ingred))) > 0 then do;
            opioid_strength_mg = strength_part3;
            strength_parse_status = 'MATCH_POSITION_3';
        end;
        else if index(upcase(ingred4_name), upcase(strip(opioid_ingred))) > 0 then do;
            opioid_strength_mg = strength_part4;
            strength_parse_status = 'MATCH_POSITION_4';
        end;
        else do;
            opioid_strength_mg = .;
            strength_parse_status = 'UNRESOLVED';
        end;
    end;
    else strength_parse_status = 'MISSING_OPIOID_INGREDIENT';

    /* Transdermal fentanyl:
       Recover the original mcg/hour strength directly from DSC_STRENGTH.
       Do not use the mg-converted opioid_strength_mg value for MME. */
    if upcase(strip(opioid_ingred)) = 'FENTANYL'
       and upcase(strip(route_category)) = 'TRANSDERMAL' then do;

        opioid_strength_mcg_hr =
            input(compress(scan(strip(dsc_strength), 1, '/'), '.', 'kd'),
                  ?? best32.);

        if not missing(opioid_strength_mcg_hr) then
            strength_parse_status = 'FENTANYL_MCG_HR_PARSED';
        else
            strength_parse_status = 'FENTANYL_STRENGTH_UNRESOLVED';
    end;

    drop part1_raw part2_raw part3_raw part4_raw;
run;


/*=============================================================================
  STEP 2: STRENGTH-PARSING QUALITY CONTROL
=============================================================================*/

proc freq data=study.claims_with_opioid_strength;
    tables strength_parse_status / missing;
    title 'File 9 QC: Opioid Strength Parsing Status';
run;

proc print data=study.claims_with_opioid_strength(obs=100);
    where strength_parse_status in
        ('UNRESOLVED',
         'MISSING_OPIOID_INGREDIENT',
         'FENTANYL_STRENGTH_UNRESOLVED');

    var bene_id
        cde_ndc
        dte_first_svc
        nam_drug_generic
        dsc_strength
        opioid_ingred
        route_category
        strength_parse_status;

    title 'File 9 QC: Example Claims With Unresolved Opioid Strength';
run;


/*=============================================================================
  STEP 3: ATTACH CDC 2022 MME CONVERSION FACTORS

  File 8 is the authoritative lookup. The merge does not hard-code separate
  methadone factors.

  Fentanyl will receive the CDC factor from the lookup, but the factor is used
  only for eligible TRANSDERMAL fentanyl in Step 4.
=============================================================================*/

proc sql;
    create table study.claims_mme_factor_attached as
    select
        a.*,
        b.unit as mme_factor_unit length=10,
        b.mme_factor,
        b.source as mme_factor_source length=20
    from study.claims_with_opioid_strength as a
    left join study.opioid_mme_lookup_cdc2022 as b
        on upcase(strip(a.opioid_ingred)) =
           upcase(strip(b.ingredient));
quit;


/*=============================================================================
  STEP 4: CALCULATE CLAIM-LEVEL MME

  Ordinary CDC 2022 mg-based opioids:
      total_mme =
          quantity_dispensed * opioid_strength_mg * mme_factor

      mme_per_day =
          total_mme / days_supply

  Transdermal fentanyl:
      CDC 2022 factor = 2.4 per mcg/hour.
      MME/day is therefore:
          fentanyl_strength_mcg_hr * mme_factor

  The transdermal fentanyl calculation does NOT multiply by patch quantity,
  because the CDC factor is defined from the patch delivery rate in mcg/hour.

  Other fentanyl formulations remain without calculated MME in this program.
=============================================================================*/

data study.claims_with_mme;
    set study.claims_mme_factor_attached;

    length mme_calc_status $50;

    total_mme = .;
    mme_per_day = .;

    /*---------------------------------------------------------------
      A. TRANSDERMAL FENTANYL
    ---------------------------------------------------------------*/
    if upcase(strip(opioid_ingred)) = 'FENTANYL' then do;

        if upcase(strip(route_category)) = 'TRANSDERMAL' then do;

            if not missing(opioid_strength_mcg_hr)
               and not missing(mme_factor) then do;

                mme_per_day =
                    opioid_strength_mcg_hr * mme_factor;

                /* A claim-level total over the recorded days supply can be
                   derived from MME/day for downstream aggregation. */
                if days_supply > 0 then
                    total_mme = mme_per_day * days_supply;

                mme_calc_status = 'CALCULATED_FENTANYL_TRANSDERMAL';
            end;
            else if missing(opioid_strength_mcg_hr) then
                mme_calc_status = 'MISSING_FENTANYL_STRENGTH';
            else
                mme_calc_status = 'MISSING_CDC_FACTOR';
        end;
        else
            mme_calc_status = 'FENTANYL_NONTRANSDERMAL_NO_CDC_FACTOR';
    end;

    /*---------------------------------------------------------------
      B. OTHER CDC 2022 OPIOIDS
    ---------------------------------------------------------------*/
    else if not missing(mme_factor) then do;

        if not missing(opioid_strength_mg)
           and not missing(qnty_dispensed)
           and days_supply > 0 then do;

            total_mme =
                qnty_dispensed *
                opioid_strength_mg *
                mme_factor;

            mme_per_day =
                total_mme / days_supply;

            mme_calc_status = 'CALCULATED_CDC2022';
        end;
        else if missing(opioid_strength_mg) then
            mme_calc_status = 'MISSING_PARSED_STRENGTH';
        else if missing(qnty_dispensed) then
            mme_calc_status = 'MISSING_QUANTITY';
        else if missing(days_supply) or days_supply <= 0 then
            mme_calc_status = 'INVALID_DAYS_SUPPLY';
    end;

    /*---------------------------------------------------------------
      C. OPIOIDS WITHOUT A CDC 2022 MME FACTOR
    ---------------------------------------------------------------*/
    else do;

        if upcase(strip(opioid_ingred)) = 'BUPRENORPHINE' then
            mme_calc_status = 'BUPRENORPHINE_NOT_IN_TOTAL_MME';
        else
            mme_calc_status = 'NO_CDC2022_MME_FACTOR';
    end;

    label opioid_strength_mg =
              'Parsed opioid strength (mg)'
          opioid_strength_mcg_hr =
              'Parsed transdermal fentanyl strength (mcg/hr)'
          mme_factor =
              'CDC 2022 MME conversion factor'
          total_mme =
              'Total claim MME'
          mme_per_day =
              'MME per day'
          mme_calc_status =
              'MME calculation status';
run;


/*=============================================================================
  STEP 5: MME CALCULATION COVERAGE
=============================================================================*/

proc freq data=study.claims_with_mme order=freq;
    tables mme_calc_status / missing;
    title 'File 9 QC: Claim-Level MME Calculation Status';
run;

proc sql;
    title 'File 9 QC: Strength Parsing and MME Calculation Coverage';

    select
        count(*) as n_claims format=comma15.,
        sum(case
                when not missing(opioid_strength_mg)
                     or not missing(opioid_strength_mcg_hr)
                then 1 else 0
            end) as n_strength_parsed format=comma15.,
        sum(case
                when not missing(mme_per_day)
                then 1 else 0
            end) as n_mme_calculated format=comma15.,
        calculated n_strength_parsed /
            calculated n_claims format=percent8.1
            as pct_strength_parsed,
        calculated n_mme_calculated /
            calculated n_claims format=percent8.1
            as pct_mme_calculated
    from study.claims_with_mme;
quit;


/*=============================================================================
  STEP 6: REVIEW MME/DAY DISTRIBUTION FOR OUTLIERS
=============================================================================*/

proc means data=study.claims_with_mme
           n mean median min max p95 p99;
    where not missing(mme_per_day);
    var mme_per_day;
    title 'File 9 QC: MME per Day Distribution - Review for Outliers';
run;


/*=============================================================================
  STEP 7: MULTI-INGREDIENT PRODUCT VALIDATION

  Avoid a beneficiary-only many-to-many join. The validation is performed
  directly on the final claim-level dataset.
=============================================================================*/

data work.multi_ingredient_check;
    set study.claims_with_mme;

    if count(nam_drug_generic, '/') >= 2;

    keep bene_id
         cde_ndc
         dte_first_svc
         nam_drug_generic
         dsc_strength
         opioid_ingred
         opioid_strength_mg
         strength_parse_status
         mme_factor
         mme_per_day
         mme_calc_status;
run;

proc print data=work.multi_ingredient_check(obs=50);
    title 'File 9 QC: Multi-Ingredient Opioid Strength Parsing';
run;

proc sql;
    title 'File 9 QC: Multi-Ingredient Strength Parsing Coverage';

    select
        count(*) as n_multi_ingred_claims format=comma15.,
        sum(case
                when not missing(opioid_strength_mg)
                then 1 else 0
            end) as n_multi_ingred_parsed format=comma15.,
        calculated n_multi_ingred_parsed /
            calculated n_multi_ingred_claims format=percent8.1
            as pct_parsed
    from work.multi_ingredient_check;
quit;


/*=============================================================================
  STEP 8: IDENTIFY INGREDIENTS WITHOUT A CDC 2022 MME FACTOR
=============================================================================*/

proc freq data=study.claims_with_mme order=freq;
    where missing(mme_factor);
    tables opioid_ingred / missing;
    title 'File 9 QC: Opioid Ingredients Without a CDC 2022 MME Factor';
run;


/*=============================================================================
  STEP 9: FENTANYL-SPECIFIC QUALITY CONTROL
=============================================================================*/

proc freq data=study.claims_with_mme;
    where upcase(strip(opioid_ingred)) = 'FENTANYL';
    tables route_category*mme_calc_status / missing;
    title 'File 9 QC: Fentanyl Route and MME Calculation Status';
run;

proc print data=study.claims_with_mme(obs=100);
    where upcase(strip(opioid_ingred)) = 'FENTANYL'
          and missing(mme_per_day);

    var cde_ndc
        nam_drug_generic
        route_category
        days_supply
        dsc_strength
        opioid_strength_mcg_hr
        mme_factor
        mme_calc_status;

    title 'File 9 QC: Fentanyl Claims Without Calculated MME';
run;


/*=============================================================================
  STEP 10: METHADONE-SPECIFIC QUALITY CONTROL

  Methadone uses the CDC 2022 factor supplied by File 8. This section checks
  that no older dose-dependent factors have been introduced.
=============================================================================*/

proc freq data=study.claims_with_mme;
    where upcase(strip(opioid_ingred)) = 'METHADONE';
    tables mme_factor*mme_calc_status / missing;
    title 'File 9 QC: Methadone CDC 2022 MME Factor and Calculation Status';
run;

proc print data=study.claims_with_mme(obs=100);
    where upcase(strip(opioid_ingred)) = 'METHADONE'
          and missing(mme_per_day);

    var cde_ndc
        nam_drug_generic
        route_category
        days_supply
        qnty_dispensed
        dsc_strength
        opioid_strength_mg
        mme_factor
        mme_calc_status;

    title 'File 9 QC: Methadone Claims Without Calculated MME';
run;


/*=============================================================================
  STEP 11: FINAL OUTPUT CHECK
=============================================================================*/

proc contents data=study.claims_with_mme;
    title 'File 9 Final Output: STUDY.CLAIMS_WITH_MME';
run;

proc sql;
    title 'File 9 Final Output Counts';

    select
        count(*) as n_opioid_claims format=comma15.,
        count(distinct bene_id) as n_unique_beneficiaries format=comma15.,
        sum(case when not missing(mme_per_day)
                 then 1 else 0 end)
            as n_claims_with_mme format=comma15.
    from study.claims_with_mme;
quit;

title;


/*=============================================================================
  END OF FILE 9

  IMPORTANT NEXT STEP:
    Before constructing longitudinal MME outcomes, apply/confirm the grant's
    final study-specific opioid eligibility rules, including route/formulation
    restrictions and special handling of products used for opioid use disorder
    versus pain management. Claims with unresolved strength or unsupported
    CDC 2022 conversion factors should remain explicitly flagged rather than
    being assigned assumed values.
=============================================================================*/
