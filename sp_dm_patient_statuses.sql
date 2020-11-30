DROP PROCEDURE IF EXISTS minivelos.sp_DM_Patient_Statuses;
CREATE PROCEDURE minivelos.`sp_DM_Patient_Statuses`()
BEGIN
   /**************************************************************************************************************************\
  **  Purpose:    Combine study/patient information including PHI for reporting details for all patient status records
  **  Issue:      Patient information will contain PHI and be DISTINCT based on included fields
  **  Method:     Reference study current status so that only one record is returned per study
                  Then add additional patient information related to person
  **  Exclusions: Discontinue Dates Null 
  **  Aliases:    dmsc=dm_study_current
                  dmp=dm_patient
  ** Last update date: 2020-Sep-30 (Add birthDt_p)
  \**************************************************************************************************************************/
   
/****************************************************************************************************************************/
/** POPULATE TEMPORARY TABLE ************************************************************************************************/
DROP TEMPORARY TABLE IF EXISTS temp_DM_Patient_Statuses;

CREATE TEMPORARY TABLE temp_DM_Patient_Statuses
SELECT DISTINCT
  /** Study information **/
  dmsc.pkStudy_st,
  dmsc.studyNumber_st,
  dmsc.title_st,
  dmsc.studyPI_st,
  dmsc.studyPIDT4_st,
  dmsc.primaryPurpose_st_lu,
  dmsc.diseaseSiteNames_st_lu,
  dmsc.therapeuticArea_st_lu,
  dmsc.phase_st_lu,
  dmsc.researchType_st_lu,
  dmsc.studyType_st_lu,
  dmsc.studyTypeName_rst,
  dmsc.studyTypeNameSort_rst,
  dmsc.cpdmCategory_stid_lu,
  dmsc.sampleSizeNational_st,
  dmsc.totalStudyTarget_stid,
  dmsc.ncorpOpen_stid,
  dmsc.ncorpAccrualType_stid,

  /** Enrollment information **/
  dmp.pkPatProt_pp,
  dmp.pkPatStudyStat_pps,
  dmp.pkSiteFacility_s,
  dmp.siteType_stst_lu, -- ** identifies type of enrollment (Alliance Member/Site -- "UNM - CRTC" considered lead site and often reported separetly from other Alliance Members
  dmp.registerOrg_p_lu,
  dmp.enrollOrg_pp_lu,
  dmp.treatmentOrg_pp_lu,
  dmp.treatmentLoc_pp_lu,
  dmp.enroll_Dt_pp,
  CONCAT(dmp.enrollByFirst_pp_lu, ' ', dmp.enrollByLast_pp_lu)            AS `enrollByName_pp`,
  CONCAT(dmp.assignToFirst_pp_lu, ' ', dmp.assignToLast_pp_lu)            AS `assignToName_pp`,
  CONCAT(dmp.physicianFirst_pp_lu, ' ', dmp.physicianLast_pp_lu)          AS `physicianName_pp`,

  /** Status information - Current status only by site **/
  dmsc.pkSite_s,
  dmsc.organization_stst,
  dmsc.orgStudyStatus_stst_lu,
  dmsc.statusValidFromDt_stst,
  dmsc.statusValidUntilDt_stst,
  dmsc.sampleSizeLocal_stsi,
  dmsc.enrolledCount_stsi,

  /** Patient information (PHI included) **/
  dmp.patStudyId_pp,
  REPLACE(CONCAT(COALESCE(dmp.patFirst_p,''), ' ', COALESCE(dmp.patMiddle_p,''), ' ', COALESCE(dmp.patLast_p,'')),'  ',' ')  AS `patName_p`,
  dmp.personCode_p,
  dmp.birthDt_p, -- add 9/30/2020
	dmp.race_p_lu,
  dmp.raceAdditional_p_lu,
  dmp.ethnicity_p,
  dmp.ethnicityAdditional_p_lu,
  dmp.gender_p,
  dmp.status_pss_lu,
  dmp.statusDt_pss,
  dmp.statusEndDt_pss,
  dmp.statusIsCurrentFlag_pps,
  dmp.survivalStatus_p_lu,
  dmp.statusReason_pps_lu,
  dmp.statusNote_pps_lu,
  dmp.screenOutcome_pss_lu,
  dmp.patZip_p,
  dmp.registerDt_pf,
  dmp.diseaseType_pid_lu,
  dmp.diseaseCodeOther_pp_lu,

  /** Reference information **/
  dmsc.clinicalResearchCat_stid_lu,
  dmsc.researchCategoryName_rst,
  dmsc.researchCategoryNameSort_rst,
  dmsc.programCode_stid,
  dmsc.programName_rpc,
  dmsc.programNameSort_rpc,
  dmsc.cwg_stid,
  dmsc.clinicalWorkingGroup_rcwg,
  dmsc.clinicalWorkingGroupSort_rcwg,
  dmsc.treatmentLine_stid,
  dmsc.treatmentLineName_rtl,
  dmsc.treatmentLineNameSort_rtl,
  
  /** Audit information -- Tables: er_Study, er_StudyStat, er_PatProt, er_patStudyStat, person -- add 8/28/2020 **/
  dmsc.createDt_st, 
  dmsc.createByName_st,
  dmsc.modDt_st,
  dmsc.modByName_st,
  dmsc.createDt_stst,
  dmsc.createByName_stst,
  dmsc.modDt_stst,
  dmsc.modByName_stst,
  dmp.createDt_pp, 
  CONCAT(dmp.createByFirst_pp_lu,' ',dmp.createByLast_pp_lu)          AS `createByName_pp`,
  dmp.modDt_pp,
  CONCAT(dmp.modByFirst_pp_lu,' ',dmp.modByLast_pp_lu)                AS `modByName_pp`,
  dmp.createDt_pss, 
  CONCAT(dmp.createByFirst_pss_lu,' ',dmp.createByLast_pss_lu)        AS `createByName_pss`,
  dmp.modDt_pss,
  CONCAT(dmp.modByFirst_pss_lu,' ',dmp.modByLast_pss_lu)              AS `modByName_pss`,
  dmp.createDt_p, 
  CONCAT(dmp.createByFirst_p_lu,' ',dmp.createByLast_p_lu)            AS `createByName_p`,
  dmp.modDt_p,
  CONCAT(dmp.modByFirst_p_lu,' ',dmp.modByLast_p_lu)                  AS `modByName_p`,
  CURRENT_TIMESTAMP()                                                 AS `xDMrunDt`

FROM minivelos.dm_study_current dmsc
  LEFT JOIN dm_patient dmp ON dmsc.pkStudy_st = dmp.pkStudy_st -- AND dmsc.pkSite_s = dmp.pkSiteFacility_s -- add patient information linking through site facility

WHERE 
  dmp.discontinueDt_pp IS NULL -- limit to only patient protocols without a discontinue date (related when a patient changes calendars - records will be in dm_patient)

  -- ********************** TESTING ******************** --
  -- AND year(dmp.statusDt_pss) >= '2020'
  -- AND dmsc.studyNumber_st =  'ECOG-ACRIN E1Q11'
  -- AND enrollOrg_pp_lu <> 'UNM - CRTC'
  -- AND dmp.patStudyId_pp = '10104'
  -- AND dmsc.pkSite_s <> dmp.pkSiteFacility_s
  -- AND dmp.pkPatProt_pp = '50347'
-- ********************** TESTING ******************** --
;

/** BEGIN POPULATE TABLE  **/
TRUNCATE TABLE minivelos.dm_patient_statuses;
INSERT INTO minivelos.dm_patient_statuses
SELECT * from temp_DM_Patient_Statuses
;

/**  Drop temporary tables created for use in this stored procedure **/
DROP TABLE temp_DM_Patient_Statuses;

END;
