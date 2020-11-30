DROP PROCEDURE IF EXISTS minivelos.sp_DM_Accruals;
CREATE PROCEDURE minivelos.`sp_DM_Accruals`()
BEGIN
   /**************************************************************************************************************************\
  **  Purpose:    Combine study/patient information exluding PHI for reporting accruals criteria
  **  Issue:      Accrual information will NOT contain PHI and be DISTINCT based on included fields
  **  Method:     Reference study current status flag so that only one record is returned
                  Then add additional patient information related to person enrolled
  **  Exclusions: Only current patient study status records
                  Enroll Dates Not Null
                  Discontinue Dates Null
  **  Aliases:    dmsc=dm_study_current
                  dmp=dm_patient
  ** Last update date: 2020-Aug-28
  \**************************************************************************************************************************/
   
/****************************************************************************************************************************/
/* POPULATE TEMPORARY TABLE *************************************************************************************************/
DROP TEMPORARY TABLE IF EXISTS temp_dm_Accruals;

CREATE TEMPORARY TABLE temp_dm_Accruals
SELECT DISTINCT
  /* Study information */
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
  
  /* Enrollment information */
  dmp.pkPatStudyStat_pps,
  dmp.pkSiteFacility_s,
  dmp.siteType_stst_lu, -- ** identifies type of enrollment (Alliance Member/Site -- "UNM - CRTC" consideredd lead and often reported separetly from NMCCA affiliate sites
  dmp.registerOrg_p_lu,
  dmp.enrollOrg_pp_lu,
  dmp.treatmentOrg_pp_lu,
  dmp.enroll_Dt_pp,
  CONCAT(dmp.enrollByFirst_pp_lu, ' ', dmp.enrollByLast_pp_lu)            AS `enrollByName_pp`,
  CONCAT(dmp.assignToFirst_pp_lu, ' ', dmp.assignToLast_pp_lu)            AS `assignToName_pp`,
  CONCAT(dmp.physicianFirst_pp_lu, ' ', dmp.physicianLast_pp_lu)          AS `physicianName_pp`,
                                                  
  /* Status information - Current status only by site*/
  dmsc.pkSite_s,
  dmsc.organization_stst,
  dmsc.orgStudyStatus_stst_lu,
  dmsc.statusValidFromDt_stst,
  dmsc.statusValidUntilDt_stst,
  dmsc.sampleSizeLocal_stsi,
  dmsc.enrolledCount_stsi,
  
  /* Patient information (NO PHI)*/
  dmp.patStudyId_pp,
  dmp.status_pss_lu,
  dmp.statusDt_pss,

  /* Reference information */
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
  
  /** Audit information - tables: er_Study(st), er_StudyStat(stst), er_PatProt(pp), er_PatStudyStat(pss), Person(p) -- add 8/28/2020 **/
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
    LEFT JOIN dm_patient dmp ON dmsc.pkStudy_st = dmp.pkStudy_st -- join patient to study current record on pkstudy

WHERE
    dmp.statusIsCurrentFlag_pps = 'Y' -- limit patient status to flagged current status
    AND dmp.enroll_Dt_pp IS NOT NULL -- limit to only enroll date values
    AND dmp.discontinueDt_pp IS NULL -- limit to only patient protocols without a discontinue date (related when a patient changes calendars - records will be in dm_patient)
;
 
 /* BEGIN POPULATE TABLE  */
TRUNCATE TABLE minivelos.dm_accruals;
INSERT INTO minivelos.dm_accruals
SELECT * from temp_dm_accruals
;

/**  Drop temporary tables created for use in this stored procedure **/
DROP TABLE temp_dm_Accruals;

END;
