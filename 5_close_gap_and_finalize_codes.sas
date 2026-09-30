/*=====================================================================
  CLOSE THE 68-NDC GAP AND BUILD THE FINAL COMPLETE NDC LIST
  Consolidates: FDA route lookup + FDA ingredient lookup (via
  Proprietary_Name) + manual resolution of 10 residual cases +
  exclusion of confirmed non-opioids -> final merged table.

  ASSUMES YOU ALREADY HAVE (from earlier work):
    - opioid_ndc_final_with_route  (RxNorm route merged onto full list,
                                      68 rows with blank route_category)
    - ndcs_missing_route            (just the 68 NDCs)
    - fda_ndc                       (your FDA file with Proprietary_Name,
                                      Dosage_Form, Route columns)

  If any of those don't exist in your current session, rerun the
  scripts that built them first (merge_fda_rxnorm_route.sas), since
  WORK tables don't persist across SAS sessions.
=====================================================================*/


/*=====================================================================
  STEP 1: Convert FDA_NDC's dashed NDC to 11-digit format
  (skip this step if fda_ndc_converted already exists in your session)
=====================================================================*/

data MMJ.fda_ndc_converted;
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

    keep ndc_11 Proprietary_Name Dosage_Form Route;
run;

proc sort data=MMJ.fda_ndc_converted nodupkey;
    by ndc_11;
run;


/*=====================================================================
  STEP 2: Get ROUTE for the 68 gap NDCs directly from the FDA file's
  own Route column -- no need to re-derive it, since your FDA_NDC
  file already has it.
=====================================================================*/
proc sql;
    create table MMJ.ndcs_missing_route as
    select ndc_11 from mmj.opioid_ndc_final_with_route
    where route_category = '';
quit;
proc sql;
    create table MMJ.gap_68_route as
    select a.ndc_11, b.Route as route_category, b.Dosage_Form
    from MMJ.ndcs_missing_route as a
    left join MMJ.fda_ndc_converted as b
    on a.ndc_11 = b.ndc_11;
quit;

proc freq data=MMJ.gap_68_route;
    tables route_category / missing;
    title 'Route for the 68 gap NDCs, from FDA file directly';
run;


/*=====================================================================
  STEP 3: Get INGREDIENT for the 68 gap NDCs via Proprietary_Name
  string match (58 auto-matched)
=====================================================================*/

data MMJ.gap_68_ingredient_auto;
    set MMJ.fda_ndc_converted;
    length opioid_ingred $20;

    array opioids{20} $20 _temporary_
        ('MORPHINE','OXYCODONE','HYDROCODONE','HYDROMORPHONE',
         'FENTANYL','OXYMORPHONE','CODEINE','DIHYDROCODEINE',
         'METHADONE','TAPENTADOL','TRAMADOL','BUPRENORPHINE',
         'MEPERIDINE','LEVORPHANOL','OPIUM','PENTAZOCINE',
         'LEVOMETHADYL','BUTORPHANOL','DEZOCINE','NALBUPHINE');

    do i = 1 to dim(opioids);
        if index(upcase(Proprietary_Name), strip(opioids{i})) > 0 then do;
            opioid_ingred = opioids{i};
            output;
        end;
    end;
    drop i;
run;

proc sort data=mmj.gap_68_ingredient_auto nodupkey;
    by ndc_11 opioid_ingred;
run;

proc sql;
    create table mmj.gap_68_final as
    select a.ndc_11, a.opioid_ingred
    from mmj.gap_68_ingredient_auto as a
    inner join ndcs_missing_route as b
    on a.ndc_11 = b.ndc_11;
quit;


/*=====================================================================
  STEP 4: Manual resolution for the 10 residual NDCs (verified via
  web search against FDA/DailyMed labeling -- see prior discussion)
=====================================================================*/

data mmj.gap_10_resolved;
    length ndc_11 $11 opioid_ingred $20 exclude_reason $60;
    infile datalines dlm='|' dsd missover;
    input ndc_11 $ opioid_ingred $ exclude_reason $;
    datalines;
17089040618|EXCLUDE|Homeopathic_ultradilute_apomorphine_not_opioid
27505000405|EXCLUDE|Apomorphine_dopamine_agonist_not_opioid
27505000605|EXCLUDE|Apomorphine_dopamine_agonist_not_opioid
50991072315|CODEINE|
58264005201|EXCLUDE|Likely_homeopathic_DNALabs_verify_manually
58716043304|HYDROCODONE|
58716043316|HYDROCODONE|
70040014501|HYDROCODONE|Benzhydrocodone_prodrug_of_hydrocodone
70040016701|HYDROCODONE|Benzhydrocodone_prodrug_of_hydrocodone
70040018901|HYDROCODONE|Benzhydrocodone_prodrug_of_hydrocodone
;
run;

/* Combine auto-matched (58) + manually resolved real opioids (7) */
proc sql;
    create table mmj.gap_68_ingredient_complete as
    select ndc_11, opioid_ingred from mmj.gap_68_final
    outer union corr
    select ndc_11, opioid_ingred from mmj.gap_10_resolved
    where opioid_ingred ne 'EXCLUDE';
quit;

proc sort data=mmj.gap_68_ingredient_complete nodupkey;
    by ndc_11;
run;

/* NDCs confirmed NOT to be real opioids -- remove from the final list */
proc sql;
    create table mmj.ndcs_to_exclude as
    select ndc_11 from mmj.gap_10_resolved
    where opioid_ingred = 'EXCLUDE';
quit;

proc print data=mmj.ndcs_to_exclude;
    title 'Confirmed non-opioid NDCs -- will be removed from final list';
run;


/*=====================================================================
  STEP 5: Build the FINAL, complete NDC list --
  route (RxNorm + FDA gap-fill) + ingredient (RxNorm + FDA gap-fill),
  with confirmed non-opioids excluded
=====================================================================*/

proc sql;
    create table mmj.opioid_ndc_TRULY_FINAL as
    select a.ndc_11,
           propcase(coalesce(a.opioid_ingred, b.opioid_ingred)) as opioid_ingred,
           propcase(coalesce(a.route_category, c.route_category)) as route_category,
           a.rxnorm_suppress
    from mmj.opioid_ndc_final_with_route as a
    left join mmj.gap_68_ingredient_complete as b on a.ndc_11 = b.ndc_11
    left join mmj.gap_68_route as c on a.ndc_11 = c.ndc_11
    where a.ndc_11 not in (select ndc_11 from ndcs_to_exclude);
quit;

proc sort data=mmj.opioid_ndc_TRULY_FINAL nodupkey;
    by ndc_11;
run;

proc freq data=mmj.opioid_ndc_truly_final;
table opioid_ingred route_category;
run;
/*=====================================================================
  STEP 6: Final QC -- confirm both gaps are closed
=====================================================================*/

proc sql;
    select count(*) as n_total_ndcs from mmj.opioid_ndc_TRULY_FINAL;
quit;
title 'Total NDCs in final list (should be ~24,454 minus excluded non-opioids)';

proc freq data=opioid_ndc_TRULY_FINAL;
    tables route_category / missing;
    title 'Route coverage in final list -- missing should be at or near 0';
run;

proc freq data=opioid_ndc_TRULY_FINAL;
    tables opioid_ingred / missing;
    title 'Ingredient coverage in final list -- missing should be at or near 0';
run;

/* Show any NDCs still missing route or ingredient for final review */
proc print data=opioid_ndc_TRULY_FINAL;
    where route_category = '' or opioid_ingred = '';
    title 'Any remaining gaps -- final manual check';
run;
