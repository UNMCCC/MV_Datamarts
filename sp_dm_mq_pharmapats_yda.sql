DROP PROCEDURE IF EXISTS sp_DM_MQ_PharmaPats_YDA;
CREATE PROCEDURE `sp_DM_MQ_PharmaPats_YDA`()
BEGIN

/********************************************************************************************************************************************\
  --  Name:         sp_DM_MQ_PharmaPats_Yesterday
  --  Depends on:   dm_study, dm_study_current, dm_patient, dm_calendar, mq_appointments, mq_chemos, mq_labs, labs_cpts
  --  Calls:
  --  Description:  Combine data from Mosaiq (MQ) with patients enrolled on Industrial (a.k.a. Pharma) trials 
                    If available included the calendar(schedule) name for billing/finance purposes
                    Insert prior data into history table and replace with new data
  --  Uses:         A patient enrolled on study will have a calendar setup with multiple events planned to be marked Done over time
  --  Method:       Create temp table of patients enrolled on industrial trials (studies)
                    Create temp table of calendar name (no events, coverage, ect.)
                    Create temp table of lab CPTs information where labname is required
                    Create temp table combining yesterdays appointments, chemo orders and labs from Mosaiq
                    Begin with combined MQ information (Appt, chemo, Labs)
                    INNER join for pharma patients enrolled
                    LEFT join lab CPTs, notes if available
                    LEFT join calendar name if available
  --  Criteria:     Only include patient's current calendar (exclude previous/history)
  --  Note:         MQ data imported on Monday's inclusive of previous 3 days (Friday, Sarurday and Sunday)
  --  Aliases:      dm_study_current = dmsc, dm_patient = dmp, dm_calendar = dmc
                    mq_appointments = mqA, mq_chemos = mqC, mq_labs = mql, labs_cpts = lcpt
                    temp_mq_data = tmqD, temp_DM_Patient_Industrial = tpats, 
                    temp_labs_cpts = tcpts, temp_curcalname = tcal
  --  Group:        Finance/Billing
  --  Project:      Velos Calendars
  --  Author:       Rick Compton
  --  Created:      November 2020
  --  Modified:     2020-Feb-8                  
  --  Formerly:     sp_DM_Patient_Enroll_Industrial
\*********************************************************************************************************************************************/

/** TEMPORARY TABLE for patients on industrial trials  **/
DROP TEMPORARY TABLE IF EXISTS temp_DM_Patient_Industrial;
CREATE TEMPORARY TABLE temp_DM_Patient_Industrial
SELECT DISTINCT
  dmsc.pkStudy_st,
  dmsc.studyNumber_st,
  dmsc.title_st AS studyTitle_st, 
  dmp.patStudyId_pp,
  dmp.personCode_p,
  UPPER(REPLACE(CONCAT(COALESCE(dmp.patLast_p,''), ', ',COALESCE(dmp.patFirst_p,''), ' ', -- pat first and last name, uppercase, replace double spaces with single space, uppercase
    COALESCE(IF(LENGTH(dmp.patMiddle_p) > 0,CONCAT(dmp.patMiddle_p, '.'),'')) -- pat middle name and "." if populated
    ),'  ',' ')) AS `patName_p`
FROM dm_study_current dmsc
    LEFT JOIN dm_patient dmp ON dmsc.pkStudy_st = dmp.pkStudy_st
WHERE
    dmp.statusIsCurrentFlag_pps = 'Y' -- limit patient status to flagged current status
    AND dmp.enroll_Dt_pp IS NOT NULL -- limit to only enroll date values
    AND dmp.discontinueDt_pp IS NULL -- limit to only patient protocols without a discontinue date (related when a patient changes calendars - records will be in dm_patient)
    AND dmsc.researchType_st_lu = 'Industrial' -- limit to only Industrial a.k.a. "Pharma" trials
AND dmp.personCode_p REGEXP '^-?[0-9]+$' -- limit to only numerical values that will map to MRN in Mosaiq
;

