DROP PROCEDURE IF EXISTS minivelos.sp_DM_Patient;
CREATE PROCEDURE minivelos.`sp_DM_Patient`()
BEGIN
   /*******************************************************************************************************************************  
   **  Purpose:    Gather patient information including PHI as related to studies and patient status records
   **  Issue:      Patient information will contain PHI
   **  Method:     Start with patient protocol table and add others as needed through left joins                  
   **  Exclusions: Active Patient Protocol records only (er_patProt.PATPROT_STAT = 1)
   **  Aliases:    p = person, pp = patprot, pid = patperID,  pss  = patstudystat,
   **              s = site,   st = study,   stid = studyid,   stst = studystat, sttm = studyteam, stsi = studysites,
   **
   **  Last update date: 6/30/2021 add address1 and address2 to support project to possibly match with NMTR
   *******************************************************************************************************************************/

/** TEMPORARY TABLE CREATED TO CONCATENATE MULTIPLE RACE DESCRIPTIONS **/

DROP TABLE IF EXISTS temp_AdditionalRace;
CREATE TEMPORARY TABLE temp_AdditionalRace (UNIQUE (fk_person))
SELECT          -- concatenate secondary (additional) race descriptions by person 
B.fk_person,
GROUP_CONCAT(B.additional_race_desc SEPARATOR ' | ') AS additional_race_desc_list
FROM (
      SELECT distinct	-- Get distinct list of secondary (additional) race descriptions for a person
		-- Note** separated by pipe (|) if more than one exists (e.g. pk_person = '67420')
        A.FK_person,
        A.additional_race_desc
        FROM (
              SELECT	-- get name for each additional race
                  er_person_add_race.FK_Person, 
                  er_person_add_race.pkPersonAddRace,
                  er_person_add_race.person_add_race, 
                  er_codeLst.codelst_desc AS additional_race_desc     
              FROM er_person_add_race   -- pivot table with Person Key /Additional Race Keys 
              LEFT JOIN er_codelst ON er_person_add_race.person_add_race = er_codeLst.PK_CODELST
			  WHERE person_add_race IS NOT NULL AND person_add_race <> ' '  -- exclude NULLs and spaces
              ) AS A
       ) AS B
GROUP BY fk_person
ORDER BY fk_person;
 
/** TEMPORARY TABLE CREATED TO RETRIEVE ETHNICITY DESCRIPTIONS -- could have multiples, but none as of June 2020 **/ 

DROP TABLE IF EXISTS temp_AdditionalEthnicity;
CREATE TEMPORARY TABLE temp_AdditionalEthnicity (UNIQUE(pk_person))
SELECT 
  A.pk_person,
  SUBSTRING(pEthAdd.codelst_desc, 1, 20)  AS  additional_ethnicity_desc     
FROM 
  (
    SELECT
      p.pk_person,
      p.person_add_ethnicity,
      CAST(RTRIM(p.person_add_ethnicity) as unsigned) AS person_add_ethnicity_int
    FROM person p   -- 2841
    WHERE p.person_add_ethnicity IS NOT NULL AND p.person_add_ethnicity <> ' '
  ) AS A
 LEFT JOIN er_codelst pEthAdd    ON A.person_add_ethnicity_int  = pEthAdd.pk_codelst   
 ;
 
/** TEMPORARY TABLE CREATED TO RETRIEVE ACTIVE PATIENT PROTOCOL -- application creates an INACTIVE record when calendars are in use on the study **/ 
/**********************************************************************************************************************************
** Purpose:  Get associated patient to protocol for reporting
** Issue:    Multiple associations can be made between patient and studies some of which occur when calendars are in use on the study
** Method:   Limit to where the patient protocol status = 1 
*/
DROP TABLE IF EXISTS temp_PatProt;
CREATE TEMPORARY TABLE temp_PatProt
SELECT 
  A.*
FROM 
  (
    SELECT
      *
    FROM er_patProt
    WHERE PATPROT_STAT = 1
  ) AS A 
 ;
 
