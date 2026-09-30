/*=============================================================================
  CDC 2022 OPIOID MME CONVERSION FACTOR REFERENCE TABLE

  Project:
    Impact of Medical Marijuana Initiation on Opioid Dosing and Use
    Among Florida Medicaid Enrollees With Type 2 Diabetes

  Purpose:
    Create the authoritative morphine milligram equivalent (MME) conversion
    factor lookup table used for subsequent claim-level MME calculations.

  Primary source:
    CDC Clinical Practice Guideline for Prescribing Opioids for Pain —
    United States, 2022. MMWR Recomm Rep. 2022;71(3):1-95.

    CDC table:
    "Morphine milligram equivalent doses for commonly prescribed opioids
     for pain management"

  IMPORTANT:
    - This lookup contains ONLY conversion factors reported in the CDC 2022
      MME table.
    - The CDC 2022 table uses a single methadone conversion factor of 4.7.
      The older 2016 dose-dependent methadone factors (4/8/10/12) are NOT
      used in this lookup.
    - Fentanyl 2.4 applies ONLY to TRANSDERMAL fentanyl measured in mcg/hr.
      Fentanyl must therefore be handled using route/formulation-specific
      logic before applying this factor.
    - Buprenorphine products approved for pain are not included in the CDC
      2022 MME table. CDC also advises not to include buprenorphine in total
      MME/day calculations.
    - Opioids present in the Medicaid claims but absent from the CDC 2022
      table should NOT be assigned an unsupported CDC factor. They should be
      identified separately for prespecified supplemental handling/sensitivity
      analysis if needed.

  Output:
    STUDY.OPIOID_MME_LOOKUP_CDC2022
=============================================================================*/


/*-----------------------------------------------------------------------------
  STEP 1: Create CDC 2022 MME conversion-factor lookup

  UNIT:
    mg     = opioid dose expressed in milligrams
    mcg/hr = transdermal fentanyl dose expressed in micrograms per hour
-----------------------------------------------------------------------------*/

data study.opioid_mme_lookup_cdc2022;
    length ingredient $30
           unit       $10
           source     $20
           special_handling $100;

    input ingredient :$30. unit :$10. mme_factor;

    source = 'CDC 2022';
    opioid_flag = 1;

    if ingredient = 'FENTANYL' then
        special_handling =
            'Factor applies only to transdermal fentanyl in mcg/hr';
    else if ingredient = 'METHADONE' then
        special_handling =
            'CDC 2022 single factor; use caution with methadone conversion';
    else
        special_handling = '';

    datalines;
CODEINE mg 0.15
FENTANYL mcg/hr 2.4
HYDROCODONE mg 1.0
HYDROMORPHONE mg 5.0
METHADONE mg 4.7
MORPHINE mg 1.0
OXYCODONE mg 1.5
OXYMORPHONE mg 3.0
TAPENTADOL mg 0.4
TRAMADOL mg 0.2
;
run;


/*-----------------------------------------------------------------------------
  STEP 2: Print lookup table for verification
-----------------------------------------------------------------------------*/

proc print data=study.opioid_mme_lookup_cdc2022 noobs label;
    var ingredient unit mme_factor source special_handling;

    label ingredient       = 'Opioid Ingredient'
          unit             = 'Dose Unit'
          mme_factor       = 'CDC 2022 MME Conversion Factor'
          source           = 'Source'
          special_handling = 'Special Handling';

    title 'CDC 2022 Opioid MME Conversion Factor Lookup';
run;


/*-----------------------------------------------------------------------------
  STEP 3: QC checks
-----------------------------------------------------------------------------*/

/* Confirm that the lookup contains the expected 10 CDC 2022 entries. */
proc sql;
    title 'QC: Number of CDC 2022 MME Lookup Entries';
    select count(*) as n_lookup_entries
    from study.opioid_mme_lookup_cdc2022;
quit;


/* Confirm ingredient uniqueness. */
proc sql;
    title 'QC: Duplicate Ingredients in CDC 2022 MME Lookup';
    select ingredient,
           count(*) as n_records
    from study.opioid_mme_lookup_cdc2022
    group by ingredient
    having calculated n_records > 1;
quit;


/* Confirm no conversion factors are missing. */
proc sql;
    title 'QC: Missing CDC 2022 MME Conversion Factors';
    select *
    from study.opioid_mme_lookup_cdc2022
    where missing(mme_factor);
quit;


/*-----------------------------------------------------------------------------
  STEP 4: Document opioids intentionally NOT assigned a CDC 2022 MME factor

  These ingredients appeared in the broader opioid-identification work but
  are not assigned a factor here because the CDC 2022 MME table does not
  provide one. This table is documentation only; it is NOT an MME lookup.
-----------------------------------------------------------------------------*/

data study.opioids_without_cdc2022_mme;
    length ingredient $30 reason $150;

    input ingredient :$30.;

    reason =
        'No conversion factor assigned from the CDC 2022 MME table';

    datalines;
BUPRENORPHINE
BUTORPHANOL
DEZOCINE
DIHYDROCODEINE
LEVORPHANOL
MEPERIDINE
NALBUPHINE
OPIUM
PENTAZOCINE
;
run;

proc print data=study.opioids_without_cdc2022_mme noobs label;
    label ingredient = 'Opioid Ingredient'
          reason     = 'Reason';

    title 'Opioid Ingredients Without a CDC 2022 MME Conversion Factor';
run;


/*-----------------------------------------------------------------------------
  END OF PROGRAM

  Next step:
    Apply study-specific route/formulation eligibility rules before merging
    MME factors onto Medicaid opioid claims. This is particularly important
    for fentanyl, buprenorphine, methadone, and products used primarily for
    opioid use disorder rather than pain management.
-----------------------------------------------------------------------------*/

title;
