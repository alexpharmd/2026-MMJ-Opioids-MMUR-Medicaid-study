/*=====================================================================
  Get the REAL, complete list of dose form terms present in your
  opioid NDC data, instead of relying on a guessed array.
=====================================================================*/

/* Option 1: RxNorm has a standalone Dose Form (DF) term type --
   this is the authoritative, complete list of dose form names RxNorm
   actually uses, independent of any specific drug */
proc sql;
    create table all_rxnorm_dose_forms as
    select distinct str as dose_form_name
    from rxnorm_names_all
    where tty = 'DF'
    order by dose_form_name;
quit;

proc print data=all_rxnorm_dose_forms;
    title 'Complete list of RxNorm Dose Form (DF) terms -- the real universe of possible values';
run;

/* We choose Option 2: even more directly useful -- extract whatever text
   appears AFTER the last strength/unit in each of YOUR actual opioid
   NDC strings. This shows exactly what dose form phrases occur in
   your real opioid product set, not a hypothetical universe. */
data mmj.dose_form_actual_extract;
    set mmj.opioid_ndcs_rxnorm;

    str_no_brand = prxchange('s/\[.*\]//', -1, str);

    /* Find the last occurrence of a unit (MG, MCG, MG/ML, MCG/ACTUAT,
       etc.) and take everything after it as the dose form phrase.
       MCG/ACTUAT added -- confirmed needed for spray/mucosal products
       via the earlier extraction artifact ("/ACTUAT Mucosal Spray"). */
    re = prxparse('/.*(MCG\/ACTUAT|MG\/ACTUAT|MG\/ML|MCG\/HR|MG\/HR|MG|MCG)\s*(.*)$/i');
    call prxsubstr(re, str_no_brand, position, length);
    if position > 0 then
        dose_form_extracted = strip(prxposn(re, 2, str_no_brand));

    drop re position length;
run;

proc freq data=mmj.dose_form_actual_extract order=freq;
    tables dose_form_extracted / missing;
    title 'Actual dose form phrases found in your opioid NDC data, by frequency';
run;