/**********************************************************************************************************************************/
/** POPULATE TEMPORARY TABLE WITH ALL DATA RELATED TO PATIENTS AND STUDIES ********************************************************/

DROP TEMPORARY TABLE IF EXISTS temp_dm_patient;
CREATE TEMPORARY TABLE temp_dm_patient
SELECT 
   /* Table Primary Keys */
    pp.pk_patprot                                       AS pkPatProt_pp,
    pp.fk_study                                         AS pkStudy_st,
    p.pk_person                                         AS pkPerson_p,        /*person.pk_person = pat_perid.fk_per = er_patProt.fk_per = er_patStudyStat.fk_per*/
    p.fk_site                                           AS pkSiteRegistered_s,
    pp.fk_site_enrolling                                AS pkSiteEnrolled_s,
    pf.fk_site                                          AS pkSiteFacility_s,
    pss.pk_patstudystat                                 AS pkPatStudyStat_pps,
    
/****************************************************************************************************/
/** ER_PATPROT:   Screening/Enrollment - Patient Study (protocol) Details **/
    st.study_number                                     AS studyNumber_st,
    RTRIM(SUBSTRING(pp.patprot_patstdid, 1, 50))        AS patStudyId_pp,     /** patprot.patstdid is assigned to person by the study, may be same as or different from person.person_code **/
    DATE_FORMAT(pp.patProt_enroldt, '%Y%m%d')           AS enrollDt_pp,
    ppEnroll.usr_lastname                               AS enrollByLast_pp_lu,              
    ppEnroll.usr_firstname                              AS enrollByFirst_pp_lu,
    RTRIM(SUBSTRING(ppEnrollSite.site_name, 1, 50))     AS enrollOrg_pp_lu,
    RTRIM(SUBSTRING(sType.codelst_desc,1,25))           AS siteType_stst_lu,    /**Add field: 7/30/2020** used to distinguish alliance member vs site (eg pkstudy=4031 "UNM 1419" contains patient enrolled at both) **/
    CASE
      WHEN pp.patprot_stat = 1 THEN 'Y'
      ELSE 'N'
    END                                                 AS enrollmentIsActiveFlag_pp, /** value will always = 'Y' based on logic in temp_PatProt filter patprot_stat = 1 **/
    ppAssign.usr_lastname                               AS assignToLast_pp_lu,
    ppAssign.usr_firstname                              AS assignToFirst_pp_lu,
    ppPhys.usr_lastname                                 AS physicianLast_pp_lu,   
    ppPhys.usr_firstname                                AS physicianFirst_pp_lu,
    SUBSTRING(ppTreatLoc.codelst_desc, 1, 50)           AS treatmentLoc_pp_lu,           /** subset of treatmentOrg_pp_lu **/
    ppTreatSite.site_name                               AS treatmentOrg_pp_lu,           
    OthDisCd.codelst_desc                               AS diseaseCodeOther_pp_lu,  
    CASE
      WHEN pp.patProt_Consign = 1 THEN 'Y'
      ELSE 'N'
    END                                                 AS consentSignedFlag_pp,
    DATE_FORMAT(pp.patprot_consigndt, '%Y%m%d')         AS consentSignedDt_pp,
    DATE_FORMAT(pp.patprot_discdt, '%Y%m%d')            AS discontinueDt_pp,
    RTRIM(SUBSTRING(pp.patprot_reason,1,250))           AS discontinueReason_pp,
    DATE_FORMAT(pp.patprot_start, '%Y%m%d')             AS startDt_pp,             
    DATE_FORMAT(pp.date_of_death, '%Y%m%d')			        AS deathDt_pp,   -- See also dod_p

 /** ER_PATPROT -- Patient Death related to study info -- but not including the primary field for death related to study **/   
    RTRIM(SUBSTRING(DthStdRel.codelst_desc,1,250))      AS deathStudyRelated_pp_lu,
    RTRIM(SUBSTRING(pp.death_std_rltd_other,1,250))     AS deathStudyRelatedOther_pp,    -- This has some weird values, but may be useful in conjunction with FK_Codelst_ptst_dth_stdrel
 
 /** ER_PATPROT  -- Record Audit Info */
    DATE_FORMAT(pp.created_on, '%Y%m%d')                AS createDt_pp,
    ppCreateBy.Usr_Lastname                             AS createByLast_pp_lu,
    ppCreateBy.usr_FirstName                            AS createByFirst_pp_lu,
    DATE_FORMAT(pp.LAST_MODIFIED_DATE, '%Y%m%d')        AS modDt_pp,
    ppModBy.usr_LastName                                AS modByLast_pp_lu,
    ppModBy.usr_FirstName                               AS modByFirst_pp_lu,

