/*=====================================================================
  OPIOID NDC IDENTIFICATION -- CONSOLIDATED MASTER SCRIPT
  Medicaid Pharmacy Claims, 2017-2024

  This is the single authoritative version of the pipeline, combining
  every fix validated over the course of development:
    - Corrected RXNCONSO/RXNSAT field layouts
    - 3-way NDC recovery logic (valid / pad-10-digit / strip-leading-
      zero-12-digit), validated against real data (99.75% recovery)
    - RXNREL two-hop ingredient bridge: IN --has_ingredient--> SCDC/
      TMSY --consists_of--> SCD/SBD/BPCK/GPCK (confirmed empirically;
      a direct one-hop IN->SCD/SBD link does not exist in this data)
    - FDA opioid NDC list cross-check (3-segment -> 11-digit conversion)
    - Reconciliation between RxNorm-based and FDA-based lists
    - Final combined NDC list (union of both sources)
    - Claims merge with suppress-status / match-source QC by year

  UPDATE THE THREE INFILE PATHS BELOW (RXNCONSO, RXNSAT, RXNREL)
  AND THE FDA IMPORT STEP BEFORE RUNNING.

  Run this entire script top-to-bottom in a single session. Do not
  run pieces in isolation across separate sessions -- WORK tables do
  not persist between sessions, and several tables in later steps
  depend on tables built in earlier steps.
=====================================================================*/


/*=====================================================================
  STEP 1: Import RXNCONSO.RRF -- all RxNorm-sourced concept names
  (unfiltered by TTY so it can be reused for both the opioid ingredient
  match AND the SCDC/TMSY intermediate lookups in Step 3)
=====================================================================*/

data MMJ.rxnorm_names_all;
    attrib rxcui length=$8
           sab   length=$20
           tty   length=$20
           str   length=$3000;

    infile "D:\Perez_MMJ\rrf\RXNCONSO.RRF" dlm='|' missover dsd lrecl=32767;

    input rxcui $ lat $ ts $ lui $ stt $ sui $ ispref $ rxaui $ saui $
          sdui $ scui $ sab $ tty $ code $ str $ srl $ suppress $ cvf $;

    if sab = 'RXNORM';

    keep rxcui str tty;
run;


/*=====================================================================
  STEP 2: Import RXNSAT.RRF -- NDC attributes with 3-way recovery logic
  Keeps active + historical/obsolete NDCs. Does not restrict to
  SAB='RXNORM' since some historical NDCs live only under legacy
  source vocabularies.
=====================================================================*/

data MMJ.rxnorm_all_ndcs;
    attrib rxcui    length=$8
           atn      length=$20
           sab      length=$20
           atv      length=$20
           suppress length=$1
           ndc_11   length=$11;

    infile "D:\Perez_MMJ\rrf\RXNSAT.RRF" dlm='|' missover dsd lrecl=32767;

    input rxcui $ lui $ sui $ rxaui $ stype $ code $ atui $ satui $
          atn $ sab $ atv $ suppress $ cvf $ garbage $;

    if atn = 'NDC';

    /* 3-way NDC recovery, validated: 63.45% valid as-is, 19.98%
       recoverable via zero-pad (10 digits/3 segments), 16.31%
       recoverable via leading-zero strip (12 digits, VANDF-sourced).
       Residual ~0.25% confirmed non-NDC (VANDF internal identifiers
       containing letters or "999" placeholder prefixes) -- dropped. */
    ndc_digits_only = compress(atv, , 'kd');
    n_segments = count(atv, '-') + 1;
    n_digits   = lengthn(ndc_digits_only);

    if n_digits = 11 then
        ndc_11 = ndc_digits_only;
    else if n_digits = 12 and n_segments = 1
            and substr(ndc_digits_only,1,1) = '0' then
        ndc_11 = substr(ndc_digits_only, 2, 11);
    else if n_digits = 10 and n_segments = 3 then do;
        labeler = scan(atv, 1, '-');
        product = scan(atv, 2, '-');
        package = scan(atv, 3, '-');
        ndc_11 = cats(put(input(labeler,8.),z5.),
                       put(input(product,8.),z4.),
                       put(input(package,8.),z2.));
    end;
    else ndc_11 = '';

    if ndc_11 = '' or lengthn(ndc_11) ne 11 then delete;

    keep rxcui ndc_11 sab suppress;
run;

proc sort data=MMJ.rxnorm_all_ndcs nodupkey;
    by rxcui ndc_11 sab;
run;

proc freq data=MMJ.rxnorm_all_ndcs;
    tables suppress;
    title 'RXNSAT NDC rows by suppress status (N=active, O=obsolete, Y=suppressed)';
run;


/*=====================================================================
  STEP 3: Opioid ingredient identification via RXNREL two-hop bridge
  Confirmed chain: IN --has_ingredient--> SCDC/TMSY --consists_of--> SCD/SBD
=====================================================================*/

