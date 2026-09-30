/*=====================================================================
  FINAL ROUTE CLASSIFICATION -- built from the confirmed, complete
  list of 22 dose forms actually present in the opioid NDC data
  (verified via proc freq + manual review, not a guessed array).
=====================================================================*/

/*=====================================================================
  FINAL ROUTE CLASSIFICATION -- applies the ground-truth route mapping
  directly to dose_form_actual_extract (built in real_dose_form_list.sas,
  Option 2), which already contains dose_form_extracted for every NDC.
  No need to re-run the extraction logic a second time.
=====================================================================*/

data mmj.opioid_ndc_dosage_form_FINAL;
    set mmj.dose_form_actual_extract;
    length route_category $20;

    select (dose_form_extracted);
        when ('Oral Tablet','Extended Release Oral Tablet','Oral Capsule',
              'Extended Release Oral Capsule','Oral Solution',
              'Oral Suspension','Extended Release Suspension',
              'Tablet for Oral Suspension','Disintegrating Oral Tablet',
              'Oral Lozenge')
            route_category = 'Oral';
        when ('Transdermal System')
            route_category = 'Transdermal';
        when ('Sublingual Tablet','Sublingual Film','Buccal Film',
              'Buccal Tablet','Mucosal Spray')
            route_category = 'Buccal/Sublingual';
        when ('Injection','Injectable Solution','Prefilled Syringe',
              'Cartridge','Auto-Injector')
            route_category = 'Injectable';
        when ('Rectal Suppository')
            route_category = 'Rectal';
        when ('Metered Dose Nasal Spray')
            route_category = 'Nasal';
        when ('Drug Implant')
            route_category = 'Implant';
        when ('Topical Solution')
            route_category = 'Topical';
        otherwise route_category = 'Unclassified';
    end;
run;

proc freq data=mmj.opioid_ndc_dosage_form_FINAL;
    tables route_category / missing;
    title 'Final route classification -- ground-truth based';
run;

proc print data=mmj.opioid_ndc_dosage_form_FINAL;
    where route_category = 'Unclassified';
    var ndc_11 opioid_ingred str dose_form_extracted;
    title 'Any remaining unclassified -- should be empty';
run;