/** TEMPORARY TABLE for calendar name **/
DROP TEMPORARY TABLE IF EXISTS temp_curcalname;
CREATE TEMPORARY TABLE temp_curcalname
  SELECT DISTINCT
    dmc.personCode_p,
    dmc.scheduleName_ea
  FROM dm_calendar dmc
  WHERE dmc.statusDesc_se1 = 'Current Schedule' -- limit to only current schedules as only one at a time can be active
;

/** TEMPORARY TABLE for lab CPTs **/
DROP TEMPORARY TABLE IF EXISTS temp_labs_cpts;
CREATE TEMPORARY TABLE temp_labs_cpts
  SELECT DISTINCT
    *
  FROM ref_labs_cpts
  WHERE labdesc <> '' -- labdesc is required to support join below
;

/** TEMPORARY TABLE for Mosaiq data from 3 source extracts - appts, chemo orders and labs from yesterday **/
DROP TEMPORARY TABLE IF EXISTS temp_mq_data;
CREATE TEMPORARY TABLE temp_mq_data
  SELECT
    mqA.patient_name      AS `PatientName_mq`,
    mqA.mrn               AS `MRN_mq`,
    mqA.app_dttm          AS `ApptDate_mq`,
    mqA.activity_desc     AS `Activity_mq`, -- corresponds to an E&M or an infusion apppointment or an RO treatment (could be some other types)
    mqA.provider_initials AS `Provider_mq`,
    mqa.location          AS `Location_mq`,
    ''                    AS `DrugName_mq`,
    ''                    AS `LabName_mq`,
    ''                    AS `LabCode_mq`,
    ''                    AS `LabNotes_mq`,
    'Appt'                AS `Source_mq`
  FROM mq_appointments mqA
  UNION SELECT 
    mqC.patient_name,
    mqC.mrn,
    mqC.app_dttm,
    '',
    mqC.provider,
    '',
    mqC.drug_name, -- this is the Chemo drug ordered.  Usually there will be another row for the appointment from above (like 1Hr infusion)
    '',
    '',
    '',
    'Chemo'
  FROM mq_chemos mqC
  UNION SELECT 
    mql.patient_name,
    mql.mrn,
    mql.app_dttm,
    '',
    mql.provider,
    '',
    '',
    mql.lab_name, -- this is the lab ordered, the patient may or may not have a corresponding appointment from appt. above (likely yes)
    mql.lab_code,
    mql.condition_notes,
    'Labs'
  FROM mq_labs mql
;

/** Combine temp tables from above **/
DROP TEMPORARY TABLE IF EXISTS tmqD;
CREATE TEMPORARY TABLE tmqD
  SELECT DISTINCT
     tpats.studyNumber_st, tpats.studyTitle_st, tpats.patStudyId_pp, tpats.patName_p
    ,tmqD.*
    ,tcpts.cpt, tcpts.cpt_additional, tcpts.labname_tricore, tcpts.map_status
    ,tcal.scheduleName_ea
    ,CURRENT_TIMESTAMP() AS `xDMrunDt`
  FROM temp_mq_data tmqD
    INNER JOIN temp_DM_Patient_Industrial     tpats    ON tmqD.MRN_mq = tpats.personCode_p -- link where MRN exists on Industrial(pharma) trial 
    LEFT JOIN temp_labs_cpts                  tcpts    ON tcpts.labdesc = tmqD.LabName_mq -- add if ref_labs_cpts are available
    LEFT JOIN temp_curcalname                 tcal     ON tmqD.MRN_mq = tcal.personCode_p -- add patient's current calendar if available
  ;  
/**********************************************************************************************************************************/

/** Place yesterday into history TABLE **/
INSERT INTO dm_PharmaPats_H
SELECT * from dm_PharmaPats_YDA;

/** BEGIN POPULATE TABLE **/
TRUNCATE TABLE dm_PharmaPats_YDA;
INSERT INTO dm_PharmaPats_YDA
SELECT * from tmqD;

/** Drop temporary tables created for use in this stored procedure **/
DROP TABLE temp_curcalname;
DROP TABLE temp_labs_cpts;
DROP TABLE temp_DM_Patient_Industrial;
DROP TABLE temp_mq_data;
DROP TABLE tmqD;

END;