/* 3a: Import RXNREL.RRF (unfiltered -- needed for both relationship types) */
data Mmj.rxnrel_check;
    attrib rxcui1 length=$8
           rxcui2 length=$8
           rela   length=$30
           sab    length=$20;
    infile "D:\Perez_MMJ\rrf\RXNREL.RRF" dlm='|' missover dsd lrecl=32767;
    input rxcui1 $ rxaui1 $ stype1 $ rel $ rxcui2 $ rxaui2 $ stype2 $
          rela $ rui $ srui $ sab $ sl $ rg $ dir $ suppress $ cvf $;
run;

/* 3b: has_ingredient hop -- IN (rxcui1) to SCDC/TMSY (rxcui2) */
data mmj.rxnrel_has_ingredient;
    set rxnrel_check;
    if rela = 'has_ingredient' and sab = 'RXNORM';
    keep rxcui1 rxcui2;
    rename rxcui1 = ing_rxcui
           rxcui2 = comp_rxcui;
run;

proc sort data=MMJ.rxnrel_has_ingredient nodupkey;
    by ing_rxcui comp_rxcui;
run;

/* 3c: consists_of hop -- SCDC/TMSY (rxcui1) to SCD/SBD (rxcui2) */
data MMJ.rxnrel_consists_of;
    set rxnrel_check;
    if rela = 'consists_of' and sab = 'RXNORM';
    keep rxcui1 rxcui2;
    rename rxcui1 = comp_rxcui
           rxcui2 = drug_rxcui;
run;

proc sort data=MMJ.rxnrel_consists_of nodupkey;
    by comp_rxcui drug_rxcui;
run;

/* 3d: seed opioid ingredient list (CDC 2022 MME table ingredients) */
data MMJ.opioid_ingredient_seed;
    length ingredient_name $20;
    input ingredient_name $;
    datalines;
MORPHINE
OXYCODONE
HYDROCODONE
HYDROMORPHONE
FENTANYL
OXYMORPHONE
CODEINE
DIHYDROCODEINE
METHADONE
TAPENTADOL
TRAMADOL
BUPRENORPHINE
MEPERIDINE
LEVORPHANOL
OPIUM
PENTAZOCINE
LEVOMETHADYL ACETATE
BUTORPHANOL
DEZOCINE
NALBUPHINE
;
run;

proc sql;
    create table MMJ.opioid_ingredient_rxcuis as
    select distinct a.rxcui, a.str as ingredient_str
    from MMJ.rxnorm_names_all as a
    inner join MMJ.opioid_ingredient_seed as b
    on upcase(a.str) = upcase(b.ingredient_name)
    where a.tty = 'IN';
quit;

/* QA: confirm every seed ingredient matched -- investigate any that
   show matched=0 before trusting downstream results */
proc sql;
    create table MMJ.seed_match_check as
    select b.ingredient_name,
           case when a.rxcui is not missing then 1 else 0 end as matched
    from MMJ.opioid_ingredient_seed as b
    left join MMJ.opioid_ingredient_rxcuis as a
    on upcase(a.ingredient_str) = upcase(b.ingredient_name);
quit;

proc print data=seed_match_check;
    where matched = 0;
    title 'Seed ingredients with NO RxNorm match -- investigate before proceeding';
run;

/* 3e: chain both hops together, filter to final dispensable term types */
proc sql;
    create table MMJ.opioid_flag as
    select distinct
           h.drug_rxcui as rxcui,
           s.ingredient_str as opioid_ingred,
           n.str,
           n.tty
    from (
        select hi.ing_rxcui, co.drug_rxcui
        from MMJ.rxnrel_has_ingredient as hi
        inner join MMJ.rxnrel_consists_of as co
        on hi.comp_rxcui = co.comp_rxcui
    ) as h
    inner join MMJ.opioid_ingredient_rxcuis as s
        on h.ing_rxcui = s.rxcui
    inner MMJ.join rxnorm_names_all as n
        on h.drug_rxcui = n.rxcui
    where n.tty in ('SCD','SBD','BPCK','GPCK');
quit;

proc sort data=MMJ.opioid_flag nodupkey;
    by rxcui opioid_ingred;
run;

proc freq data=MMJ.opioid_flag;
    tables opioid_ingred / missing;
    title 'Opioid concepts by ingredient (RXNREL two-hop method)';
run;


/*=====================================================================
  STEP 4: RxNorm-based opioid NDC list
=====================================================================*/

proc sql;
    create table MMJ.opioid_ndcs_rxnorm as
    select distinct
           b.ndc_11,
           b.rxcui,
           b.sab   as ndc_source_sab,
           b.suppress,
           a.str,
           a.tty,
           a.opioid_ingred
    from MMJ.opioid_flag as a
    inner join MMJ.rxnorm_all_ndcs as b
    on a.rxcui = b.rxcui;
quit;

proc sort data=MMJ.opioid_ndcs_rxnorm nodupkey;
    by ndc_11;
run;

proc freq data=MMJ.opioid_ndcs_rxnorm;
    tables opioid_ingred / missing;
    title 'RxNorm-based opioid NDC counts by ingredient';
run;


/*=====================================================================
  STEP 5: FDA opioid NDC list -- import & convert to 11-digit format
  Replace the datalines block with your actual FDA file import.
=====================================================================*/