/****************************************************************************************************/
/** ER_PATSTUDYSTAT: patience sas re;ated to a specific study **/
  /** Patient Screening details **/          
    pss.screen_number                                   AS screenNumber_pss,
    pssScreener.usr_lastname                            AS screenByLast_pss_lu,            
    pssScreener.usr_firstname                           AS screenByFirst_pss_lu,   
    RTRIM(SUBSTRING(pssScrOut.codelst_desc,1,250))      AS screenOutcome_pss_lu,
 
  /** ER_PATSTUDYSTAT --Patient Study Status info **/
    RTRIM(SUBSTRING(pssStat.codelst_desc,1,50))         AS status_pss_lu,      
    DATE_FORMAT(pss.PatStudyStat_date, '%Y%m%d')        AS statusDt_pss,
    DATE_FORMAT(pss.PatStudyStat_Endt, '%Y%m%d')        AS statusEndDt_pss,
    CASE
      WHEN pss.current_stat  = 1 THEN 'Y'
      ELSE 'N'
    END                                                 AS statusIsCurrent_pps,
    RTRIM(SUBSTRING(pssReason.codelst_desc,1,250))      AS statusReason_pps_lu,
    RTRIM(SUBSTRING(pss.patstudystat_note,1,250))       AS note_pps,      -- Useful info -- may include as hover over in Tableau
    pss.inform_consent_ver                              AS consentVersion_pss,  
          
  /** ER_PATSTUDYSTAT -- Record Audit Info **/
    DATE_FORMAT(pss.CREATED_ON, '%Y%m%d')               AS createDt_pss,
    pssCreateBy.usr_LastName                            AS createByLast_pss_lu,  
    pssCreateBy.usr_FirstName                           AS createByFirst_pss_lu,
    DATE_FORMAT(pss.LAST_MODIFIED_DATE, '%Y%m%d')       AS modDt_pss,
    pssModBy.usr_LastName                               AS modByLast_pss_lu,
    pssModBy.usr_FirstName                              AS modByFirst_pss_lu,

/****************************************************************************************************/    
/** ER_PatFacility **Serves as a link between a study at a given facility(= patprot-enrolling-site) to the patient **/
    pf.pat_facilityid                                   AS facilityID_pf,  -- patient identifier for the facility (patprot-enrolling-site)
    CASE
      WHEN pf.pat_accessRight = 0 THEN 'Revoked'
      WHEN pf.pat_accessRight = 7 THEN 'Granted'
      ELSE ''
    END                                                 AS accessRight_pf,
    CASE
      WHEN pf.patfacility_default = 1 THEN 'Y'
      ELSE 'N'
    END                                                 AS facilityIsDefaultFlag_pf,
    pfProv.usr_lastName                                 AS providerLast_pf,
    pfProv.usr_firstName                                AS providerFirst_pf, 
    pf.patfacility_otherprovider                        AS providerOther_pf,
    DATE_FORMAT(pf.patfacility_regdate, '%Y%m%d')       AS registerDate_pf,
          
