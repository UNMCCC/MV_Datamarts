DROP PROCEDURE IF EXISTS minivelos.sp_DM_Study;
CREATE PROCEDURE minivelos.`sp_DM_Study`()
BEGIN
/****NOTE CHANGE -- change size of length of study_type field in ER_Study table to be 25 to handle upcoming field change (from 3) */

/*******************************************************************************************************************************  
**  Purpose:    Convert Study Disease Site keys into a Concatenated Field of Disease Site Names
**  Issue:      The study disease-site keys are stored as comma-delimited integers in the er_study.er_disease_site field.
**              Need to look up disease name for each field to be used in DT4 reporting
**  Method:     Inigo separated the comma-delimited field into separate pivot table rows by Study PK (er_studydiseasesite).
**              The code below creates a temporary table that looks up each disease site name related to a study PK and 
**              concatenates them into a field for report display
**  Exclusions: None
**  Aliases:    s = site,   st = study,   stid = studyid,   stst = studystat, sttm = studyteam, stsi = studysites,
**                rcwg=ref_clinical_working_group
**  Last update date: 2020-09-25 (RC and Quinn added clinical working group desc and sort)
*/

DROP TABLE IF EXISTS temp_DiseaseNames;
CREATE TEMPORARY TABLE temp_DiseaseNames
SELECT          -- concatenate disease site names for each study PK 
B.fk_study,
GROUP_CONCAT(B.diseaseName SEPARATOR ' | ') AS diseaseSiteNames
FROM (
      SELECT DISTINCT    -- Get distinct list of study and disease names (note - repeated disease sites for some er_study.pk_study rows)
        A.FK_Study,
        A.diseaseName
        FROM (
              SELECT      -- get disease site name for each study/study_disease_site keys
                  FK_Study, 
                  pkstudydiseasesite, 
                  study_disease_site,
                  er_codeLst.codelst_desc AS diseaseName    
              FROM er_studydiseasesite   -- pivot table with Study Key /Disease Site Keys 
              LEFT JOIN er_codelst ON er_studydiseasesite.study_disease_site = er_codeLst.PK_CODELST
              ) AS A
       ) AS B
GROUP BY fk_study
ORDER BY fk_Study;
/**********************************************************************************************************************************/

/**********************************************************************************************************************************
** Purpose:  Get Associated Study Number for reporting
** Issue:    The field study_assoc is a varchar field which needs to join with the er_study primary key field (integer)
** Method:   Convert the er_Study.study_assoc field from varchar to integer and then use that to join with er_study primary key
**           and return study number for the associated study
*/
DROP TABLE IF EXISTS temp_AssocStudy;

CREATE TEMPORARY TABLE temp_AssocStudy
SELECT
B.PK_Study,
B.study_assoc,
B.PK_AssocStudy,
B.Study_Number
FROM (
      SELECT DISTINCT
        A.PK_Study,
        A.study_assoc,
        A.PK_AssocStudy,
        st2.study_number 
        FROM (
              SELECT
                PK_Study,
                study_assoc,
                CAST(study_assoc AS unsigned) AS PK_AssocStudy
              FROM er_study
              ) AS A
        LEFT JOIN er_study st2 ON A.PK_AssocStudy = st2.PK_STUDY
        ) AS B
 ORDER BY B.PK_Study;
/**********************************************************************************************************************************/

/*  GATHER STUDY DATA FROM THE ER_STUDY TABLE AND EXTRACT RELATED FIELDS FROM LOOK-UP TABLES 
**  SECTIONS RELATE TO FRONT-END APP **/

