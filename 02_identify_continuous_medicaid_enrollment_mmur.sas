/**************************************************************************
Program:    01_identify_continuous_medicaid_enrollment_mmur.sas
Project:    Impact of Medical Marijuana Initiation on Opioid Dosing and Use
            Among Florida Medicaid Enrollees With Type 2 Diabetes
Purpose:    Identify MMUR-linked beneficiaries and evaluate Medicaid
            enrollment coverage during the 12 months before and 12 months
            after the first OMMU/MMUR certification reference date.

Input:      AHCA.AHCA_CE_EPISODES_NO_DUAL_45D
Output:     STUDY.ENROLLMENT2

Enrollment definition implemented here:
  - Target window: day -365 through day +365 relative to the first
    OMMU/MMUR certification reference date.
  - Enrollment episodes outside the target window are excluded.
  - Episodes overlapping the target window are truncated to its boundaries.
  - A beneficiary is classified as CONTINUOUS_24MON=1 when:
      1. coverage begins within 30 days of the baseline boundary;
      2. coverage extends to within 30 days of the follow-up boundary; and
      3. no gap between enrollment episodes exceeds 30 days.

Notes:
  - This operational definition permits enrollment gaps of up to 30 days.
  - DATE_REFERENCE, DTSTART, and DTEND are assumed to have already been
    constructed in the source enrollment-episode dataset.
  - BASELINE_START and FOLLOWUP_END are relative-day values, not SAS dates.
  - Local/network paths are intentionally represented as configurable
    placeholders for GitHub portability.
**************************************************************************/

/*=======================================================================
  1. USER-CONFIGURABLE PATHS
  Replace these placeholders with the appropriate local/network paths.
=======================================================================*/

%let STUDY_PATH = <PATH_TO_STUDY_OUTPUT_DIRECTORY>;
%let AHCA_PATH  = <PATH_TO_AHCA_DATA_DIRECTORY>;

libname study "&STUDY_PATH.";
libname ahca  "&AHCA_PATH.";


/*=======================================================================
  2. INSPECT REFERENCE-DATE TYPES
  Confirms the values present in DATE_REFERENCE before cohort selection.
=======================================================================*/

proc freq data=ahca.ahca_ce_episodes_no_dual_45d;
    tables date_reference / missing;
run;


/*=======================================================================
  3. SELECT MMUR/OMMU REFERENCE-DATE RECORDS
  This temporary dataset is useful for validation and inspection.
=======================================================================*/

data work.tmp_mmur;
    set ahca.ahca_ce_episodes_no_dual_45d;

    if date_reference = 'First Date of OMMU Certification';
run;


/*=======================================================================
  4. DEFINE THE TARGET 24-MONTH ENROLLMENT WINDOW
=======================================================================*/

data work.enrollment1;
    set ahca.ahca_ce_episodes_no_dual_45d;

    /* Retain beneficiaries indexed to first OMMU/MMUR certification. */
    if date_reference = 'First Date of OMMU Certification';

    /* Patient-specific boundaries relative to the reference/index date. */
    baseline_start = -365;
    followup_end   =  365;

    /* Remove enrollment episodes entirely outside the target window. */
    if dtend < baseline_start or dtstart > followup_end then delete;

    /* Clamp overlapping episodes to the target window boundaries. */
    if dtstart < baseline_start then dtstart = baseline_start;
    if dtend   > followup_end   then dtend   = followup_end;
run;


/*=======================================================================
  5. SORT ENROLLMENT EPISODES WITHIN BENEFICIARY
=======================================================================*/

proc sort data=work.enrollment1;
    by bene_id dtstart;
run;


/*=======================================================================
  6. EVALUATE COVERAGE GAPS AND CREATE CONTINUOUS-ENROLLMENT FLAG
=======================================================================*/

data study.enrollment2;
    set work.enrollment1;
    by bene_id dtstart;

    retain min_start max_end has_gap;

    /* Initialize tracking variables for each beneficiary. */
    if first.bene_id then do;
        min_start = dtstart;
        max_end   = dtend;
        has_gap   = 0;
    end;

    else do;
        /*
          Flag a gap when the next episode begins more than 30 days after
          the end of the currently accumulated coverage interval.
        */
        if dtstart > (max_end + 30) then has_gap = 1;

        /* Extend the accumulated coverage endpoint when appropriate. */
        if dtend > max_end then max_end = dtend;
    end;

    /*
      Output one record per beneficiary.

      CONTINUOUS_24MON=1 requires:
        - coverage beginning within 30 days of the baseline boundary;
        - coverage extending to within 30 days of the follow-up boundary;
        - no internal enrollment gap greater than 30 days.
    */
    if last.bene_id then do;

        if (min_start <= baseline_start + 30) and
           (max_end   >= followup_end - 30) and
           (has_gap = 0)
        then continuous_24mon = 1;
        else continuous_24mon = 0;

        output;
    end;

    keep bene_id
         baseline_start
         followup_end
         min_start
         max_end
         has_gap
         continuous_24mon;
run;


/*=======================================================================
  7. QUALITY-CONTROL CHECK
=======================================================================*/

title "Continuous Medicaid Enrollment Around First OMMU/MMUR Certification";

proc freq data=study.enrollment2;
    tables continuous_24mon / missing;
run;

title;