/****************************************************************************************************/
/** PERSON: patient information **/
  /** patient name, dob, dod, survival status **/
    p.person_code                                       AS personCode_p, -- MRN or non-hsc facility person id  -- used in UI, but may not be unique
    RTRIM(SUBSTRING(p.person_lname, 1, 30))             AS patLast_p,
    RTRIM(SUBSTRING(p.person_fname, 1, 30))             AS patFirst_p,
    RTRIM(SUBSTRING(p.person_mname, 1, 20))             AS patMiddle_p,                    
    DATE_FORMAT(p.person_dob, '%Y%m%d')                 AS birthDt_p,
    RTRIM(SUBSTRING(pStat.codelst_desc, 1, 20))         AS survivalStat_p_lu,
    DATE_FORMAT(p.person_deathdt, '%Y%m%d')             AS deathDt_p,                      -- See also deathDt_pp --
    RTRIM(SUBSTRING(pDthCause.codelst_desc, 1, 10))     AS deathCause_p_lu,
    RTRIM(SUBSTRING(p.cause_of_death_other, 1, 200))    AS deathCauseOther_p,
   
  /** Demographics Personal Details **/
    SUBSTRING(pGender.codelst_desc, 1, 20)              AS gender_p,
    SUBSTRING(pEthnicity.codelst_desc, 1, 20)           AS ethnicity_p,
    temp_AdditionalEthnicity.additional_ethnicity_desc  AS ethnicityAdditional_p_lu,
    SUBSTRING(pRace.codelst_desc, 1, 50)                AS race_p_lu,
    temp_AdditionalRace.additional_race_desc_list       AS raceAdditional_p_lu,
    -- NOTE pk_person 67420 has primary and secondary race separated by comma

  /** Demographics Contact Information **/
    RTRIM(SUBSTRING(p.person_city, 1, 100))             AS patCity_p,                      
    RTRIM(SUBSTRING(p.person_state, 1, 100))            AS patState_p,               
    RTRIM(SUBSTRING(p.person_county, 1, 100))           AS patCounty_p,                    
    RTRIM(SUBSTRING(p.person_zip, 1, 20))               AS patZip_p,                
    RTRIM(SUBSTRING(p.person_country, 1, 100))          AS patCountry_p,   
   
  /** Registration Details **/
    RTRIM(SUBSTRING(pRegSite.site_name, 1, 50))         AS registerOrg_p_lu, -- Registering Organization for Patient --
    DATE_FORMAT(p.person_regdate, '%Y%m%d')             AS registerDt_p,
    pRegBy.usr_lastName                                 AS registerByLast_p_lu,
    pRegBy.usr_firstname                                AS registerByFirst_p_lu,
   
  /** PERSON -- Record Audit Info **/
    DATE_FORMAT(p.created_on, '%Y%m%d')                 AS createDt_p, -- 7/30/2020 add date format '%Y%m%d'
    pCreateBy.Usr_Lastname                              AS createByLast_p_lu,
    pCreateBy.usr_FirstName                             AS createByFirst_p_lu,
    DATE_FORMAT(p.last_modified_date, '%Y%m%d')         AS modDt_p, -- 7/30/2020 add date format '%Y%m%d'
    pModBy.Usr_Lastname                                 AS modByLast_p_lu,         
    pModBy.usr_FirstName                                AS modByFirst_p_lu,     

  /** PAT_PerID -- patient-level disease site only **/
    refDisease.description                              AS diseaseType_pid_lu,
    CURRENT_TIMESTAMP()                                 AS xDMrunDt,
    RTRIM(SUBSTRING(p.PERSON_ADDRESS1, 1, 100))         AS patAddress1_p, -- 6/30/2021 add to support project to possibly match with NMTR
    RTRIM(SUBSTRING(p.PERSON_ADDRESS2, 1, 100))         AS patAddress2_p -- 6/30/2021 add to support project to possibly match with NMTR
 
/**********************************************************************************************************************************/ 
FROM temp_PatProt pp
LEFT JOIN er_study st           ON pp.fk_study                    = st.pk_study
LEFT JOIN er_site ppEnrollSite  ON pp.fk_site_enrolling           = ppEnrollSite.pk_site
LEFT JOIN er_codelst sType      ON ppEnrollSite.fk_codelst_type   = sType.pk_codelst
LEFT JOIN er_user ppEnroll      ON pp.fk_user                     = ppEnroll.pk_user
LEFT JOIN er_user ppAssign      ON pp.fk_userAssto                = ppAssign.pk_user
LEFT JOIN er_user ppPhys        ON pp.patprot_physician           = ppPhys.pk_user
LEFT JOIN er_codelst ppTreatLoc ON pp.fk_codelstloc               = ppTreatLoc.pk_codelst
LEFT JOIN er_site ppTreatSite   ON pp.patprot_treatingorg         = ppTreatSite.pk_site
LEFT JOIN er_codelst DthStdRel  ON pp.fk_codelst_ptst_dth_stdrel  = DthStdRel.pk_codelst
LEFT JOIN er_codelst OthDisCd   ON pp.patprot_othr_dis_code       = OthDisCd.pk_codelst
          
