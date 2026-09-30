/*=====================================================================
  Merge route_category (RxNorm-derived) onto the complete combined
  NDC list (RxNorm + FDA-only NDCs).

  opioid_ndc_final       = complete list, RxNorm + FDA-only NDCs (~24,691)
  opioid_ndc_dosage_form_FINAL = route_category, RxNorm-sourced only (24,386)

  Left join keeps every NDC in opioid_ndc_final. The ~237 FDA-only
  NDCs will come through with route_category missing -- this is
  expected and transparent, not an error.
=====================================================================*/

proc sql;
    create table mmj.opioid_ndc_final_with_route as
    select a.*,
           b.dose_form_raw,
           b.route_category
    from mmj.opioid_ndc_final as a
    left join mmj.opioid_ndc_dosage_form_FINAL
        (keep=ndc_11 dose_form_raw route_category) as b
    on a.ndc_11 = b.ndc_11;
quit;

/* Confirm row count matches opioid_ndc_final exactly -- the merge
   should not add or drop any rows, only attach route where available */
proc sql;
    select count(*) as n_final_with_route from opioid_ndc_final_with_route;
    select count(*) as n_final_original from mmj.opioid_ndc_final;
quit;
title 'Row counts should match -- confirms the left join did not drop/duplicate NDCs';

/* Check how much route coverage gap actually exists */
proc freq data=mmj.opioid_ndc_final_with_route;
    tables route_category / missing;
    title 'Route category coverage across the FULL combined NDC list';
run;

/* Identify exactly which NDCs are missing route -- should be the
   FDA-only ones */
proc sql;
    create table ndcs_missing_route as
    select ndc_11 from opioid_ndc_final_with_route
    where route_category = '';
quit;

proc sql;
    select count(*) as n_missing_route from ndcs_missing_route;
quit;
title 'NDCs with no route category -- expected to be ~237 FDA-only NDCs';