/*Import FDA NDC list for opioid*/ 


data MMJ.opioid_ndcs11_fda;
    set MMJ.fda_ndc;
    length labeler $5 product $4 package $2 ndc_11 $11;

    labeler_raw = scan(ndc, 1, '-');
    product_raw = scan(ndc, 2, '-');
    package_raw = scan(ndc, 3, '-');

    if labeler_raw = '' or product_raw = '' or package_raw = '' then delete;

    labeler = put(input(labeler_raw, 8.), z5.);
    product = put(input(product_raw, 8.), z4.);
    package = put(input(package_raw, 8.), z2.);

    ndc_11 = cats(labeler, product, package);

    keep ndc ndc_11;
run;

proc sort data=MMJ.opioid_ndcs11_fda nodupkey;
    by ndc_11;
run;


/*=====================================================================
  STEP 6: Reconcile RxNorm list vs FDA list
=====================================================================*/

proc sql;
    create table MMJ.opioid_ndc_reconciliation as
    select
        coalesce(a.ndc_11, b.ndc_11) as ndc_11,
        (a.ndc_11 is not missing) as in_rxnorm,
        (b.ndc_11 is not missing) as in_fda,
        a.opioid_ingred,
        a.suppress as rxnorm_suppress,
        b.ndc
    from MMJ.opioid_ndcs_rxnorm as a
    full join MMJ.opioid_ndcS11_fda as b
    on a.ndc_11 = b.ndc_11;
quit;

proc freq data=opioid_ndc_reconciliation;
    tables in_rxnorm*in_fda / missing;
    title 'NDC overlap between RxNorm-based and FDA-based opioid lists';
run;


/*=====================================================================
  STEP 7: Final combined opioid NDC list
=====================================================================*/

data MMJ.opioid_ndc_final;
    set MMJ.opioid_ndcs_rxnorm (keep=ndc_11 opioid_ingred suppress
                             rename=(suppress=rxnorm_suppress))
        MMJ.opioid_ndcS11_fda (keep=ndc_11);
run;

proc sort data=MMJ.opioid_ndc_final nodupkey;
    by ndc_11;
run;

proc sql noprint;
    select count(*) into :n_final trimmed from opioid_ndc_final;
quit;
%put NOTE: Final combined opioid NDC list contains &n_final unique NDCs.;


/*=====================================================================
  STEP 8: Merge with Medicaid pharmacy claims + QC by year
  UPDATE: pharmacy_claims / ndc / claim_date to match your actual data
=====================================================================*/

proc sql;
    create table claims_opioid_flagged as
    select a.*,
           case when b.ndc_11 is not missing then 1 else 0 end as opioid_flag,
           b.opioid_ingred,
           b.rxnorm_suppress
    from pharmacy_claims as a
    left join opioid_ndc_final as b
    on a.ndc = b.ndc_11;
quit;

data claims_opioid_flagged;
    set claims_opioid_flagged;
    claim_year = year(claim_date);

    length match_source $20;
    if opioid_flag = 0 then match_source = 'Not opioid';
    else if rxnorm_suppress = 'N' then match_source = 'RxNorm - active';
    else if rxnorm_suppress = 'O' then match_source = 'RxNorm - obsolete (src)';
    else if rxnorm_suppress = 'Y' then match_source = 'RxNorm - suppressed (edtr)';
    else if opioid_flag = 1 and rxnorm_suppress = '' then match_source = 'FDA list only';
run;

proc freq data=claims_opioid_flagged;
    tables claim_year*opioid_flag / nocol nopercent;
    title 'Opioid claim match rate by year';
run;

proc freq data=claims_opioid_flagged;
    where opioid_flag = 1;
    tables claim_year*match_source / nopercent norow;
    title 'Opioid-matched claims by year and NDC match source/suppress status';
run;

proc sql;
    create table suppress_by_year as
    select claim_year, match_source, count(*) as n_claims
    from claims_opioid_flagged
    where opioid_flag = 1
    group by claim_year, match_source;
quit;

proc sql;
    select
        claim_year,
        sum(case when match_source = 'RxNorm - active' then n_claims else 0 end) as active_n,
        sum(case when match_source in ('RxNorm - obsolete (src)','RxNorm - suppressed (edtr)')
                 then n_claims else 0 end) as obsolete_suppressed_n,
        sum(case when match_source = 'FDA list only' then n_claims else 0 end) as fda_only_n,
        sum(n_claims) as total_opioid_claims,
        calculated obsolete_suppressed_n / calculated total_opioid_claims
            as pct_obsolete_suppressed format=percent8.1
    from suppress_by_year
    group by claim_year
    order by claim_year;
    title 'Share of opioid claims matched via obsolete/suppressed NDCs, by year';
quit;

proc sql;
    select
        claim_year,
        count(*) as total_claims,
        sum(opioid_flag) as opioid_claims,
        calculated opioid_claims / calculated total_claims as opioid_pct format=percent8.2
    from claims_opioid_flagged
    group by claim_year
    order by claim_year;
    title 'Overall opioid claim rate by year';
quit;
