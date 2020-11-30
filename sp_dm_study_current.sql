DROP PROCEDURE IF EXISTS minivelos.sp_DM_Study_Current;
CREATE PROCEDURE minivelos.`sp_DM_Study_Current`()
BEGIN
  /**************************************************************************************************************************\
  **  Purpose:    Limit to one record per Study for relavent information to support accrual/enrollment details
  **  Issue:      Assumption that application will have ONLY ONE RECORD per study
  **  Method:     Reference flag on study status subform "Is study's Current Status".  
                    Include only when it equals 'Y' from the study datamart (dm_study)
  **  Exclusions: Active studies in ref_study_exclusions
  **  Aliases:    dms=dm_study    
                  rcwg=ref_clinical_working_group
                  rpc=ref_program_code
                  rrc=ref_research_category
                  rst=ref_study_type
                  rtl=ref_treatment_line
  ** Last update date: 2020-Sep-25 (RC remove rcwg join and redirect fields to dms)
  \**************************************************************************************************************************/

DROP TABLE IF EXISTS temp_StudyCurrent;
CREATE TEMPORARY TABLE temp_StudyCurrent

/**********************************************************************************************************************************/
SELECT DISTINCT

  /* PK fields, Study Information and Definition */
  dms.pkStudy_st,
	dms.pkSite_s,
  dms.pkStudyStat_stst,
  dms.studyNumber_st,
  CONCAT(dms.piLast_st_lu,', ',dms.piFirst_st_lu)                    AS studyPI_st,
  CONCAT(dms.piLast_st_lu,' ',LEFT(dms.piFirst_st_lu,1))             AS studyPIDT4_st,
  dms.title_st,
  dms.nctNumber_st,
  
  /* Study Details and Sponsor Information */
  dms.cpdmCategory_stid_lu, -- value is NOT in Velos but a logic using values from Clinical Research Category for Summary 4 (INT, OBS, ANC/COR) and Study Type (Tre, or non-tre)
  dms.primaryPurpose_st_lu,
  dms.therapeuticArea_st_lu,
  dms.diseaseSiteNames_st_lu,
  dms.sampleSizeNational_st,
  dms.duration_st,
  dms.durationUnit_st,
  CASE WHEN (dms.sponsor_st_lu = 'Other' OR dms.sponsor_st_lu IS NULL)
    THEN dms.sponsor_st 
    ELSE sponsor_st_lu 
  END                                                                AS fundingSource_st, -- if sponsor dropdown is "Other" or Null then "If other" value, else sponsor selection from dropdown
  dms.sponsorID_st, -- Sponsor ID in Velos
  
  /* Study Design and More Study Details */
  dms.phase_st_lu,
  dms.researchType_st_lu,
  dms.studyScope_st_lu,
  dms.studyType_st_lu,
  rst.DESCRIPTION                                                    AS studyTypeName_rst,
  rst.REPORT_SORT                                                    AS studyTypeNameSort_rst,
  dms.irb_stid,
  dms.irbOther_stid,
  dms.nciNumber_stid,
  dms.allianceOpen_stid,
  dms.ncorpOpen_stid,
  dms.ncorpAccrualType_stid,
  dms.clinicalResearchCat_stid_lu,
  rrc.DESCRIPTION                                                    AS researchCategoryName_rst,
  rrc.REPORT_SORT                                                    AS researchCategoryNameSort_rst,
  dms.programCode_stid,
  rpc.DESCRIPTION                                                    AS programName_rpc,
  rpc.REPORT_SORT                                                    AS programNameSort_rpc,
  dms.totalStudyTarget_stid,
  dms.cwg_stid,
  dms.clinicalWorkingGroup_rcwg,
  dms.clinicalWorkingGroupSort_rcwg,
  treatmentLine_stid,
  rtl.DESCRIPTION                                                    AS treatmentLineName_rtl,
  rtl.REPORT_SORT                                                    AS treatmentLineNameSort_rtl,
  additionalInfo_stid,
  dms.acuityScore_stid,
  
  /* Additional study information */
  dms.studyStartDt_st,
  dms.studyEndDt_st, 
  CONCAT(authorFirst_st_lu,' ' ,authorLast_st_lu)                    AS authorName_st,
  dms.createDt_st,
  CONCAT(dms.createByFirst_st_lu,' ',dms.createByLast_st_lu)         AS createByName_st,
  dms.modDt_st,
  CONCAT(dms.modByFirst_st_lu,' ',dms.modByLast_st_lu)               AS modByName_st,
  
  /* Organization (Site) Status information */
  dms.organization_stst,
  dms.siteType_stst_lu,
  dms.orgStudyStatus_stst_lu,
  dms.statusValidFromDt_stst,
  dms.statusValidUntilDt_stst,
  dms.sampleSizeLocal_stsi,
  dms.enrolledCount_stsi,  -- this is NOT how the status of enrolled is counted. this systematically counts the number of patients which are selected for trial for each Organization
  dms.createDt_stst ,
  CONCAT(dms.createByFirst_stst_lu,' ',dms.createByLast_stst_lu)     AS createByName_stst,
  dms.modDt_stst,
  CONCAT(dms.modByFirst_stst_lu,' ',dms.modByLast_stst_lu)           AS modByName_stst,
  
  /* additional fields from dm_study 9/15/2020 */
  dms.outcome_stst_lu,
  dms.statusEndDt_stst, -- seems to be system generated end date for the row
  dms.statusMeetingDt_stst,
  dms.statusNote_stst,
  dms.studyContactFirst_st_lu,
  dms.studyContactLast_st_lu,
  CONCAT(dms.studyContactFirst_st_lu,' ',dms.studyContactLast_st_lu) AS contactName_stst,
  CURRENT_TIMESTAMP()                                                AS xDMrunDt
/************************************************************************************************************/ 
FROM minivelos.dm_study dms
  LEFT JOIN ref_program_code              rpc   ON rpc.VALUE = dms.programCode_stid -- add reference table program code name
  LEFT JOIN ref_research_category         rrc   ON rrc.VALUE = dms.clinicalResearchCat_stid_lu -- add reference table research category name
  LEFT JOIN ref_study_type                rst   ON rst.VALUE = dms.studyType_st_lu -- add reference table Study Type name 
  LEFT JOIN ref_treatment_line            rtl   ON dms.treatmentLine_stid = rtl.VALUE -- add reference table treatment line name

WHERE
  dms.statusCurrentFlag_stst = 'Y' -- limit to only Y values
  AND NOT EXISTS (SELECT * FROM ref_study_exclusions rse WHERE rse.IS_ACTIVE ='Y' AND rse.PK_STUDY = dms.pkStudy_st) -- exclude studies from ref table which are IsActive=Y
;
/**********************************************************************************************************************************/
 
/* BEGIN POPULATE TABLE  */
TRUNCATE TABLE minivelos.dm_study_current;
INSERT INTO minivelos.dm_study_current
SELECT * from temp_StudyCurrent
;

/*  Drop temporary tables created for use in this stored procedure*/
DROP TABLE temp_StudyCurrent;
/**********************************************************************************************************************************/

END;