LEFT JOIN er_patstudystat pss   ON pp.fk_per                      = pss.fk_per   AND st.pk_study = pss.fk_study
LEFT JOIN er_codelst pssStat    ON pss.fk_codelst_stat            = pssStat.pk_codelst
LEFT JOIN er_user pssScreener   ON pss.screened_by                = pssScreener.pk_user
LEFT JOIN er_codelst pssScrOut  ON pss.screening_outcome          = pssScrOut.pk_codelst
LEFT JOIN er_codelst pssReason  ON pss.patstudystat_reason        = pssReason.pk_codelst AND pss.patstudystat_reason IS NOT NULL

LEFT JOIN er_patFacility pf     ON pp.fk_per                      = pf.fk_per    AND pp.fk_site_enrolling = pf.fk_site 
LEFT JOIN er_user pfProv        ON pf.patFacility_Provider        = pfProv.pk_user

LEFT JOIN person p              ON pp.fk_per                      = p.pk_person
LEFT JOIN er_codelst pStat      ON p.fk_codelst_pstat             = pstat.pk_codelst
LEFT JOIN er_codelst pDthCause  ON p.fk_codelst_pat_dth_cause     = pDthCause.pk_codelst
LEFT JOIN er_codelst pGender    ON p.fk_codelst_gender            = pGender.pk_codelst
LEFT JOIN er_codelst pEthnicity ON p.fk_codelst_ethnicity         = pEthnicity.pk_codelst  -- system allows comma separated keys, but is not used as of 06/2020
LEFT JOIN temp_AdditionalEthnicity    ON p.pk_person              = temp_AdditionalEthnicity.pk_person     
LEFT JOIN er_codelst pRace      ON p.fk_codelst_race              = pRace.pk_codelst
LEFT JOIN temp_AdditionalRace   ON p.pk_person                    = temp_AdditionalRace.fk_person     --   p.person_add_race can have a pipe-delimited (|) list keys
LEFT JOIN er_site pRegSite      ON p.fk_site                      = pRegSite.pk_site
LEFT JOIN er_user pRegBy        ON p.person_regby                 = pRegBy.pk_user

LEFT JOIN pat_perid pidDisease  ON p.pk_person                    = pidDisease.fk_per AND pidDisease.fk_codelst_idtype = 8101 /*'Disease Type'*/
LEFT JOIN ref_disease_site refDisease   ON pidDisease.perid_id    = refDisease.value    
         
LEFT JOIN er_user ppCreateBy    ON pp.creator                     = ppCreateBy.pk_user
LEFT JOIN er_user ppModBy       ON pp.last_modified_by            = ppModBy.pk_user
LEFT JOIN er_user pssCreateBy   ON pss.creator                    = pssCreateBy.pk_user
LEFT JOIN er_user pssModBy      ON pss.last_modified_by           = pssModBy.pk_user
LEFT JOIN er_user pCreateBy     ON p.creator                      = pCreateBy.pk_user
LEFT JOIN er_user pModBy        ON p.last_modified_by             = pModBy.pk_user
;
/**********************************************************************************************************************************/

/* BEGIN POPULATE TABLE  */
TRUNCATE TABLE minivelos.dm_patient;
INSERT INTO minivelos.dm_patient
SELECT * from temp_dm_patient;
 
/**  Drop temporary tables created for use in this stored procedure **/
DROP TABLE temp_AdditionalRace;
DROP TABLE temp_AdditionalEthnicity;
DROP TABLE temp_PatProt;
DROP TABLE temp_dm_patient;
 
END;