DROP TABLE IF EXISTS temp_DM_Study;
CREATE TEMPORARY TABLE temp_DM_Study
SELECT 
  /**  Table Primary Keys **/
  st.pk_study                                         AS pkStudy_st,
    s.pk_site                                         AS pkSite_s,
    stst.pk_studystat                                 AS pkStudyStat_stst,
    stsi.pk_studysites                                AS pkStudySites_stsi,
    sttm.pk_studyteam                                 AS pkStudyTeam_sttm,

  /** Study Identifier **/
    st.study_number                                   AS studyNumber_st,              -- aka protocol ID, local protocol ID
    
  /** STUDY SUMMARY / STUDY INFORMATION **/
    stCreator.usr_lastname                            AS enteredByLast_st_lu,       -- st.creator; this is the Data Manager
    stCreator.usr_firstname                           AS enteredByFirst_st_lu,     -- if "Velos Admin", then this field is blank
    stPI.usr_lastName 		                            AS piLast_st_lu,   -- st.study_prinv (PI is in Velos)    
    stPI.usr_firstName		                            AS piFirst_st_lu,   
    CASE 
      WHEN st.study_maj_auth = 'Y' THEN 'Y'
      ELSE 'N'
    END                                               AS piMajorAuthFlag_st,   -- values are 'Y' and blank
    st.study_otherprinv	                              AS piOther_st,		      -- "If Other" 
    stCoord.usr_lastname                              AS contactLast_st_lu, 	          -- st.study_coordinator is on UI as "Study Contact",  
    stCoord.usr_firstname                             AS contactFirst_st_lu,
  
  /** STUDY SUMMARY / STUDY DEFINITION SECTION **/
    -- st.study_number at top 
    st.study_title			                              AS title_st,
    st.nct_number 			                              AS nctNumber_st,                -- Number assigned by ClinicalTrials.GOV -used in DT4  may be used for insurance billing
     
  /** STUDY SUMMARY / STUDY DETAILS **/
    SUBSTRING(stPurpose.codelst_desc,1,25)            AS primaryPurpose_st_lu,        -- st.fk_codelst_PURPOSE,		
    st.study_prodname                                 AS agentOrDevice_st,
    RTRIM(SUBSTRING(stDiv.codeLst_desc,1,25))		      AS division_st_lu,              -- st.study_division,	
    RTRIM(SUBSTRING(stTarea.codelst_desc,1,50))	      AS therapeuticArea_st_lu,       -- st.fk_codelst_TAREA,
    temp_DiseaseNames.diseaseSiteNames                AS diseaseSiteNames_st_lu,      -- st.study_disease_site,  -- comma-delimited keys  -- see above
    st.study_nsamplsize		                            AS sampleSizeNational_st,       -- total # all sites for duration of study
    st.study_samplsize                                AS sampleSizeStudy_st,          -- this is NOT the local sample size by site
    st.study_dur			                                AS duration_st,
    st.study_durunit		                              AS durationUnit_st,   
	  st.study_estBeginDt                               AS studyEstBeginDt_st,

  /**  STUDY SUMMARY / STUDY DESIGN **/  
    RTRIM(SUBSTRING(stPhase.codelst_desc,1,50))       AS phase_st_lu,                 -- st.fk_codelst_PHASE, 
    RTRIM(SUBSTRING(stRestype.codelst_desc,1,50))	    AS researchType_st_lu,          -- st.fk_codelst_RESTYPE,
    RTRIM(SUBSTRING(stScope.codelst_desc,1,25))		    AS studyScope_st_lu,            -- st.fk_codelst_SCOPE,
    RTRIM(SUBSTRING(stType.codelst_desc,1,25))		    AS studyType_st_lu,	            -- st.fk_codelst_TYPE, 
    -- Note:  didn't bring randomization field over to minivelos in extract 
    stParent.study_number                             AS studyNumberParent_st_lu,     --  st.STUDY_PARENTID  this is linkedTo
    temp_assocStudy.Study_Number                      AS studyNumberAssoc_st_lu,      --  historic use    this is linkedTo (historically)
    RTRIM(SUBSTRING(stBlind.codelst_desc,1,10))		    AS blindingOption_st_lu,        -- st.fk_codelst_blind,  
    
  /** SPONSOR INFORMATION **/
    SUBSTRING(stSponsor.codelst_desc,1,50)            AS sponsor_st_lu,  	            -- st.fk_codelst_SPONSOR, if "Other", don't include on DT4, see sponsorContact_st field
    st.study_sponsor 		                              AS sponsor_st,	                -- "IF OTHER" - may have both sponsor fields
    st.study_sponsorid		                            AS sponsorID_st,                -- if id differs from studyNumber.  1 for each sponsor (comma-delimited)
    st.study_contact		                              AS sponsorContact_st,		        -- Regulatory  study_contact when sponsor_st_lu='OTHER'; may be multiple names
 
  /** MORE STUDY DETAILS **/
    RTRIM(SUBSTRING(stidIrbNum.studyid_id,1,10))      AS irb_stid,
    RTRIM(SUBSTRING(stidIrbOth.studyid_id,1,100))     AS irbOther_stid,
    st.nci_trial_identifier	                          AS nciTrialId_st,             -- used on DT4 reports  - in UI as "Other Numbers"
    RTRIM(SUBSTRING(stidNciNum.studyid_id,1,100))     AS nciNumber_stid,            -- CALLED "OTHER NUMBERS" in app on 1st half of More Study Details
    RTRIM(SUBSTRING(stidOpnAll.studyid_id,1,1))       AS allianceOpen_stid,         -- in app on 1st half of More Study Details
    RTRIM(SUBSTRING(stidOpnNCR.studyid_id,1,1))       AS ncorpOpen_stid,            -- in app on 1st half of More Study Details
    RTRIM(SUBSTRING(stidNCRtyp.studyid_id,1,25))      AS ncorpAccrualType_stid,
    RTRIM(SUBSTRING(stidProCod.studyid_id,1,5))       AS programCode_stid,          -- NEED REFERENCE TABLE to map from integer to name (hard-coded in eTools)
    CAST(RTRIM(stidTotTar.studyid_id) AS unsigned)    AS totalStudyTarget_stid,
    CAST(RTRIM(stidClWrkG.studyid_id) AS unsigned)    AS cwg_stid,
    RTRIM(SUBSTRING(rcwg.DESCRIPTION,1,50))           AS clinicalWorkingGroup_rcwg,
    CAST(RTRIM(rcwg.REPORT_SORT) AS unsigned)         AS clinicalWorkingGroupSort_rcwg,
    RTRIM(SUBSTRING(stidTrmtLn.studyid_id,1,5))       AS treatmentLine_stid,        -- NEED REFERENCE TABLE to map from integer to name (hard-coded in eTools)
    stidAddInf.STUDYID_ID                             AS additionalInfo_stid,
    stidAcuity.studyid_id                             AS acuityScore_stid,          -- in app on 2nd half of MORE STUDY DETAILS
    CASE 
      WHEN stidClReas.fk_codelst_idType = 7110 THEN 'OBS'
      WHEN stidClReas.fk_codelst_idType = 7111 THEN 'INT'
      WHEN stidClReas.fk_codelst_idType = 7112 THEN 'OTH INT'
      WHEN stidClReas.fk_codelst_idType = 8089 THEN 'ANC/COR'
    END                                               AS clinicalResearchCat_stid_lu,
    -- maybe need to set up cat1 and cat2 for current and new reporting
    CASE
      WHEN stidClReas.fk_codelst_idType IN (7111, 7112) AND stType.codelst_desc	=  'TRE' THEN 'Interventional Treatment'     -- Clinical Research Category is 'INT' or 'OTH INT (7111, 7112) and Primary purpose is 'TREatment'
      WHEN stidClReas.fk_codelst_idType IN (7111, 7112) AND stType.codelst_desc	<> 'TRE' THEN 'Interventional Non-Treatment' -- Clinical Research Category is 'INT' or 'OTH INT (7111, 7112) and Primary purpose  is not 'TREatment'
      WHEN stidClReas.fk_codelst_idType NOT IN (7111, 7112) THEN 'Non-Interventional'   -- Clinical Research Category neither 'INT' nor 'OTH INT (7111, 7112)                                                                             -- all other Clinical Research Categories
      WHEN stidClReas.fk_codelst_idType IS NULL THEN ''  -- See AccrualField Templates
  END                                                 AS cpdmCategory_stid_lu,
    -- st.study_creation_type                as creationType_st,             -- values: D=default, A=Application(IRB), in PROD is alway "DEFAULT" or null - leave out
  /**  STUDY PEOPLE AND ORGS **/
    stAuthor.usr_lastname                             AS authorLast_st_lu, 
    stAuthor.usr_firstname                            AS authorFirst_st_lu,                 -- st.fk_AUTHOR,

  /**  STUDY STATUS HEADER **/ 
    st.study_actualDt                                 AS studyStartDt_st, -- This is called STUDY START DATE on Study Status History header
    st.study_end_date                                 AS studyEndDt_st,    -- When study has a current status of Complete, this is set -- this the correct date for end date
    s.site_name                                       AS organization_stst , -- siteName_stst,  -- stst.fk_site,  REPEATS FOR EACH SITE WHERE STUDY IS INITIATED
    RTRIM(SUBSTRING(sType.codelst_desc,1,25))         AS siteType_stst_lu,    -- this used to distinguish alliance vs other (eg 1490)
    
  /**  STUDY STATUSES ENTRY **/ 
    -- ststType.codelst_desc                             AS statusType_stst_lu,       -- stst.status_type,  -- this is NOT needed -- always "DEFAULT"
    RTRIM(SUBSTRING(ststStat.codelst_desc,1,25))      AS statusOrganization_stst_lu,           -- stst.fk_codelst_studystat,  REPEATS FOR EACH STATUS
    ststDocBy.usr_lastname                            AS documentByLast_stst_lu,    -- auto populated by system of user entering the status
    ststDocBy.usr_firstname                           AS documentByFirst_stst_lu,
    ststAssigned.usr_lastname                         AS assignToLast_stst_lu,  -- status="Working Group Approved", then PI Name
    ststAssigned.usr_firstname                        AS assignToFirst_stst_lu,
    CASE 
      WHEN stst.current_stat = 1 THEN 'Y'
      ELSE 'N'
    END                                               AS statusCurrentFlag_stst,   -- values:  0=not current, 1=current           
    DATE_FORMAT(stst.studystat_date,'%Y%m%d')         AS statusValidFromDt_stst,    -- verfied with Rick
    DATE_FORMAT(stst.studystat_endt,'%Y%m%d')         AS statusEndDt_stst,      -- seems to be system generated end date for the row and is 
    DATE_FORMAT(stst.studystat_validt,'%Y%m%d')       AS statusValidUntilDt_stst,   -- will be blank if isCurrentStat=1; 
    DATE_FORMAT(stst.studystat_meetdt,'%Y%m%d')       AS statusMeetingDt_stst,        -- Date Working Group plans to review status
    RTRIM(SUBSTRING(ststRevBrd.codelst_desc,1,25))    AS reviewBoard_stst,      -- sparsely used (2018)
    RTRIM(SUBSTRING(ststOut.codelst_desc,1,100))      AS outcome_stst_lu,       -- starting to be used
    RTRIM(SUBSTRING(stst.STUDYSTAT_NOTE,1,2000))      AS statusNote_stst,       -- to support weekly status reporting add 9/11/2020
    
  /** STUDY SITE DATA -- This is added via a link after NationalSampleSize is entered for the STUDY --related to both SITE and STUDYSTATUS table **/
     CAST(stsi.studysite_lsamplesize AS unsigned)     AS sampleSizeLocal_stsi,     -- this IS the local sample size by site/organization
     CAST(stsi.studysite_enrcount AS unsigned)        AS enrolledCount_stsi,        -- is this in the UI?  How to check this?
    
  /** STUDY TEAM **/
    sttmRegCoor.usr_Lastname                          AS regCoordPrimLast_sttm_lu,   -- study team   
    sttmRegCoor.usr_firstname                         AS regCoordPrimFirst_sttm_lu, -- study team 

  /** AUDIT DATA TIME STAMPS **/
    /* ER_STUDY */
    stCreator.usr_lastname                            AS enterByLast_st_lu,       -- st.creator; this is the Data Manager
    stCreator.usr_firstname                           AS enterByFirst_st_lu,     -- if "Velos Admin", then this field is blank
    DATE_FORMAT(st.created_on,'%Y%m%d')               AS createDt_st,
    stModBy.USR_LASTNAME                              AS modByLast_st_lu,
    stModBy.USR_FIRSTNAME                             AS modByFirst_st_lu,
    DATE_FORMAT(st.last_modified_date,'%Y%m%d')       AS modDt_st,
    
    /* STUDY STATUS AUDIT FIELDS */
    DATE_FORMAT(stst.created_on,'%Y%m%d')             AS createDt_stst,
    ststCreator.usr_lastname                          AS createByLast_stst_lu,
    ststCreator.usr_firstname                         AS createByFirst_stst_lu,
    DATE_FORMAT(stst.last_modified_date,'%Y%m%d')     AS modDt_stst,                            
    ststModBy.usr_lastname                            AS modByLast_stst_lu,
    ststModBy.usr_firstname                           AS modByFirst_stst_lu,
    CURRENT_TIMESTAMP()                               AS xDMrunDt
