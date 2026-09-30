/*=============================================================================
  OPIOID CLAIMS DRUG-NAME AND STRENGTH PROFILE
  Florida Medicaid Pharmacy Claims

  Purpose:
    Examine the actual generic drug-name and strength formats among opioid
    pharmacy claims before developing parsing and MME calculation logic.

  Input:
    STUDY.CLAIMS_OPIOID_MERGED

  Temporary outputs:
    WORK.DRUGNAME_SLASH_CHECK
    WORK.MULTI_INGREDIENT_PRODUCTS
    WORK.ZERO_SLASH_CHECK
=============================================================================*/


/*-----------------------------------------------------------------------------
  STEP 1: Check actual, complete distribution of opioid drug names
-----------------------------------------------------------------------------*/

proc freq data=study.claims_opioid_merged order=freq;
    tables nam_drug_generic / missing;
    title 'All distinct drug names in claims data by frequency';
run;


/*-----------------------------------------------------------------------------
  STEP 2: Count "/" separators in generic drug names
-----------------------------------------------------------------------------*/

data drugname_slash_check;
    set study.claims_opioid_merged;
    n_slashes = count(nam_drug_generic, '/');
run;

proc freq data=drugname_slash_check;
    tables n_slashes / missing;
    title 'Number of "/" separators per drug name -- 2+ mean 3+ ingredients';
run;


/*-----------------------------------------------------------------------------
  STEP 3: Check products with 3 or more ingredients
-----------------------------------------------------------------------------*/

proc sql;
    create table multi_ingredient_products as
    select distinct
        nam_drug_generic,
        dsc_strength
    from drugname_slash_check
    where n_slashes >= 2;
quit;

proc print data=multi_ingredient_products;
    title 'Distinct 3+ ingredient drug names - these need extended logic';
run;


/*-----------------------------------------------------------------------------
  STEP 4: Check drug names with no slash but a slash-separated strength
-----------------------------------------------------------------------------*/

proc sql;
    create table zero_slash_check as
    select distinct
        nam_drug_generic,
        dsc_strength
    from drugname_slash_check
    where n_slashes = 0
      and index(dsc_strength, '/') > 0;
quit;

proc print data=zero_slash_check (obs=20);
    title 'Drug names with NO slash but a dash-separated strength';
run;


/*-----------------------------------------------------------------------------
  STEP 5: Check strength-field formats
-----------------------------------------------------------------------------*/

proc freq data=study.claims_opioid_merged order=freq;
    tables dsc_strength / missing;
    title 'All distinct strength value formats - confirm mg/dash pattern holds';
run;

title;