/************************************************************************************************************/
FROM er_study st
LEFT JOIN er_codelst stSponsor 	      ON st.fk_codelst_sponsor  	= stSponsor.pk_codelst
LEFT JOIN  er_codelst stPhase 	      ON st.fk_codelst_phase 		  = stPhase.pk_codelst
LEFT JOIN  er_codelst stRestype       ON st.fk_codelst_restype	  = stResType.pk_codelst
LEFT JOIN  er_codelst stScope	        ON st.fk_codelst_scope		  = stScope.pk_codelst
LEFT JOIN  er_codelst stType	 	      ON st.fk_codelst_type		    = stType.pk_codelst
LEFT JOIN  er_codelst stPurpose       ON st.fk_codelst_purpose	  = stPurpose.pk_codelst
LEFT JOIN  er_codelst stTarea	 	      ON st.fk_codelst_tarea		  = stTarea.pk_codelst
LEFT JOIN  er_codelst stDiv		        ON st.study_division		    = stDiv.pk_codelst
LEFT JOIN  er_codelst stBlind		      ON st.fk_codelst_blind		  = stBlind.pk_codelst
LEFT JOIN  er_user stAuthor		        ON st.fk_author				      = stAuthor.pk_user
LEFT JOIN  er_user stCoord			      ON st.study_coordinator	    = stCoord.pk_user
LEFT JOIN  er_user stPI		            ON st.study_prInv			      = stPI.pk_user 
LEFT JOIN  er_user stCreator          ON st.creator               = stCreator.pk_user
LEFT JOIN  er_user stModby            ON st.last_modified_by      = stModby.pk_user
LEFT JOIN  er_study stParent          ON st.study_parentid        = stParent.pk_study
LEFT JOIN  temp_DiseaseNames          ON st.pk_study              = temp_DiseaseNames.fk_Study
LEFT JOIN  temp_AssocStudy            ON st.pk_study              = temp_assocStudy.PK_study
LEFT JOIN  er_studystat stst          ON st.pk_study                   = stst.fk_study
LEFT JOIN  er_codelst ststType        ON stst.status_type              = ststType.pk_codelst
LEFT JOIN  er_codelst ststStat        ON stst.fk_codelst_studystat     = ststStat.pk_codelst
LEFT JOIN  er_codelst ststOut         ON stst.outcome                  = ststOut.pk_codelst
LEFT JOIN  er_site s                  ON stst.fk_site = s.pk_site AND stst.fk_study = st.pk_study
LEFT JOIN  er_codelst sType           ON s.fk_codelst_type             = sType.pk_codelst
LEFT JOIN er_user ststCreator         ON stst.creator                  = ststCreator.pk_user
LEFT JOIN er_user ststModBy           ON stst.last_modified_by         = ststModBy.pk_user
LEFT JOIN er_user ststDocBy           ON stst.fk_user_docBy            = ststDocBy.pk_user
LEFT JOIN er_user ststAssigned        ON stst.studystat_assignedto     = ststAssigned.pk_user
LEFT JOIN er_codelst ststRevBrd       ON stst.fk_codelst_revboard      = ststRevBrd.pk_codelst
LEFT JOIN er_studysites stsi          ON st.pk_study = stsi.fk_study AND s.pk_site = stsi.fk_site
LEFT JOIN er_studyteam sttm           ON st.pk_study = sttm.fk_study AND sttm.fk_codelst_tmrole=8132 AND sttm.study_team_usr_type='D' -- PK_Codelst 8132=Primary Regulatory Coordinator
LEFT JOIN er_user sttmRegCoor         ON sttm.FK_USER                  = sttmRegCoor.pk_user
LEFT JOIN er_studyID stidNciNum       ON st.pk_study = stidNciNum.FK_STUDY AND stidNciNum.fk_codelst_idType = 6068 
LEFT JOIN er_studyID stidProCod       ON st.pk_study = stidProCod.FK_STUDY AND stidProCod.fk_codelst_idType = 7109
LEFT JOIN er_studyID stidOpnAll       ON st.pk_study = stidOpnAll.FK_STUDY AND stidOpnAll.fk_codelst_idType = 8004
LEFT JOIN er_studyID stidOpnNCR       ON st.pk_study = stidOpnNCR.FK_STUDY AND stidOpnNCR.fk_codelst_idType = 8151
LEFT JOIN er_studyID stidNCRtyp       ON st.pk_study = stidNCRtyp.FK_STUDY AND stidNCRtyp.fk_codelst_idType = 12085
LEFT JOIN er_studyID stidAcuity       ON st.pk_study = stidAcuity.FK_STUDY AND stidAcuity.fk_codelst_idType = 11065
LEFT JOIN er_studyID stidTrmtLn       ON st.PK_STUDY = stidTrmtLn.FK_STUDY AND stidTrmtLn.fk_codelst_idType = 9183
LEFT JOIN er_studyID stidClReas       ON st.PK_STUDY = stidClReas.FK_STUDY AND stidClReas.fk_codelst_idType IN (7110, 7111, 7112, 8089) AND stidClReas.studyID_id = 'Y'
LEFT JOIN er_studyID stidClWrkG       ON st.PK_STUDY = stidClWrkG.FK_STUDY AND stidClWrkG.fk_codelst_idType = 8576
LEFT JOIN er_studyID stidTotTar       ON st.PK_STUDY = stidTotTar.FK_STUDY AND stidTotTar.fk_codelst_idType = 12133
LEFT JOIN er_studyID stidAddInf       ON st.PK_STUDY = stidAddInf.FK_STUDY AND stidAddInf.fk_codelst_idType = 8295
LEFT JOIN er_studyID stidIrbNum       ON st.PK_STUDY = stidIrbNum.FK_STUDY AND stidIrbNum.fk_codelst_idType = 8258
LEFT JOIN er_studyID stidIrbOth       ON st.PK_STUDY = stidIrbOth.FK_STUDY AND stidIrbOth.fk_codelst_idType = 8259
LEFT JOIN ref_clinical_working_group    rcwg  ON stidClWrkG.studyid_id = rcwg.VALUE-- add reference table clinical working group name
;
/**********************************************************************************************************************************/
 
/* BEGIN POPULATE TABLE  */
TRUNCATE TABLE minivelos.dm_study;
INSERT INTO minivelos.dm_study
SELECT * FROM temp_DM_Study
;
  
/*  Drop temporary tables created for use in this stored procedure*/
DROP TABLE temp_diseaseNames;
DROP TABLE temp_assocStudy;
DROP TABLE temp_DM_Study;
/**********************************************************************************************************************************/

END;
